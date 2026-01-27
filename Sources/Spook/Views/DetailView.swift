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
            // When paused, keep the frozen order but update the data
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

        // Apply direction filter (only sort if not paused)
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

        // Apply search filter
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

            Divider()

            // Traffic Graph
            TrafficGraphView()

            Divider()

            // Search Field
            SearchFieldView(searchText: $searchText)

            Divider()

            // App List Header with sort toggle and direction filter
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

            Divider()

            // App List
            if filteredApps.isEmpty {
                if searchText.isEmpty && directionFilter == .all {
                    EmptyStateView()
                } else {
                    NoResultsView(searchText: searchText, directionFilter: directionFilter)
                }
            } else {
                AppListView(apps: filteredApps, directionFilter: directionFilter, maxTraffic: maxTraffic)
            }
        }
        .frame(width: 360, height: 580)
    }
}

struct SearchFieldView: View {
    @Binding var searchText: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            TextField("Filter apps...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isFocused)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct AppListHeaderView: View {
    let appCount: Int
    let totalCount: Int
    let isFiltered: Bool
    @Binding var isSortPaused: Bool
    @Binding var directionFilter: TrafficDirection
    let onPauseToggle: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            // Direction filter toggles
            HStack(spacing: 8) {
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

                Button(action: onPauseToggle) {
                    HStack(spacing: 4) {
                        Image(systemName: isSortPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 9))
                        Text(isSortPaused ? "Resume" : "Freeze")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(isSortPaused ? .orange : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isSortPaused ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .help(isSortPaused ? "Resume live sorting" : "Freeze list order")
            }

            // App count
            HStack {
                Text("Active Applications")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                if isFiltered {
                    Text("(\(appCount) of \(totalCount))")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                } else {
                    Text("(\(appCount))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.7))
                }

                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct DirectionToggle: View {
    let direction: TrafficDirection
    let isSelected: Bool
    let onTap: () -> Void

    var icon: String {
        direction == .download ? "arrow.down" : "arrow.up"
    }

    var color: Color {
        direction == .download ? .blue : .green
    }

    var label: String {
        direction == .download ? "Download" : "Upload"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(.system(size: 10))
            }
            .foregroundColor(isSelected ? .white : color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? color : color.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
        .help(isSelected ? "Show all traffic" : "Show only \(label.lowercased()) traffic")
    }
}

struct SummaryHeaderView: View {
    let downloadSpeed: Int64
    let uploadSpeed: Int64
    let totalIn: Int64
    let totalOut: Int64

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 32) {
                // Download
                VStack(alignment: .center, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.blue)
                        Text("Download")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(SpeedFormatter.format(downloadSpeed))
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                }

                // Upload
                VStack(alignment: .center, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundColor(.green)
                        Text("Upload")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(SpeedFormatter.format(uploadSpeed))
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                }
            }

            // Session totals
            HStack(spacing: 16) {
                Text("Session:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Text(ByteFormatter.format(totalIn))
                        .font(.caption)
                }

                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.caption2)
                        .foregroundColor(.green)
                    Text(ByteFormatter.format(totalOut))
                        .font(.caption)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "network.slash")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No network activity")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Traffic will appear here when apps use the network")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.7))
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
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: directionFilter != .all ? (directionFilter == .download ? "arrow.down.circle" : "arrow.up.circle") : "magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No matches")
                .font(.headline)
                .foregroundColor(.secondary)

            if !searchText.isEmpty {
                Text("No apps matching \"\(searchText)\"")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)
            } else if directionFilter == .download {
                Text("No apps with download activity")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)
            } else if directionFilter == .upload {
                Text("No apps with upload activity")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
