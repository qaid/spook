import Foundation

enum SpeedFormatter {
    static func format(_ bytesPerSecond: Int64) -> String {
        let units = ["B/s", "KB/s", "MB/s", "GB/s"]
        var value = Double(bytesPerSecond)
        var unitIndex = 0

        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return String(format: "%.0f %@", value, units[unitIndex])
        } else {
            return String(format: "%.1f %@", value, units[unitIndex])
        }
    }

    static func formatCompact(_ bytesPerSecond: Int64) -> String {
        let units = ["B", "K", "M", "G"]
        var value = Double(bytesPerSecond)
        var unitIndex = 0

        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return String(format: "%.0f%@", value, units[unitIndex])
        } else if value >= 100 {
            return String(format: "%.0f%@", value, units[unitIndex])
        } else if value >= 10 {
            return String(format: "%.1f%@", value, units[unitIndex])
        } else {
            return String(format: "%.2f%@", value, units[unitIndex])
        }
    }
}

enum ByteFormatter {
    static func format(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0

        while value >= 1024 && unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }

        if unitIndex == 0 {
            return String(format: "%.0f %@", value, units[unitIndex])
        } else {
            return String(format: "%.1f %@", value, units[unitIndex])
        }
    }
}
