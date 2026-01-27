import Foundation
import AppKit

struct AppTraffic: Identifiable {
    let id: String  // bundleID or process name
    let processName: String
    let pid: pid_t
    var bytesIn: Int64
    var bytesOut: Int64
    var previousBytesIn: Int64
    var previousBytesOut: Int64
    var speedIn: Int64  // bytes per second
    var speedOut: Int64
    var connections: [Connection]

    var displayName: String {
        // Clean up process names like "com.apple.WebKi" -> "WebKit"
        if processName.hasPrefix("com.apple.") {
            return String(processName.dropFirst(10))
        }
        return processName
    }

    var icon: NSImage {
        // Try to get app icon from bundle identifier
        if let bundleID = bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }

        // Try to find by process name
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "").first(where: {
            $0.localizedName == processName
        }) {
            return app.icon ?? defaultIcon
        }

        return defaultIcon
    }

    var bundleIdentifier: String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    private var defaultIcon: NSImage {
        NSImage(systemSymbolName: "app.fill", accessibilityDescription: "Application")
            ?? NSImage()
    }

    var totalBytes: Int64 {
        bytesIn + bytesOut
    }

    var totalSpeed: Int64 {
        speedIn + speedOut
    }
}

struct Connection: Identifiable {
    let id = UUID()
    let remoteAddress: String
    let remotePort: UInt16
    let localPort: UInt16
    let protocolType: String  // "tcp" or "udp"
    let state: String
    var bytesIn: Int64
    var bytesOut: Int64
    var resolvedHostname: String?

    var displayAddress: String {
        if let hostname = resolvedHostname, !hostname.isEmpty, hostname != remoteAddress {
            return "\(hostname) (\(remoteAddress))"
        }
        return remoteAddress
    }
}
