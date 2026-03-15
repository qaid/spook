import SwiftUI

enum TrafficDirection: String, CaseIterable {
    case all = "All"
    case download = "Download"
    case upload = "Upload"
}

struct DetailView: View {
    @State private var monitor: NetworkMonitor
    @State private var isSortPaused: Bool = false
    @State private var frozenApps: [AppTraffic] = []
    @State private var searchText: String = ""
    @State private var directionFilter: TrafficDirection = .all

    init(monitor: NetworkMonitor) {
        _monitor = State(initialValue: monitor)
    }

    var baseApps: [AppTraffic] {
        if isSortPaused {
            return frozenApps.compactMap { frozenApp in
                if let updated = monitor.appTraffic.first(where: { $0.id == frozenApp.id }) {
                    return updated
                }
                var stale = frozenApp
                stale.speedIn = 0
                stale.speedOut = 0
                return stale
            }
        } else {
            return monitor.appTraffic
        }
    }

    var filteredApps: [AppTraffic] {
        var apps = baseApps

        switch directionFilter {
        case .download:
            apps = apps.filter { $0.speedIn > 0 || $0.bytesIn > 0 }
            if !isSortPaused {
                apps.sort { $0.speedIn > $1.speedIn }
            }
        case .upload:
            apps = apps.filter { $0.speedOut > 0 || $0.bytesOut > 0 }
            if !isSortPaused {
                apps.sort { $0.speedOut > $1.speedOut }
            }
        case .all:
            break
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            apps = apps.filter { app in
                app.displayName.lowercased().contains(query) ||
                app.processName.lowercased().contains(query)
            }
        }

        return apps
    }

    var maxTraffic: Int64 {
        filteredApps.map { $0.totalSpeed }.max() ?? 1
    }

    var body: some View {
        VStack(spacing: 0) {
            // Summary Header
            SummaryHeaderView(
                downloadSpeed: monitor.downloadSpeed,
                uploadSpeed: monitor.uploadSpeed,
                totalIn: monitor.totalBytesIn,
                totalOut: monitor.totalBytesOut
            )

            // Traffic Graph
            TrafficGraphView(monitor: monitor)
                .padding(.top, Spacing.xs)

            // Search Field
            SearchFieldView(searchText: $searchText)
                .padding(.top, Spacing.xs)

            // App List Header
            AppListHeaderView(
                appCount: filteredApps.count,
                totalCount: baseApps.count,
                isFiltered: !searchText.isEmpty || directionFilter != .all,
                isSortPaused: $isSortPaused,
                directionFilter: $directionFilter,
                onPauseToggle: {
                    if !isSortPaused {
                        frozenApps = monitor.appTraffic
                    }
                    isSortPaused.toggle()
                }
            )

            // Subtle separator before list
            Color.spookBorder
                .frame(height: 0.5)
                .padding(.horizontal, Spacing.lg)

            // App List
            if filteredApps.isEmpty {
                if searchText.isEmpty && directionFilter == .all {
                    EmptyStateView()
                        .transition(.opacity)
                } else {
                    NoResultsView(searchText: searchText, directionFilter: directionFilter)
                        .transition(.opacity)
                }
            } else {
                AppListView(apps: filteredApps, directionFilter: directionFilter, maxTraffic: maxTraffic)
            }
        }
        .frame(width: 400, height: 600)
    }
}

// MARK: - Search Field

struct SearchFieldView: View {
    @Binding var searchText: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(.spookTextSecondary)

            TextField("Filter apps...", text: $searchText)
                .textFieldStyle(.plain)
                .font(SpookFont.caption)
                .focused($isFocused)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.spookTextSecondary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CornerRadius.md)
                .fill(Color.spookTextBackground.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: CornerRadius.md)
                        .stroke(isFocused ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
                )
        )
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.sm)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .animation(.easeInOut(duration: 0.15), value: searchText.isEmpty)
    }
}

// MARK: - App List Header

struct AppListHeaderView: View {
    let appCount: Int
    let totalCount: Int
    let isFiltered: Bool
    @Binding var isSortPaused: Bool
    @Binding var directionFilter: TrafficDirection
    let onPauseToggle: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            // Direction filter toggles
            DirectionToggle(
                direction: .download,
                isSelected: directionFilter == .download,
                onTap: {
                    directionFilter = directionFilter == .download ? .all : .download
                }
            )

            DirectionToggle(
                direction: .upload,
                isSelected: directionFilter == .upload,
                onTap: {
                    directionFilter = directionFilter == .upload ? .all : .upload
                }
            )

            Spacer()

            // App count
            if isFiltered {
                Text("\(appCount) of \(totalCount)")
                    .font(SpookFont.caption2)
                    .foregroundColor(.orange)
            } else {
                Text("\(appCount) apps")
                    .font(SpookFont.caption2)
                    .foregroundColor(.spookTextTertiary)
            }

            // Freeze button
            Button(action: onPauseToggle) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: isSortPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 10))
                    Text(isSortPaused ? "Resume" : "Freeze")
                        .font(SpookFont.caption)
                }
                .foregroundColor(isSortPaused ? .orange : .spookTextSecondary)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.xs)
                .background(
                    Capsule()
                        .fill(isSortPaused ? Color.orange.opacity(0.15) : Color.spookTextSecondary.opacity(0.1))
                )
            }
            .buttonStyle(.plain)
            .help(isSortPaused ? "Resume live sorting" : "Freeze list order")
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
    }
}

// MARK: - Direction Toggle

struct DirectionToggle: View {
    let direction: TrafficDirection
    let isSelected: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    var icon: String {
        direction == .download ? "arrow.down" : "arrow.up"
    }

    var color: Color {
        direction == .download ? .spookDownload : .spookUpload
    }

    var label: String {
        direction == .download ? "Download" : "Upload"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(SpookFont.caption)
            }
            .foregroundColor(isSelected ? .white : color)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(
                Capsule()
                    .fill(isSelected ? color : color.opacity(isHovered ? 0.2 : 0.12))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .help(isSelected ? "Show all traffic" : "Show only \(label.lowercased()) traffic")
    }
}

// MARK: - Summary Header

struct SummaryHeaderView: View {
    let downloadSpeed: Int64
    let uploadSpeed: Int64
    let totalIn: Int64
    let totalOut: Int64

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Speed readouts
            HStack(spacing: 0) {
                // Download column
                VStack(alignment: .center, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.spookDownload)
                            .font(.system(size: 12))
                        Text("Download")
                            .font(SpookFont.caption)
                            .foregroundColor(.spookTextSecondary)
                    }
                    Text(SpeedFormatter.format(downloadSpeed))
                        .font(SpookFont.title)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity)

                // Vertical divider
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.spookBorder)
                    .frame(width: 1, height: 28)

                // Upload column
                VStack(alignment: .center, spacing: Spacing.xs) {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.spookUpload)
                            .font(.system(size: 12))
                        Text("Upload")
                            .font(SpookFont.caption)
                            .foregroundColor(.spookTextSecondary)
                    }
                    Text(SpeedFormatter.format(uploadSpeed))
                        .font(SpookFont.title)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity)
            }

            // Session totals
            HStack(spacing: Spacing.lg) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundColor(.spookTextTertiary)

                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 9))
                        .foregroundColor(.spookDownload)
                    Text(ByteFormatter.format(totalIn))
                        .font(SpookFont.caption2)
                        .foregroundColor(.spookTextSecondary)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xxs)
                .background(
                    Capsule()
                        .fill(Color.spookDownload.opacity(0.08))
                )

                HStack(spacing: Spacing.xs) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 9))
                        .foregroundColor(.spookUpload)
                    Text(ByteFormatter.format(totalOut))
                        .font(SpookFont.caption2)
                        .foregroundColor(.spookTextSecondary)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xxs)
                .background(
                    Capsule()
                        .fill(Color.spookUpload.opacity(0.08))
                )
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.lg)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Empty States

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: "network.slash")
                .font(.system(size: 32))
                .foregroundColor(.spookTextTertiary)
            Text("No network activity")
                .font(SpookFont.headline)
                .foregroundColor(.spookTextSecondary)
            Text("Traffic will appear here when apps use the network")
                .font(SpookFont.caption)
                .foregroundColor(.spookTextTertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NoResultsView: View {
    let searchText: String
    var directionFilter: TrafficDirection = .all

    var body: some View {
        VStack(spacing: Spacing.md) {
            Spacer()
            Image(systemName: directionFilter != .all ? (directionFilter == .download ? "arrow.down.circle" : "arrow.up.circle") : "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.spookTextTertiary)
            Text("No matches")
                .font(SpookFont.headline)
                .foregroundColor(.spookTextSecondary)

            if !searchText.isEmpty {
                Text("No apps matching \"\(searchText)\"")
                    .font(SpookFont.caption)
                    .foregroundColor(.spookTextTertiary)
                    .multilineTextAlignment(.center)
            } else if directionFilter == .download {
                Text("No apps with download activity")
                    .font(SpookFont.caption)
                    .foregroundColor(.spookTextTertiary)
                    .multilineTextAlignment(.center)
            } else if directionFilter == .upload {
                Text("No apps with upload activity")
                    .font(SpookFont.caption)
                    .foregroundColor(.spookTextTertiary)
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
