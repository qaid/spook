import Foundation

@Observable
@MainActor
class NetworkMonitor {
    var downloadSpeed: Int64 = 0
    var uploadSpeed: Int64 = 0
    var totalBytesIn: Int64 = 0
    var totalBytesOut: Int64 = 0
    var appTraffic: [AppTraffic] = []

    var onUpdate: ((Int64, Int64) -> Void)?

    private var monitorTask: Task<Void, Never>?
    private var previousBytesIn: Int64 = 0
    private var previousBytesOut: Int64 = 0
    private var previousAppData: [String: (bytesIn: Int64, bytesOut: Int64)] = [:]

    func startMonitoring() async {
        await readInitialStats()

        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.updateStats()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    private func readInitialStats() async {
        let (stats, perAppData) = await Task.detached(priority: .userInitiated) { [self] in
            let s = self.readNetworkStats()
            let p = self.readPerAppStats()
            return (s, p)
        }.value

        previousBytesIn = stats.bytesIn
        previousBytesOut = stats.bytesOut

        for app in perAppData {
            let key = "\(app.processName).\(app.pid)"
            previousAppData[key] = (app.bytesIn, app.bytesOut)
        }
    }

    private func updateStats() async {
        // Run all three system commands concurrently off the main thread
        let (stats, perAppData, connectionsByPid) = await Task.detached(priority: .userInitiated) { [self] in
            async let s = self.readNetworkStats()
            async let p = self.readPerAppStats()
            async let c = self.readConnectionDetails()
            return await (s, p, c)
        }.value

        // --- Everything below runs on @MainActor ---

        // Update total stats
        let bytesInDelta = stats.bytesIn - previousBytesIn
        let bytesOutDelta = stats.bytesOut - previousBytesOut

        downloadSpeed = max(0, bytesInDelta)
        uploadSpeed = max(0, bytesOutDelta)

        totalBytesIn += downloadSpeed
        totalBytesOut += uploadSpeed

        previousBytesIn = stats.bytesIn
        previousBytesOut = stats.bytesOut

        // Record to history
        if downloadSpeed > 0 || uploadSpeed > 0 {
            Task {
                await HistoryStore.shared.recordTotals(bytesIn: downloadSpeed, bytesOut: uploadSpeed)
                await HistoryStore.shared.recordHourlySample(bytesIn: downloadSpeed, bytesOut: uploadSpeed)
            }
        }

        // Update per-app stats
        var updatedApps = perAppData
        var currentKeys = Set<String>()

        for i in updatedApps.indices {
            let key = "\(updatedApps[i].processName).\(updatedApps[i].pid)"
            currentKeys.insert(key)

            if let previous = previousAppData[key] {
                updatedApps[i].speedIn = max(0, updatedApps[i].bytesIn - previous.bytesIn)
                updatedApps[i].speedOut = max(0, updatedApps[i].bytesOut - previous.bytesOut)
                updatedApps[i].previousBytesIn = previous.bytesIn
                updatedApps[i].previousBytesOut = previous.bytesOut
            }
            previousAppData[key] = (updatedApps[i].bytesIn, updatedApps[i].bytesOut)
        }

        // Prune entries for processes no longer in nettop output
        for key in previousAppData.keys where !currentKeys.contains(key) {
            previousAppData.removeValue(forKey: key)
        }

        // Get connection details for active apps
        appTraffic = updatedApps
            .filter { $0.bytesIn > 0 || $0.bytesOut > 0 }
            .map { app in
                var appWithConnections = app
                appWithConnections.connections = connectionsByPid[app.pid] ?? []
                return appWithConnections
            }
            .sorted { $0.totalSpeed > $1.totalSpeed }

        // Record per-app stats to history
        Task {
            await HistoryStore.shared.recordAppStats(appTraffic)
        }

        onUpdate?(downloadSpeed, uploadSpeed)
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
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
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

    // MARK: - Per-App Stats (nettop)

    nonisolated private func readPerAppStats() -> [AppTraffic] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        task.arguments = ["-P", "-L", "1", "-x", "-J", "bytes_in,bytes_out"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else {
                return []
            }

            return parseNettopOutput(output)
        } catch {
            return []
        }
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
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
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
