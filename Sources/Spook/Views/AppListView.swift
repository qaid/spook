import SwiftUI

struct AppListView: View {
    let apps: [AppTraffic]
    var directionFilter: TrafficDirection = .all
    var maxTraffic: Int64 = 1
    @State private var expandedApps: Set<String> = []

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(apps) { app in
                    AppRowView(
                        app: app,
                        directionFilter: directionFilter,
                        maxTraffic: maxTraffic,
                        isExpanded: expandedApps.contains(app.id),
                        onToggle: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if expandedApps.contains(app.id) {
                                    expandedApps.remove(app.id)
                                } else {
                                    expandedApps.insert(app.id)
                                }
                            }
                        }
                    )
                    Divider()
                        .padding(.leading, 44)
                }
            }
        }
    }
}

struct AppRowView: View {
    let app: AppTraffic
    var directionFilter: TrafficDirection = .all
    var maxTraffic: Int64 = 1
    let isExpanded: Bool
    let onToggle: () -> Void

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
                        RoundedRectangle(cornerRadius: 2)
                            .fill(trafficBarColor.opacity(0.1))
                            .frame(width: geometry.size.width * trafficRatio)
                    }

                    HStack(spacing: 12) {
                        // App icon
                        Image(nsImage: app.icon)
                            .resizable()
                            .frame(width: 24, height: 24)

                        // App name and totals
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(app.displayName)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)

                                // Connection badge
                                if !app.connections.isEmpty {
                                    Text("\(app.connections.count)")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Capsule().fill(Color.secondary.opacity(0.6)))
                                }
                            }

                            Text(ByteFormatter.format(app.totalBytes) + " total")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Current speeds (show based on filter)
                        VStack(alignment: .trailing, spacing: 2) {
                            if directionFilter != .upload {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 9))
                                        .foregroundColor(.blue)
                                    Text(SpeedFormatter.formatCompact(app.speedIn))
                                        .font(.system(size: 11, design: .monospaced))
                                }
                                .opacity(directionFilter == .download ? 1 : (app.speedIn > 0 ? 1 : 0.4))
                            }

                            if directionFilter != .download {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 9))
                                        .foregroundColor(.green)
                                    Text(SpeedFormatter.formatCompact(app.speedOut))
                                        .font(.system(size: 11, design: .monospaced))
                                }
                                .opacity(directionFilter == .upload ? 1 : (app.speedOut > 0 ? 1 : 0.4))
                            }
                        }
                        .frame(width: 70, alignment: .trailing)

                        // Expand indicator (only show if there are connections)
                        if !app.connections.isEmpty {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        } else {
                            Color.clear
                                .frame(width: 10)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(app.connections.isEmpty)

            // Expanded connection details
            if isExpanded && !app.connections.isEmpty {
                ConnectionsView(connections: app.connections)
            }
        }
    }

    var trafficBarColor: Color {
        switch directionFilter {
        case .download: return .blue
        case .upload: return .green
        case .all: return app.speedIn > app.speedOut ? .blue : .green
        }
    }
}

struct ConnectionsView: View {
    let connections: [Connection]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(connections) { connection in
                ConnectionRowView(connection: connection)
            }
        }
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
}

struct ConnectionRowView: View {
    let connection: Connection
    @State private var resolvedHostname: String?

    var body: some View {
        HStack(spacing: 8) {
            // Protocol icon
            Image(systemName: connection.protocolType == "tcp" ? "link" : "antenna.radiowaves.left.and.right")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 14)

            // Address and port
            VStack(alignment: .leading, spacing: 1) {
                if let hostname = resolvedHostname, hostname != connection.remoteAddress {
                    Text(hostname)
                        .font(.system(size: 11))
                        .lineLimit(1)

                    Text("\(connection.remoteAddress):\(connection.remotePort)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Text("\(connection.remoteAddress):\(connection.remotePort)")
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Connection state
            if !connection.state.isEmpty {
                Text(connection.state.lowercased())
                    .font(.system(size: 9))
                    .foregroundColor(stateColor(connection.state))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(stateColor(connection.state).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .padding(.horizontal, 12)
        .padding(.leading, 32)
        .padding(.vertical, 4)
        .task {
            // Resolve DNS asynchronously
            resolvedHostname = await DNSResolver.shared.resolve(connection.remoteAddress)
        }
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
