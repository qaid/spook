import SwiftUI

struct TrafficGraphView: View {
    @State private var samples: [TrafficSample] = []
    @State private var maxValue: Int64 = 1
    @State private var selectedRange: GraphRange = .hour

    enum GraphRange: String, CaseIterable {
        case hour = "1 Hour"
        case day = "24 Hours"
        case week = "7 Days"

        var hours: Int {
            switch self {
            case .hour: return 1
            case .day: return 24
            case .week: return 168
            }
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Range selector
            HStack {
                Text("Traffic History")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                Picker("", selection: $selectedRange) {
                    ForEach(GraphRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .onChange(of: selectedRange) { _, _ in
                    Task { await loadSamples() }
                }
            }

            // Graph
            if samples.isEmpty {
                Text("No data yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(height: 80)
            } else {
                GraphCanvas(samples: samples, maxValue: maxValue)
                    .frame(height: 80)

                // Legend
                HStack(spacing: 16) {
                    LegendItem(color: .blue, label: "Download")
                    LegendItem(color: .green, label: "Upload")

                    Spacer()

                    if let lastSample = samples.last {
                        Text("Total: ↓\(ByteFormatter.format(lastSample.cumulativeIn)) ↑\(ByteFormatter.format(lastSample.cumulativeOut))")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .task {
            await loadSamples()
        }
    }

    private func loadSamples() async {
        let hourlyData = await HistoryStore.shared.getHourlySamples(hours: selectedRange.hours)

        var cumulativeIn: Int64 = 0
        var cumulativeOut: Int64 = 0

        let newSamples = hourlyData.map { data -> TrafficSample in
            cumulativeIn += data.bytesIn
            cumulativeOut += data.bytesOut
            return TrafficSample(
                timestamp: data.timestamp,
                bytesIn: data.bytesIn,
                bytesOut: data.bytesOut,
                cumulativeIn: cumulativeIn,
                cumulativeOut: cumulativeOut
            )
        }

        let maxIn = newSamples.map(\.bytesIn).max() ?? 1
        let maxOut = newSamples.map(\.bytesOut).max() ?? 1

        await MainActor.run {
            samples = newSamples
            maxValue = max(maxIn, maxOut, 1)
        }
    }
}

struct TrafficSample: Identifiable {
    let id = UUID()
    let timestamp: Date
    let bytesIn: Int64
    let bytesOut: Int64
    let cumulativeIn: Int64
    let cumulativeOut: Int64
}

struct GraphCanvas: View {
    let samples: [TrafficSample]
    let maxValue: Int64

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let stepX = samples.count > 1 ? width / CGFloat(samples.count - 1) : width

            ZStack {
                // Background grid
                Path { path in
                    for i in 0..<4 {
                        let y = height * CGFloat(i) / 3
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                }
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)

                // Download line (blue)
                Path { path in
                    guard !samples.isEmpty else { return }

                    for (index, sample) in samples.enumerated() {
                        let x = CGFloat(index) * stepX
                        let y = height - (height * CGFloat(sample.bytesIn) / CGFloat(maxValue))

                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.blue, lineWidth: 1.5)

                // Download fill
                Path { path in
                    guard !samples.isEmpty else { return }

                    path.move(to: CGPoint(x: 0, y: height))

                    for (index, sample) in samples.enumerated() {
                        let x = CGFloat(index) * stepX
                        let y = height - (height * CGFloat(sample.bytesIn) / CGFloat(maxValue))
                        path.addLine(to: CGPoint(x: x, y: y))
                    }

                    path.addLine(to: CGPoint(x: width, y: height))
                    path.closeSubpath()
                }
                .fill(Color.blue.opacity(0.15))

                // Upload line (green)
                Path { path in
                    guard !samples.isEmpty else { return }

                    for (index, sample) in samples.enumerated() {
                        let x = CGFloat(index) * stepX
                        let y = height - (height * CGFloat(sample.bytesOut) / CGFloat(maxValue))

                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.green, lineWidth: 1.5)

                // Upload fill
                Path { path in
                    guard !samples.isEmpty else { return }

                    path.move(to: CGPoint(x: 0, y: height))

                    for (index, sample) in samples.enumerated() {
                        let x = CGFloat(index) * stepX
                        let y = height - (height * CGFloat(sample.bytesOut) / CGFloat(maxValue))
                        path.addLine(to: CGPoint(x: x, y: y))
                    }

                    path.addLine(to: CGPoint(x: width, y: height))
                    path.closeSubpath()
                }
                .fill(Color.green.opacity(0.15))
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 12, height: 3)
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
    }
}
