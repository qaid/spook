import SwiftUI
import AppKit

struct AppListView: View {
    let apps: [AppTraffic]
    var directionFilter: TrafficDirection = .all
    var maxTraffic: Int64 = 1
    var monitor: NetworkMonitor?
    @State private var expandedApps: Set<String> = []
    @State private var drillInApp: String?

    var body: some View {
        Group {
            if let drillInApp, let app = apps.first(where: { $0.id == drillInApp }) {
                AppDrillInView(app: app, onBack: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        self.drillInApp = nil
                    }
                })
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(apps) { app in
                            AppRowView(
                                app: app,
                                directionFilter: directionFilter,
                                maxTraffic: maxTraffic,
                                speedHistory: monitor?.appSpeedHistory[app.id] ?? [],
                                isExpanded: expandedApps.contains(app.id),
                                onToggle: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        if expandedApps.contains(app.id) {
                                            expandedApps.remove(app.id)
                                        } else {
                                            expandedApps.insert(app.id)
                                        }
                                    }
                                },
                                onShowAll: {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                        drillInApp = app.id
                                    }
                                }
                            )
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .transition(.opacity)
            }
        }
    }
}

struct AppRowView: View {
    let app: AppTraffic
    var directionFilter: TrafficDirection = .all
    var maxTraffic: Int64 = 1
    var speedHistory: [(in: Int64, out: Int64)] = []
    let isExpanded: Bool
    let onToggle: () -> Void
    var onShowAll: () -> Void = {}
    @State private var isHovered = false

    var relevantSpeed: Int64 {
        switch directionFilter {
        case .download: return app.speedIn
        case .upload: return app.speedOut
        case .all: return app.totalSpeed
        }
    }

    var trafficRatio: CGFloat {
        guard maxTraffic > 0 else { return 0 }
        return CGFloat(relevantSpeed) / CGFloat(maxTraffic)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main row
            Button(action: onToggle) {
                ZStack(alignment: .leading) {
                    // Traffic bar background
                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: CornerRadius.xs)
                            .fill(trafficBarColor.opacity(0.08))
                            .frame(width: geometry.size.width * trafficRatio)
                            .animation(.easeOut(duration: 0.3), value: trafficRatio)
                    }

                    HStack(spacing: Spacing.lg) {
                        // App icon
                        Image(nsImage: app.icon)
                            .resizable()
                            .frame(width: 28, height: 28)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))

                        // App name and totals
                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                            HStack(spacing: Spacing.sm) {
                                Text(app.displayName)
                                    .font(SpookFont.bodyMedium)
                                    .lineLimit(1)

                                // Connection badge
                                if !app.connections.isEmpty {
                                    Text("\(app.connections.count)")
                                        .font(SpookFont.caption2Medium)
                                        .foregroundColor(.spookTextSecondary)
                                        .padding(.horizontal, Spacing.sm)
                                        .padding(.vertical, 1)
                                        .background(
                                            Capsule()
                                                .fill(Color.spookSurfaceElevated)
                                        )
                                }
                            }

                            Text(ByteFormatter.format(app.totalBytes) + " total")
                                .font(SpookFont.caption3)
                                .foregroundColor(.spookTextTertiary)
                        }

                        Spacer()

                        // Current speeds
                        VStack(alignment: .trailing, spacing: Spacing.xxs) {
                            if directionFilter != .upload {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: "arrow.down")
                                        .font(SpookFont.caption3)
                                        .foregroundColor(.spookDownload)
                                    Text(SpeedFormatter.formatCompact(app.speedIn))
                                        .font(SpookFont.caption)
                                        .monospacedDigit()
                                }
                                .opacity(directionFilter == .download ? 1 : (app.speedIn > 0 ? 1 : 0.4))
                            }

                            if directionFilter != .download {
                                HStack(spacing: Spacing.xs) {
                                    Image(systemName: "arrow.up")
                                        .font(SpookFont.caption3)
                                        .foregroundColor(.spookUpload)
                                    Text(SpeedFormatter.formatCompact(app.speedOut))
                                        .font(SpookFont.caption)
                                        .monospacedDigit()
                                }
                                .opacity(directionFilter == .upload ? 1 : (app.speedOut > 0 ? 1 : 0.4))
                            }
                        }
                        .frame(width: 75, alignment: .trailing)

                        // Expand indicator
                        if !app.connections.isEmpty {
                            Image(systemName: "chevron.right")
                                .font(SpookFont.caption2Semibold)
                                .foregroundColor(.spookTextSecondary)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isExpanded)
                        } else {
                            Color.clear
                                .frame(width: 10)
                        }
                    }
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.lg)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(app.connections.isEmpty)
            .background(Color.white.opacity(isHovered ? 0.05 : 0))
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }

            // Expanded content: sparkline + top hosts + actions
            if isExpanded && !app.connections.isEmpty {
                AppExpandedContentView(app: app, speedHistory: speedHistory, onShowAll: onShowAll)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    var trafficBarColor: Color {
        switch directionFilter {
        case .download: return .spookDownload
        case .upload: return .spookUpload
        case .all: return app.speedIn > app.speedOut ? .spookDownload : .spookUpload
        }
    }
}

// MARK: - Expanded Content (V2: sparkline + top 3 hosts + actions)

private struct HostSummary: Identifiable {
    let host: String
    let count: Int
    let hasEstablished: Bool
    var id: String { host }
}

struct AppExpandedContentView: View {
    let app: AppTraffic
    let speedHistory: [(in: Int64, out: Int64)]
    var onShowAll: () -> Void = {}
    @State private var resolvedHosts: [String: String] = [:]
    @State private var processPaths: (exe: String?, cwd: String?) = (nil, nil)

    private var hostSummaries: [HostSummary] {
        var counts: [String: (count: Int, hasEstablished: Bool)] = [:]
        var order: [String] = []
        for connection in app.connections {
            let host = resolvedHosts[connection.remoteAddress] ?? connection.remoteAddress
            if counts[host] == nil {
                order.append(host)
                counts[host] = (0, false)
            }
            var entry = counts[host]!
            entry.count += 1
            if connection.state.uppercased() == "ESTABLISHED" {
                entry.hasEstablished = true
            }
            counts[host] = entry
        }
        return order
            .map { HostSummary(host: $0, count: counts[$0]!.count, hasEstablished: counts[$0]!.hasEstablished) }
            .sorted { $0.count > $1.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if processPaths.exe != nil || processPaths.cwd != nil {
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    if let exe = processPaths.exe {
                        Text(exe)
                            .font(SpookFont.monoCaption2)
                            .foregroundColor(.spookTextSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(exe)
                    }
                    if let cwd = processPaths.cwd, cwd != "/" {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: "folder")
                                .font(SpookFont.caption3)
                            Text(cwd)
                                .font(SpookFont.monoCaption2)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .foregroundColor(.spookTextSecondary)
                        .help(cwd)
                    }
                }
            }

            if speedHistory.count >= 2 {
                MiniSparklineView(history: speedHistory)
                    .frame(height: 44)
            }

            let hosts = hostSummaries
            let top3 = Array(hosts.prefix(3))

            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(top3) { host in
                    HStack(spacing: Spacing.sm) {
                        Circle()
                            .fill(host.hasEstablished ? Color.green : Color.gray)
                            .frame(width: 6, height: 6)

                        Text(host.host)
                            .font(SpookFont.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if host.count > 1 {
                            Text("\(host.count)")
                                .font(SpookFont.caption3)
                                .foregroundColor(.spookTextSecondary)
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule().fill(Color.spookSurfaceElevated)
                                )
                        }

                        Spacer()
                    }
                }
            }

            if hosts.count > 3 {
                Button(action: onShowAll) {
                    Text("Show all \(hosts.count)")
                        .font(SpookFont.caption2)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: Spacing.sm) {
                Button(action: copyHosts) {
                    Text("Copy hosts")
                        .font(SpookFont.caption2)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.xs)
                        .background(
                            Capsule().fill(Color.spookSurfaceElevated)
                        )
                }
                .buttonStyle(.plain)
                .hoverHighlight()
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.leading, Spacing.connectionIndent)
        .padding(.vertical, Spacing.md)
        .background(Color.black.opacity(0.05))
        .task(id: app.connections.map(\.remoteAddress).sorted().joined(separator: ",")) {
            var resolved = resolvedHosts
            for connection in app.connections {
                resolved[connection.remoteAddress] = await DNSResolver.shared.resolve(connection.remoteAddress)
            }
            resolvedHosts = resolved
        }
        .task(id: app.pid) {
            processPaths = ProcessInfoLookup.paths(for: app.pid)
        }
    }

    private func copyHosts() {
        let hosts = hostSummaries.map(\.host)
        let unique = NSOrderedSet(array: hosts).array as? [String] ?? hosts
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(unique.joined(separator: "\n"), forType: .string)
    }
}

// MARK: - Mini Sparkline

struct MiniSparklineView: View {
    let history: [(in: Int64, out: Int64)]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let maxValue = max(history.map(\.in).max() ?? 1, history.map(\.out).max() ?? 1, 1)
            let stepX = history.count > 1 ? width / CGFloat(history.count - 1) : width

            ZStack {
                sparkPath(keyPath: \.in, stepX: stepX, height: height, maxValue: maxValue)
                    .fill(Color.spookDownload.opacity(0.15))
                sparkLine(keyPath: \.in, stepX: stepX, height: height, maxValue: maxValue)
                    .stroke(Color.spookDownload, lineWidth: 1.2)

                sparkPath(keyPath: \.out, stepX: stepX, height: height, maxValue: maxValue)
                    .fill(Color.spookUpload.opacity(0.15))
                sparkLine(keyPath: \.out, stepX: stepX, height: height, maxValue: maxValue)
                    .stroke(Color.spookUpload, lineWidth: 1.2)
            }
        }
        .background(Color.spookSurfaceElevated.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))
    }

    private func points(keyPath: KeyPath<(in: Int64, out: Int64), Int64>, stepX: CGFloat, height: CGFloat, maxValue: Int64) -> [CGPoint] {
        history.enumerated().map { index, sample in
            let value = sample[keyPath: keyPath]
            let x = CGFloat(index) * stepX
            let y = height - (height * CGFloat(value) / CGFloat(maxValue))
            return CGPoint(x: x, y: y)
        }
    }

    private func sparkLine(keyPath: KeyPath<(in: Int64, out: Int64), Int64>, stepX: CGFloat, height: CGFloat, maxValue: Int64) -> Path {
        var path = Path()
        let pts = points(keyPath: keyPath, stepX: stepX, height: height, maxValue: maxValue)
        guard let first = pts.first else { return path }
        path.move(to: first)
        for point in pts.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    private func sparkPath(keyPath: KeyPath<(in: Int64, out: Int64), Int64>, stepX: CGFloat, height: CGFloat, maxValue: Int64) -> Path {
        var path = Path()
        let pts = points(keyPath: keyPath, stepX: stepX, height: height, maxValue: maxValue)
        guard let first = pts.first, let last = pts.last else { return path }
        path.move(to: CGPoint(x: 0, y: height))
        path.addLine(to: first)
        for point in pts.dropFirst() {
            path.addLine(to: point)
        }
        path.addLine(to: CGPoint(x: last.x, y: height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Drill-in (V4: inline drill-in)

private enum DrillInSortColumn: String, CaseIterable {
    case host = "Host"
    case port = "Port"
    case state = "State"
    case proto = "Proto"
}

struct AppDrillInView: View {
    let app: AppTraffic
    let onBack: () -> Void
    @State private var sortColumn: DrillInSortColumn = .host
    @State private var resolvedHosts: [String: String] = [:]
    @State private var processPaths: (exe: String?, cwd: String?) = (nil, nil)

    private var sortedConnections: [Connection] {
        app.connections.sorted { a, b in
            switch sortColumn {
            case .host:
                let hostA = resolvedHosts[a.remoteAddress] ?? a.remoteAddress
                let hostB = resolvedHosts[b.remoteAddress] ?? b.remoteAddress
                return hostA.localizedCaseInsensitiveCompare(hostB) == .orderedAscending
            case .port:
                return a.remotePort < b.remotePort
            case .state:
                return a.state.localizedCaseInsensitiveCompare(b.state) == .orderedAscending
            case .proto:
                return a.protocolType.localizedCaseInsensitiveCompare(b.protocolType) == .orderedAscending
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: Spacing.md) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(SpookFont.caption2Semibold)
                        .foregroundColor(.spookTextSecondary)
                }
                .buttonStyle(.plain)

                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm))

                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(app.displayName)
                        .font(SpookFont.bodyMedium)

                    if let exe = processPaths.exe {
                        Text(exe)
                            .font(SpookFont.monoCaption2)
                            .foregroundColor(.spookTextSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(exe)
                    }
                    if let cwd = processPaths.cwd, cwd != "/" {
                        Text(cwd)
                            .font(SpookFont.monoCaption2)
                            .foregroundColor(.spookTextSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(cwd)
                    }
                }

                Text("\(app.connections.count) connections")
                    .font(SpookFont.caption2)
                    .foregroundColor(.spookTextSecondary)

                Spacer()
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.lg)

            Color.spookBorder
                .frame(height: 0.5)
                .padding(.horizontal, Spacing.lg)

            // Table header
            HStack(spacing: Spacing.md) {
                drillHeaderCell("Host", column: .host, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                drillHeaderCell("Port", column: .port, alignment: .trailing)
                    .frame(width: 50, alignment: .trailing)
                drillHeaderCell("State", column: .state, alignment: .leading)
                    .frame(width: 90, alignment: .leading)
                drillHeaderCell("Proto", column: .proto, alignment: .leading)
                    .frame(width: 40, alignment: .leading)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(sortedConnections) { connection in
                        HStack(spacing: Spacing.md) {
                            Text(resolvedHosts[connection.remoteAddress] ?? connection.remoteAddress)
                                .font(SpookFont.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text("\(connection.remotePort)")
                                .font(SpookFont.monoCaption2)
                                .foregroundColor(.spookTextSecondary)
                                .frame(width: 50, alignment: .trailing)

                            Text(connection.state.lowercased())
                                .font(SpookFont.caption3)
                                .foregroundColor(stateColor(connection.state))
                                .padding(.horizontal, Spacing.sm)
                                .padding(.vertical, Spacing.xxs)
                                .background(
                                    Capsule().fill(stateColor(connection.state).opacity(0.12))
                                )
                                .frame(width: 90, alignment: .leading)

                            Text(connection.protocolType)
                                .font(SpookFont.caption3)
                                .foregroundColor(.spookTextSecondary)
                                .frame(width: 40, alignment: .leading)
                        }
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, Spacing.xs)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
        }
        .task(id: app.connections.map(\.remoteAddress).sorted().joined(separator: ",")) {
            var resolved = resolvedHosts
            for connection in app.connections {
                resolved[connection.remoteAddress] = await DNSResolver.shared.resolve(connection.remoteAddress)
            }
            resolvedHosts = resolved
        }
        .task(id: app.pid) {
            processPaths = ProcessInfoLookup.paths(for: app.pid)
        }
    }

    @ViewBuilder
    private func drillHeaderCell(_ title: String, column: DrillInSortColumn, alignment: Alignment) -> some View {
        Button(action: { sortColumn = column }) {
            HStack(spacing: Spacing.xxs) {
                Text(title)
                if sortColumn == column {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7))
                }
            }
            .font(SpookFont.caption3)
            .foregroundColor(sortColumn == column ? .spookTextPrimary : .spookTextSecondary)
        }
        .buttonStyle(.plain)
    }

    private func stateColor(_ state: String) -> Color {
        switch state.uppercased() {
        case "ESTABLISHED":
            return .green
        case "CLOSE_WAIT", "TIME_WAIT", "FIN_WAIT1", "FIN_WAIT2":
            return .orange
        case "SYN_SENT", "SYN_RECV":
            return .blue
        default:
            return .secondary
        }
    }
}

