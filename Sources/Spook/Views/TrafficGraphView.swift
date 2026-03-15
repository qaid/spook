import SwiftUI

struct TrafficGraphView: View {
    var monitor: NetworkMonitor?
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

        /// Dynamic time labels based on actual sample data
        func timeLabels(from samples: [TrafficSample]) -> [String] {
            guard let first = samples.first else {
                return defaultTimeLabels
            }

            let elapsed = Date().timeIntervalSince(first.timestamp)

            switch self {
            case .hour:
                if elapsed < 60 {
                    return ["\(Int(elapsed))s ago", "now"]
                } else if elapsed < 3600 {
                    let mins = Int(elapsed / 60)
                    let mid = mins / 2
                    return ["\(mins)m ago", "\(mid)m", "now"]
                } else {
                    return ["60m ago", "30m", "now"]
                }
            case .day:
                let hours = Int(elapsed / 3600)
                if hours < 1 {
                    let mins = Int(elapsed / 60)
                    return ["\(max(1, mins))m ago", "now"]
                } else {
                    let mid = hours / 2
                    return ["\(hours)h ago", "\(mid)h", "now"]
                }
            case .week:
                let days = Int(elapsed / 86400)
                if days < 1 {
                    let hours = Int(elapsed / 3600)
                    return ["\(max(1, hours))h ago", "now"]
                } else {
                    let mid = days / 2
                    return ["\(days)d ago", "\(mid)d", "now"]
                }
            }
        }

        private var defaultTimeLabels: [String] {
            switch self {
            case .hour: return ["60m ago", "30m", "now"]
            case .day: return ["24h ago", "12h", "now"]
            case .week: return ["7d ago", "3d", "now"]
            }
        }
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            // Range selector
            HStack {
                Text("Traffic History")
                    .font(SpookFont.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.spookTextSecondary)

                Spacer()

                Picker("", selection: $selectedRange) {
                    ForEach(GraphRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .controlSize(.small)
            }

            // Graph
            if samples.isEmpty {
                // Styled empty state
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(SpookFont.iconLg)
                        .foregroundColor(.spookTextTertiary)
                    Text("No traffic recorded")
                        .font(SpookFont.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.spookTextSecondary)
                    Text("Data will appear after network activity is detected")
                        .font(SpookFont.caption2)
                        .foregroundColor(.spookTextTertiary)
                }
                .frame(height: 100)
                .frame(maxWidth: .infinity)
                .opacity(0.7)
            } else {
                ZStack(alignment: .bottomLeading) {
                    GraphCanvas(samples: samples, maxValue: maxValue)
                        .frame(height: 100)

                    // Y-axis labels
                    VStack {
                        Text(ByteFormatter.format(maxValue))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer()
                        Text(ByteFormatter.format(maxValue / 2))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Spacer()
                        Text("0")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(SpookFont.caption3)
                    .foregroundColor(.spookTextTertiary)
                    .frame(height: 100)
                    .padding(.leading, Spacing.xs)

                    // Time labels
                    HStack {
                        let labels = selectedRange.timeLabels(from: samples)
                        ForEach(labels, id: \.self) { label in
                            if label != labels.first {
                                Spacer()
                            }
                            Text(label)
                        }
                    }
                    .font(SpookFont.caption3)
                    .foregroundColor(.spookTextTertiary)
                    .offset(y: Spacing.xl)
                }
                .padding(.bottom, Spacing.xl)

                // Legend
                HStack(spacing: Spacing.xl) {
                    LegendItem(color: .spookDownload, label: "Download")
                    LegendItem(color: .spookUpload, label: "Upload")

                    Spacer()

                    if let lastSample = samples.last {
                        Text("Total: \u{2193}\(ByteFormatter.format(lastSample.cumulativeIn)) \u{2191}\(ByteFormatter.format(lastSample.cumulativeOut))")
                            .font(SpookFont.caption2)
                            .foregroundColor(.spookTextSecondary)
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .task(id: selectedRange) {
            await loadSamples(animated: false)
            // Auto-refresh every 2 seconds for the 1-hour view
            if selectedRange == .hour {
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(2))
                    } catch {
                        break
                    }
                    await loadSamples()
                }
            }
        }
    }

    private func loadSamples(animated: Bool = true) async {
        let newSamples: [TrafficSample]

        if selectedRange == .hour, let monitor = monitor {
            // Use in-memory per-second data, downsampled to ~60 points
            let recentData = await MainActor.run { monitor.recentSamples }
            let bucketCount = 60
            newSamples = downsampleToTrafficSamples(recentData, buckets: bucketCount)
        } else {
            // Use DB hourly samples for 24h and 7d
            let hourlyData = await HistoryStore.shared.getHourlySamples(hours: selectedRange.hours)

            var cumulativeIn: Int64 = 0
            var cumulativeOut: Int64 = 0

            newSamples = hourlyData.map { data -> TrafficSample in
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
        }

        let maxIn = newSamples.map(\.bytesIn).max() ?? 1
        let maxOut = newSamples.map(\.bytesOut).max() ?? 1

        await MainActor.run {
            if animated {
                withAnimation(.easeInOut(duration: 0.3)) {
                    samples = newSamples
                    maxValue = max(maxIn, maxOut, 1)
                }
            } else {
                samples = newSamples
                maxValue = max(maxIn, maxOut, 1)
            }
        }
    }

    private func downsampleToTrafficSamples(_ rawSamples: [SpeedSample], buckets: Int) -> [TrafficSample] {
        guard !rawSamples.isEmpty else { return [] }

        let bucketSize = max(1, rawSamples.count / buckets)
        var result: [TrafficSample] = []
        var cumulativeIn: Int64 = 0
        var cumulativeOut: Int64 = 0

        var i = 0
        while i < rawSamples.count {
            let end = min(i + bucketSize, rawSamples.count)
            let slice = rawSamples[i..<end]

            // Average the bytes in this bucket
            let avgIn = slice.map(\.bytesIn).reduce(0, +) / Int64(slice.count)
            let avgOut = slice.map(\.bytesOut).reduce(0, +) / Int64(slice.count)
            cumulativeIn += avgIn
            cumulativeOut += avgOut

            result.append(TrafficSample(
                timestamp: slice.last!.timestamp,
                bytesIn: avgIn,
                bytesOut: avgOut,
                cumulativeIn: cumulativeIn,
                cumulativeOut: cumulativeOut
            ))

            i = end
        }

        return result
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

// MARK: - Graph Canvas

struct GraphCanvas: View {
    let samples: [TrafficSample]
    let maxValue: Int64

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let stepX = samples.count > 1 ? width / CGFloat(samples.count - 1) : width

            ZStack {
                // Background grid (dashed)
                Path { path in
                    for i in 0..<4 {
                        let y = height * CGFloat(i) / 3
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                    }
                }
                .stroke(Color.spookTextSecondary.opacity(0.15), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))

                // Download fill
                smoothFilledPath(samples: samples, keyPath: \.bytesIn, stepX: stepX, height: height, width: width)
                    .fill(Color.spookDownload.opacity(0.12))

                // Download line
                smoothLinePath(samples: samples, keyPath: \.bytesIn, stepX: stepX, height: height)
                    .stroke(Color.spookDownload, lineWidth: 1.5)

                // Upload fill
                smoothFilledPath(samples: samples, keyPath: \.bytesOut, stepX: stepX, height: height, width: width)
                    .fill(Color.spookUpload.opacity(0.12))

                // Upload line
                smoothLinePath(samples: samples, keyPath: \.bytesOut, stepX: stepX, height: height)
                    .stroke(Color.spookUpload, lineWidth: 1.5)
            }
        }
        .background(Color.spookSurfaceElevated.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.md))
    }

    // Catmull-Rom spline interpolation for smooth curves
    private func smoothLinePath(samples: [TrafficSample], keyPath: KeyPath<TrafficSample, Int64>, stepX: CGFloat, height: CGFloat) -> Path {
        let points = samples.enumerated().map { (index, sample) -> CGPoint in
            let x = CGFloat(index) * stepX
            let y = height - (height * CGFloat(sample[keyPath: keyPath]) / CGFloat(maxValue))
            return CGPoint(x: x, y: y)
        }
        return catmullRomPath(points: points)
    }

    private func smoothFilledPath(samples: [TrafficSample], keyPath: KeyPath<TrafficSample, Int64>, stepX: CGFloat, height: CGFloat, width: CGFloat) -> Path {
        let points = samples.enumerated().map { (index, sample) -> CGPoint in
            let x = CGFloat(index) * stepX
            let y = height - (height * CGFloat(sample[keyPath: keyPath]) / CGFloat(maxValue))
            return CGPoint(x: x, y: y)
        }

        var path = Path()
        guard !points.isEmpty else { return path }

        path.move(to: CGPoint(x: 0, y: height))

        if points.count < 4 {
            // Linear fallback for few points
            for point in points {
                path.addLine(to: point)
            }
        } else {
            // Catmull-Rom curve
            path.addLine(to: points[0])
            for i in 0..<(points.count - 1) {
                let (cp1, cp2) = catmullRomControlPoints(
                    p0: points[max(0, i - 1)],
                    p1: points[i],
                    p2: points[min(points.count - 1, i + 1)],
                    p3: points[min(points.count - 1, i + 2)]
                )
                path.addCurve(to: points[i + 1], control1: cp1, control2: cp2)
            }
        }

        path.addLine(to: CGPoint(x: points.last?.x ?? width, y: height))
        path.closeSubpath()
        return path
    }

    private func catmullRomPath(points: [CGPoint]) -> Path {
        var path = Path()
        guard !points.isEmpty else { return path }

        if points.count < 4 {
            // Linear fallback
            path.move(to: points[0])
            for i in 1..<points.count {
                path.addLine(to: points[i])
            }
            return path
        }

        path.move(to: points[0])
        for i in 0..<(points.count - 1) {
            let (cp1, cp2) = catmullRomControlPoints(
                p0: points[max(0, i - 1)],
                p1: points[i],
                p2: points[min(points.count - 1, i + 1)],
                p3: points[min(points.count - 1, i + 2)]
            )
            path.addCurve(to: points[i + 1], control1: cp1, control2: cp2)
        }

        return path
    }

    private func catmullRomControlPoints(p0: CGPoint, p1: CGPoint, p2: CGPoint, p3: CGPoint) -> (CGPoint, CGPoint) {
        let alpha: CGFloat = 1.0 / 6.0
        let cp1 = CGPoint(
            x: p1.x + alpha * (p2.x - p0.x),
            y: p1.y + alpha * (p2.y - p0.y)
        )
        let cp2 = CGPoint(
            x: p2.x - alpha * (p3.x - p1.x),
            y: p2.y - alpha * (p3.y - p1.y)
        )
        return (cp1, cp2)
    }
}

// MARK: - Legend

struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(SpookFont.caption2)
                .foregroundColor(.spookTextSecondary)
        }
    }
}
