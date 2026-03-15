import SwiftUI

struct AppListView: View {
    let apps: [AppTraffic]
    var directionFilter: TrafficDirection = .all
    var maxTraffic: Int64 = 1
    @State private var expandedApps: Set<String> = []

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(apps) { app in
                    AppRowView(
                        app: app,
                        directionFilter: directionFilter,
                        maxTraffic: maxTraffic,
                        isExpanded: expandedApps.contains(app.id),
                        onToggle: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                if expandedApps.contains(app.id) {
                                    expandedApps.remove(app.id)
                                } else {
                                    expandedApps.insert(app.id)
                                }
                            }
                        }
                    )
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
}

struct AppRowView: View {
    let app: AppTraffic
    var directionFilter: TrafficDirection = .all
    var maxTraffic: Int64 = 1
    let isExpanded: Bool
    let onToggle: () -> Void
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
                        RoundedRectangle(cornerRadius: 3)
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
                                        .font(.system(size: 10, weight: .medium))
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
                                        .font(.system(size: 9))
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
                                        .font(.system(size: 9))
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
                                .font(.system(size: 10, weight: .semibold))
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

            // Expanded connection details
            if isExpanded && !app.connections.isEmpty {
                ConnectionsView(connections: app.connections)
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

struct ConnectionsView: View {
    let connections: [Connection]

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(connections) { connection in
                ConnectionRowView(connection: connection)
            }
        }
        .padding(.vertical, Spacing.xs)
        .background(Color.black.opacity(0.05))
    }
}

struct ConnectionRowView: View {
    let connection: Connection
    @State private var resolvedHostname: String?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Protocol icon
            Image(systemName: connection.protocolType == "tcp" ? "link" : "antenna.radiowaves.left.and.right")
                .font(.system(size: 10))
                .foregroundColor(.spookTextSecondary)
                .frame(width: 14)

            // Address and port
            VStack(alignment: .leading, spacing: 1) {
                if let hostname = resolvedHostname, hostname != connection.remoteAddress {
                    Text(hostname)
                        .font(SpookFont.caption)
                        .lineLimit(1)

                    Text("\(connection.remoteAddress):\(connection.remotePort)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.spookTextSecondary)
                        .lineLimit(1)
                } else {
                    Text("\(connection.remoteAddress):\(connection.remotePort)")
                        .font(SpookFont.monoCaption)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Connection state
            if !connection.state.isEmpty {
                Text(connection.state.lowercased())
                    .font(SpookFont.caption3)
                    .foregroundColor(stateColor(connection.state))
                    .padding(.horizontal, Spacing.sm)
                    .padding(.vertical, Spacing.xxs)
                    .background(
                        Capsule()
                            .fill(stateColor(connection.state).opacity(0.12))
                    )
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.leading, 44)
        .padding(.vertical, Spacing.xs)
        .background(Color.white.opacity(isHovered ? 0.03 : 0))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .task {
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
