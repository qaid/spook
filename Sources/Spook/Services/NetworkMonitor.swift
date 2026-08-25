import Foundation

struct SpeedSample {
    let timestamp: Date
    let bytesIn: Int64
    let bytesOut: Int64
}

@Observable
@MainActor
class NetworkMonitor {
    var downloadSpeed: Int64 = 0
    var uploadSpeed: Int64 = 0
    var totalBytesIn: Int64 = 0
    var totalBytesOut: Int64 = 0
    var appTraffic: [AppTraffic] = []

    /// Ring buffer of per-second speed readings for the last hour
    private(set) var recentSamples: [SpeedSample] = []
    private static let maxRecentSamples = 3600  // 1 hour of per-second data

    var onUpdate: ((Int64, Int64) -> Void)?

    /// Whether the detail panel is visible — lsof only runs while true. ponytail: avoids running lsof every second when nobody's looking at connections.
    var isPanelVisible = false

    private var monitorTask: Task<Void, Never>?
    private var previousBytesIn: Int64 = 0
    private var previousBytesOut: Int64 = 0
    private var lastNetstatSampleTime: Date?
    private var previousAppData: [String: (bytesIn: Int64, bytesOut: Int64)] = [:]
    private var connectionsByPid: [pid_t: [Connection]] = [:]
    private var flushTickCount = 0

    // Persistent nettop process state
    private var nettopProcess: Process?
    private var nettopPipe: Pipe?
    private var nettopBuffer = ""
    private var lastNettopSampleTime: Date?
    private var isMonitoring = false

    func startMonitoring() async {
        isMonitoring = true
        await readInitialStats()
        startNettopStream()

        Task {
            await HistoryStore.shared.pruneOldData()
        }

        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.updateStats()
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    break
                }
            }
        }
    }

    func stopMonitoring() {
        isMonitoring = false
        monitorTask?.cancel()
        monitorTask = nil
        stopNettopStream()
    }

    private func readInitialStats() async {
        let stats = await Task.detached(priority: .userInitiated) { [weak self] in
            self?.readNetworkStats() ?? (bytesIn: 0, bytesOut: 0)
        }.value

        previousBytesIn = stats.bytesIn
        previousBytesOut = stats.bytesOut
        lastNetstatSampleTime = Date()
    }

    private func updateStats() async {
        // Run lsof only when the panel is visible; netstat always runs.
        let shouldReadConnections = isPanelVisible
        let (stats, newConnections) = await Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else {
                return ((bytesIn: Int64(0), bytesOut: Int64(0)), [pid_t: [Connection]]())
            }
            async let s = self.readNetworkStats()
            async let c: [pid_t: [Connection]] = shouldReadConnections ? self.readConnectionDetails() : [:]
            return await (s, c)
        }.value

        // --- Everything below runs on @MainActor ---

        if shouldReadConnections {
            connectionsByPid = newConnections
        } else {
            // ponytail: clear connections when the panel is hidden; cache the last result if the reopen delay matters
            connectionsByPid = [:]
        }

        let now = Date()
        let elapsed = lastNetstatSampleTime.map { now.timeIntervalSince($0) } ?? 1.0
        lastNetstatSampleTime = now

        let bytesInDelta = stats.bytesIn - previousBytesIn
        let bytesOutDelta = stats.bytesOut - previousBytesOut

        let safeElapsed = elapsed > 0 ? elapsed : 1.0
        downloadSpeed = Int64(max(0, Double(bytesInDelta)) / safeElapsed)
        uploadSpeed = Int64(max(0, Double(bytesOutDelta)) / safeElapsed)

        totalBytesIn += max(0, bytesInDelta)
        totalBytesOut += max(0, bytesOutDelta)

        previousBytesIn = stats.bytesIn
        previousBytesOut = stats.bytesOut

        // Record to in-memory ring buffer for 1-hour graph
        recentSamples.append(SpeedSample(timestamp: now, bytesIn: downloadSpeed, bytesOut: uploadSpeed))
        if recentSamples.count > Self.maxRecentSamples {
            recentSamples.removeFirst(recentSamples.count - Self.maxRecentSamples)
        }

        // Record to history
        if downloadSpeed > 0 || uploadSpeed > 0 {
            Task {
                await HistoryStore.shared.recordTotals(bytesIn: downloadSpeed, bytesOut: uploadSpeed)
                await HistoryStore.shared.recordHourlySample(bytesIn: downloadSpeed, bytesOut: uploadSpeed)
            }
        }

        // Flush history to disk every ~10s
        flushTickCount += 1
        if flushTickCount >= 10 {
            flushTickCount = 0
            Task {
                await HistoryStore.shared.flush()
            }
        }

        onUpdate?(downloadSpeed, uploadSpeed)
    }

    // MARK: - Per-App Stats (persistent nettop stream)

    private func startNettopStream() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = ["-P", "-L", "0", "-s", "1", "-x", "-J", "bytes_in,bytes_out"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        nettopBuffer = ""

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.appendNettopChunk(chunk)
            }
        }

        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isMonitoring else { return }
                // ponytail: naive restart-after-delay instead of exponential backoff
                try? await Task.sleep(for: .seconds(1))
                if self.isMonitoring {
                    self.startNettopStream()
                }
            }
        }

        do {
            try process.run()
            nettopProcess = process
            nettopPipe = pipe
        } catch {
            nettopProcess = nil
            nettopPipe = nil
        }
    }

    private func stopNettopStream() {
        nettopPipe?.fileHandleForReading.readabilityHandler = nil
        nettopProcess?.terminationHandler = nil
        if nettopProcess?.isRunning == true {
            nettopProcess?.terminate()
        }
        nettopProcess = nil
        nettopPipe = nil
        nettopBuffer = ""
    }

    private static let nettopHeaderMarker = ",bytes_in,bytes_out,"

    /// Accumulate streamed nettop output; each time a new header line arrives, the previously
    /// buffered sample (if any) is complete and gets parsed and delivered.
    private func appendNettopChunk(_ chunk: String) {
        nettopBuffer += chunk

        var lines = nettopBuffer.components(separatedBy: "\n")
        // Keep the last (possibly incomplete) line back in the buffer.
        let trailing = lines.removeLast()

        var currentSampleLines: [String] = []
        for line in lines {
            if line.hasPrefix(",") && line.contains(Self.nettopHeaderMarker) {
                // New sample starting — flush the previous one if it has content.
                if !currentSampleLines.isEmpty {
                    handleNettopSample(currentSampleLines)
                }
                currentSampleLines = []
            } else {
                currentSampleLines.append(line)
            }
        }

        // Re-buffer whatever wasn't flushed yet, plus the trailing partial line.
        nettopBuffer = currentSampleLines.joined(separator: "\n")
        if !nettopBuffer.isEmpty {
            nettopBuffer += "\n"
        }
        nettopBuffer += trailing
    }

    private func handleNettopSample(_ lines: [String]) {
        let output = lines.joined(separator: "\n")
        let perAppData = parseNettopOutput(output)

        let now = Date()
        let elapsed = lastNettopSampleTime.map { now.timeIntervalSince($0) } ?? 1.0
        lastNettopSampleTime = now

        if previousAppData.isEmpty {
            // Seed only — no speeds yet.
            for app in perAppData {
                let key = "\(app.processName).\(app.pid)"
                previousAppData[key] = (app.bytesIn, app.bytesOut)
            }
            return
        }

        applyPerAppSample(perAppData, elapsed: elapsed > 0 ? elapsed : 1.0)
    }

    private func applyPerAppSample(_ perAppData: [AppTraffic], elapsed: Double) {
        var updatedApps = perAppData
        var currentKeys = Set<String>()

        for i in updatedApps.indices {
            let key = "\(updatedApps[i].processName).\(updatedApps[i].pid)"
            currentKeys.insert(key)

            if let previous = previousAppData[key] {
                let deltaIn = updatedApps[i].bytesIn - previous.bytesIn
                let deltaOut = updatedApps[i].bytesOut - previous.bytesOut
                updatedApps[i].speedIn = Int64(max(0, Double(deltaIn)) / elapsed)
                updatedApps[i].speedOut = Int64(max(0, Double(deltaOut)) / elapsed)
                updatedApps[i].previousBytesIn = previous.bytesIn
                updatedApps[i].previousBytesOut = previous.bytesOut
            }
            previousAppData[key] = (updatedApps[i].bytesIn, updatedApps[i].bytesOut)
        }

        // Prune entries for processes no longer in nettop output
        for key in previousAppData.keys where !currentKeys.contains(key) {
            previousAppData.removeValue(forKey: key)
        }

        appTraffic = updatedApps
            .filter { $0.bytesIn > 0 || $0.bytesOut > 0 }
            .map { app in
                var appWithConnections = app
                appWithConnections.connections = connectionsByPid[app.pid] ?? []
                return appWithConnections
            }
            .sorted { $0.totalSpeed > $1.totalSpeed }

        Task {
            await HistoryStore.shared.recordAppStats(appTraffic)
        }
    }

    // MARK: - Total Network Stats (netstat)

    nonisolated private func readNetworkStats() -> (bytesIn: Int64, bytesOut: Int64) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        task.arguments = ["-ib"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else {
                return (0, 0)
            }

            return parseNetstatOutput(output)
        } catch {
            return (0, 0)
        }
    }

    nonisolated private func parseNetstatOutput(_ output: String) -> (bytesIn: Int64, bytesOut: Int64) {
        var totalIn: Int64 = 0
        var totalOut: Int64 = 0

        let lines = output.components(separatedBy: "\n")

        for line in lines {
            let components = line.split(separator: " ", omittingEmptySubsequences: true)

            guard components.count >= 11 else { continue }

            let interface = String(components[0])

            if interface == "lo0" || interface.hasPrefix("utun") || interface.hasPrefix("awdl") {
                continue
            }

            guard interface.hasPrefix("en") else { continue }

            let networkField = String(components[2])
            guard networkField.hasPrefix("<Link#") else { continue }

            if let bytesIn = Int64(components[6]), let bytesOut = Int64(components[9]) {
                totalIn += bytesIn
                totalOut += bytesOut
            }
        }

        return (totalIn, totalOut)
    }

    nonisolated private func parseNettopOutput(_ output: String) -> [AppTraffic] {
        var apps: [AppTraffic] = []

        let lines = output.components(separatedBy: "\n")

        for line in lines {
            // Skip header and empty lines
            if line.isEmpty || line.hasPrefix(",") { continue }

            // Format: process_name.pid,bytes_in,bytes_out,
            let components = line.components(separatedBy: ",")
            guard components.count >= 3 else { continue }

            let processInfo = components[0]
            guard let bytesIn = Int64(components[1]),
                  let bytesOut = Int64(components[2]) else { continue }

            // Parse process name and PID from "process_name.pid"
            let (processName, pid) = parseProcessInfo(processInfo)

            let app = AppTraffic(
                id: processInfo,
                processName: processName,
                pid: pid,
                bytesIn: bytesIn,
                bytesOut: bytesOut,
                previousBytesIn: 0,
                previousBytesOut: 0,
                speedIn: 0,
                speedOut: 0,
                connections: []
            )
            apps.append(app)
        }

        return apps
    }

    nonisolated private func parseProcessInfo(_ info: String) -> (name: String, pid: pid_t) {
        // Format: "process_name.pid" - but process name might contain dots
        // Find the last dot followed by only digits
        if let lastDotRange = info.range(of: ".", options: .backwards) {
            let pidPart = String(info[lastDotRange.upperBound...])
            if let pid = Int32(pidPart) {
                let name = String(info[..<lastDotRange.lowerBound])
                return (name, pid)
            }
        }
        return (info, 0)
    }

    // MARK: - Connection Details (lsof)

    nonisolated private func readConnectionDetails() -> [pid_t: [Connection]] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-i", "-n", "-P"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard let output = String(data: data, encoding: .utf8) else {
                return [:]
            }

            return parseLsofOutput(output)
        } catch {
            return [:]
        }
    }

    nonisolated private func parseLsofOutput(_ output: String) -> [pid_t: [Connection]] {
        var connectionsByPid: [pid_t: [Connection]] = [:]

        let lines = output.components(separatedBy: "\n")

        for line in lines {
            // Skip header
            if line.hasPrefix("COMMAND") { continue }

            let components = line.split(separator: " ", omittingEmptySubsequences: true)
            guard components.count >= 9 else { continue }

            // Parse PID
            guard let pid = Int32(components[1]) else { continue }

            // Parse TYPE (IPv4/IPv6)
            let type = String(components[4])
            guard type == "IPv4" || type == "IPv6" else { continue }

            // Parse NODE (TCP/UDP)
            let node = String(components[7])
            guard node == "TCP" || node == "UDP" else { continue }

            // Parse NAME (connection details)
            let name = String(components[8])

            // Parse connection state if present (last component for TCP)
            var state = ""
            if components.count >= 10 && node == "TCP" {
                state = String(components[9]).trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            }

            // Parse the connection: local->remote or *:port (LISTEN)
            if let connection = parseConnectionName(name, protocolType: node, state: state) {
                if connectionsByPid[pid] == nil {
                    connectionsByPid[pid] = []
                }
                // Avoid duplicates
                if !connectionsByPid[pid]!.contains(where: {
                    $0.remoteAddress == connection.remoteAddress &&
                    $0.remotePort == connection.remotePort
                }) {
                    connectionsByPid[pid]!.append(connection)
                }
            }
        }

        return connectionsByPid
    }

    nonisolated private func parseConnectionName(_ name: String, protocolType: String, state: String) -> Connection? {
        // Format: "local:port->remote:port" or "*:port (LISTEN)"
        if name.contains("->") {
            let parts = name.components(separatedBy: "->")
            guard parts.count == 2 else { return nil }

            let localParts = parts[0].components(separatedBy: ":")
            let remoteParts = parts[1].components(separatedBy: ":")

            guard localParts.count >= 2, remoteParts.count >= 2 else { return nil }

            let localPort = UInt16(localParts.last ?? "0") ?? 0
            let remoteAddress = remoteParts.dropLast().joined(separator: ":")
            let remotePort = UInt16(remoteParts.last ?? "0") ?? 0

            // Skip if remote is localhost
            if remoteAddress == "127.0.0.1" || remoteAddress == "::1" || remoteAddress.hasPrefix("fe80:") {
                return nil
            }

            return Connection(
                remoteAddress: remoteAddress,
                remotePort: remotePort,
                localPort: localPort,
                protocolType: protocolType.lowercased(),
                state: state,
                bytesIn: 0,
                bytesOut: 0,
                resolvedHostname: nil
            )
        }

        return nil
    }
}
