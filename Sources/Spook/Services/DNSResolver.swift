import Foundation

actor DNSResolver {
    static let shared = DNSResolver()

    private var cache: [String: CachedHostname] = [:]
    private let cacheDuration: TimeInterval = 300  // 5 minutes

    private struct CachedHostname {
        let hostname: String
        let timestamp: Date
    }

    func resolve(_ ipAddress: String) async -> String {
        // Check cache first
        if let cached = cache[ipAddress] {
            if Date().timeIntervalSince(cached.timestamp) < cacheDuration {
                return cached.hostname
            }
        }

        // Perform reverse DNS lookup
        let hostname = await performReverseDNS(ipAddress)

        // Cache the result
        cache[ipAddress] = CachedHostname(hostname: hostname, timestamp: Date())

        return hostname
    }

    private func performReverseDNS(_ ipAddress: String) async -> String {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var hints = addrinfo()
                hints.ai_flags = AI_NUMERICHOST
                hints.ai_family = AF_UNSPEC

                var result: UnsafeMutablePointer<addrinfo>?

                let status = getaddrinfo(ipAddress, nil, &hints, &result)
                defer { freeaddrinfo(result) }

                guard status == 0, let addrInfo = result else {
                    continuation.resume(returning: ipAddress)
                    return
                }

                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))

                let lookupStatus = getnameinfo(
                    addrInfo.pointee.ai_addr,
                    addrInfo.pointee.ai_addrlen,
                    &hostname,
                    socklen_t(hostname.count),
                    nil,
                    0,
                    0
                )

                if lookupStatus == 0 {
                    let resolved = String(cString: hostname)
                    // Don't return if it's just the IP address again
                    if resolved != ipAddress && !resolved.isEmpty {
                        continuation.resume(returning: resolved)
                        return
                    }
                }

                continuation.resume(returning: ipAddress)
            }
        }
    }

    func clearCache() {
        cache.removeAll()
    }
}
