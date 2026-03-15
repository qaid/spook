import Foundation
import AppKit

// MARK: - Icon Cache

/// Caches resolved icons by process name so icon resolution only runs once per unique process.
class IconCache {
    static let shared = IconCache()
    private var cache: [String: NSImage] = [:]

    func icon(for processName: String) -> NSImage? {
        cache[processName]
    }

    func set(_ image: NSImage, for processName: String) {
        cache[processName] = image
    }
}

// MARK: - Icon Resolver

/// Resolves app icons through multiple fallback tiers.
enum IconResolver {

    /// Resolve the best icon for a process, using cache when available.
    static func resolve(processName: String, pid: pid_t) -> NSImage {
        // Check cache first
        if let cached = IconCache.shared.icon(for: processName) {
            return cached
        }

        let icon = resolveUncached(processName: processName, pid: pid)
        IconCache.shared.set(icon, for: processName)
        return icon
    }

    private static func resolveUncached(processName: String, pid: pid_t) -> NSImage {
        // Tier 1: Direct PID lookup (works for GUI apps)
        if let app = NSRunningApplication(processIdentifier: pid) {
            if let bundleID = app.bundleIdentifier,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return NSWorkspace.shared.icon(forFile: url.path)
            }
            if let appIcon = app.icon {
                return appIcon
            }
            // Tier 1b: Walk up from executableURL (doesn't need proc_pidpath entitlements)
            if let execURL = app.executableURL {
                if let appIcon = findAppBundleIcon(from: execURL) {
                    return appIcon
                }
            }
        }

        // Tier 2: Walk up from proc_pidpath (may fail without entitlements)
        if let execPath = executablePath(for: pid) {
            if let appIcon = findAppBundleIcon(from: URL(fileURLWithPath: execPath)) {
                return appIcon
            }
        }

        // Tier 3: Match by process name against all running apps
        let cleanedName = cleanProcessName(processName)
        let allApps = NSWorkspace.shared.runningApplications
        if let match = allApps.first(where: { app in
            guard let name = app.localizedName else { return false }
            return name == processName ||
                   name == cleanedName ||
                   name.localizedCaseInsensitiveCompare(cleanedName) == .orderedSame ||
                   (app.bundleIdentifier?.localizedCaseInsensitiveContains(cleanedName) ?? false)
        }) {
            if let bundleURL = match.bundleURL {
                return NSWorkspace.shared.icon(forFile: bundleURL.path)
            }
            if let appIcon = match.icon {
                return appIcon
            }
        }

        // Tier 4: Search Applications folders with cleaned name variations
        if let appIcon = searchApplicationsFolders(for: cleanedName) {
            return appIcon
        }

        // Tier 5: For com.apple.* processes, try extracting the app name
        if processName.hasPrefix("com.apple.") {
            let parts = processName.dropFirst(10).components(separatedBy: ".")
            // Try "Safari" from "com.apple.Safari.SafeBrowsing"
            if let firstPart = parts.first, !firstPart.isEmpty {
                if let appIcon = searchApplicationsFolders(for: firstPart) {
                    return appIcon
                }
            }
        }

        // Tier 6: Fuzzy match — find any running app whose bundle path contains the cleaned name
        if let match = allApps.first(where: { app in
            guard let bundlePath = app.bundleURL?.lastPathComponent else { return false }
            let appName = bundlePath.replacingOccurrences(of: ".app", with: "")
            return appName.localizedCaseInsensitiveContains(cleanedName) ||
                   cleanedName.localizedCaseInsensitiveContains(appName)
        }) {
            if let bundleURL = match.bundleURL {
                return NSWorkspace.shared.icon(forFile: bundleURL.path)
            }
        }

        return defaultIcon
    }

    /// Walk up from an executable URL to find the enclosing .app bundle
    private static func findAppBundleIcon(from url: URL) -> NSImage? {
        var current = url
        while current.path != "/" {
            if current.pathExtension == "app" {
                return NSWorkspace.shared.icon(forFile: current.path)
            }
            current = current.deletingLastPathComponent()
        }
        return nil
    }

    /// Strip common suffixes from helper/agent/daemon process names
    static func cleanProcessName(_ name: String) -> String {
        var cleaned = name
        let suffixes = [
            " Helper (Renderer)", " Helper (GPU)", " Helper (Plugin)",
            " Helper", " Web Content", " Networking",
            " Agent", " Daemon", " Service",
            " (Renderer)", " (GPU)", " (Plugin)",
        ]
        for suffix in suffixes {
            if cleaned.hasSuffix(suffix) {
                cleaned = String(cleaned.dropLast(suffix.count))
                break  // only strip one suffix
            }
        }
        return cleaned
    }

    /// Search standard app directories for a .app matching the name
    private static func searchApplicationsFolders(for name: String) -> NSImage? {
        let searchDirs = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            NSString("~/Applications").expandingTildeInPath
        ]
        for dir in searchDirs {
            let appPath = "\(dir)/\(name).app"
            if FileManager.default.fileExists(atPath: appPath) {
                return NSWorkspace.shared.icon(forFile: appPath)
            }
        }

        // Also try recursive search one level deep in /Applications (for folders like "Utilities")
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: "/Applications") {
            for item in contents where item.hasSuffix(".app") == false {
                let subPath = "/Applications/\(item)/\(name).app"
                if FileManager.default.fileExists(atPath: subPath) {
                    return NSWorkspace.shared.icon(forFile: subPath)
                }
            }
        }

        return nil
    }

    private static func executablePath(for pid: pid_t) -> String? {
        let pathBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(MAXPATHLEN))
        defer { pathBuffer.deallocate() }
        let size = UInt32(MAXPATHLEN)
        guard proc_pidpath(pid, pathBuffer, size) > 0 else { return nil }
        return String(cString: pathBuffer)
    }

    static var defaultIcon: NSImage {
        NSImage(named: NSImage.computerName)
            ?? NSWorkspace.shared.icon(forFile: "/System")
    }
}

// MARK: - AppTraffic

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

    /// Resolved icon — uses cache so resolution only happens once per process name.
    var icon: NSImage {
        IconResolver.resolve(processName: processName, pid: pid)
    }

    var bundleIdentifier: String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
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
