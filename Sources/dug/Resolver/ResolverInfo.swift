import Foundation
import SystemConfiguration

/// DNS resolver configuration for a network interface, read from SystemConfiguration.
struct ResolverConfig: Equatable {
    let nameservers: [String]
    let searchDomains: [String]
    let domain: String?
}

/// Reads macOS DNS resolver configurations without shelling out.
/// Uses SCDynamicStore to access the same data as `scutil --dns`.
enum ResolverInfo {
    /// Build a map of interface name → resolver config.
    /// The "global" key holds the system-wide default resolver.
    static func resolverConfigs() -> [String: ResolverConfig] {
        guard let store = SCDynamicStoreCreate(nil, "dug" as CFString, nil, nil) else {
            return [:]
        }

        var configs: [String: ResolverConfig] = [:]

        // Per-service resolver configs
        let pattern = "State:/Network/Service/.*/DNS" as CFString
        if let keys = SCDynamicStoreCopyKeyList(store, pattern) as? [String] {
            for key in keys {
                guard let config = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any] else {
                    continue
                }
                let iface = config["InterfaceName"] as? String ?? "default"
                configs[iface] = ResolverConfig(
                    nameservers: config["ServerAddresses"] as? [String] ?? [],
                    searchDomains: config["SearchDomains"] as? [String] ?? [],
                    domain: config["DomainName"] as? String
                )
            }
        }

        // Global DNS config
        if let dns = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any] {
            configs["global"] = ResolverConfig(
                nameservers: dns["ServerAddresses"] as? [String] ?? [],
                searchDomains: dns["SearchDomains"] as? [String] ?? [],
                domain: nil
            )
        }

        return configs
    }

    /// Look up the resolver config for a given interface name.
    /// Falls back to the global config if the interface has no specific resolver.
    static func config(
        forInterface iface: String?, from configs: [String: ResolverConfig]
    ) -> ResolverConfig? {
        if let iface, let config = configs[iface] {
            return config
        }
        return configs["global"]
    }
}
