//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

@preconcurrency import Network
import Foundation

enum CastBonjourDiscoveryParser {
    // MARK: Constants

    static let serviceType = "_googlecast._tcp"

    // MARK: Parsing

    static func serviceIdentity(from endpoint: NWEndpoint) -> ServiceIdentity? {
        guard case let .service(name, type, domain, _) = endpoint else {
            return nil
        }
        return .init(name: name, type: type, domain: domain)
    }

    static func txtDictionary(from metadata: NWBrowser.Result.Metadata) -> [String: String] {
        guard case let .bonjour(txtRecord) = metadata else {
            return [:]
        }
        return txtRecord.dictionary
    }

    static func deviceDescriptor(
        serviceName: String,
        resolvedEndpoint: ResolvedEndpoint,
        txt: [String: String]
    ) -> CastDeviceDescriptor {
        let deviceID = CastDeviceID(txt["id"] ?? serviceName)
        let friendlyName = txt["fn"] ?? serviceName
        let modelName = txt["md"]
        let manufacturer = txt["manufacturer"] ?? txt["mf"]
        let uuid = parseUUID(txt["id"])
        let capabilities = parseCapabilities(txt: txt, friendlyName: friendlyName, modelName: modelName)

        return CastDeviceDescriptor(
            id: deviceID,
            friendlyName: friendlyName,
            host: normalizedHost(resolvedEndpoint.host),
            port: resolvedEndpoint.port,
            modelName: modelName,
            manufacturer: manufacturer,
            uuid: uuid,
            capabilities: capabilities
        )
    }

    static func shouldInclude(
        _ descriptor: CastDeviceDescriptor,
        includeGroups: Bool
    ) -> Bool {
        includeGroups || descriptor.capabilities.contains(.group) == false
    }

    private static func normalizedHost(_ host: String) -> String {
        guard host.last == "." else {
            return host
        }
        return String(host.dropLast())
    }

    private static func parseUUID(_ raw: String?) -> UUID? {
        guard let raw, raw.isEmpty == false else {
            return nil
        }
        return UUID(uuidString: raw)
    }

    private static func parseCapabilities(
        txt: [String: String],
        friendlyName: String,
        modelName: String?
    ) -> Set<CastDeviceCapability> {
        var capabilities = Set<CastDeviceCapability>()

        if let raw = txt["ca"], let bitmask = Int(raw) {
            // Chromecast mDNS TXT `ca` is a bitmask. We only map a conservative subset.
            if bitmask & 0x1 != 0 {
                capabilities.insert(.video)
            }
            if bitmask & 0x4 != 0 {
                capabilities.insert(.audio)
            }
            if bitmask & 0x20 != 0 {
                capabilities.insert(.multizone)
            }
        }

        if isLikelyGroup(friendlyName: friendlyName, modelName: modelName) {
            capabilities.insert(.group)
            capabilities.insert(.audio)
            capabilities.insert(.multizone)
        }

        return capabilities
    }

    private static func isLikelyGroup(friendlyName: String, modelName: String?) -> Bool {
        let haystack = [friendlyName, modelName ?? ""]
            .joined(separator: " ")
            .lowercased()
        return haystack.contains("group")
    }
}

extension CastBonjourDiscoveryParser {
    struct ServiceIdentity: Sendable, Hashable {
        let name: String
        let type: String
        let domain: String
    }

    struct ResolvedEndpoint: Sendable, Hashable {
        let host: String
        let port: Int
    }
}
