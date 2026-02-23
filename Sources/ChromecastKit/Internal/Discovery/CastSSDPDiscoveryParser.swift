//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

enum CastSSDPDiscoveryParser {
    // MARK: Constants

    static let multicastHost = "239.255.255.250"
    static let multicastPort = 1900
    static let dialSearchTarget = "urn:dial-multiscreen-org:service:dial:1"

    // MARK: Parsing

    static func parseSearchResponse(_ data: Data) -> Response? {
        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first,
              first.uppercased().hasPrefix("HTTP/1.1 200") || first.uppercased().hasPrefix("HTTP/1.0 200") else {
            return nil
        }

        var headers = [String: String]()
        for line in lines.dropFirst() {
            guard let idx = line.firstIndex(of: ":") else {
                continue
            }
            let key = line[..<idx].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: idx)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        guard let locationRaw = headers["location"], let locationURL = URL(string: locationRaw) else {
            return nil
        }

        return .init(
            locationURL: locationURL,
            usn: headers["usn"],
            searchTarget: headers["st"],
            cacheMaxAge: parseCacheMaxAge(headers["cache-control"])
        )
    }

    static func isDialResponse(_ response: Response) -> Bool {
        let st = response.searchTarget?.lowercased()
        let usn = response.usn?.lowercased()
        return st == dialSearchTarget || usn?.contains(dialSearchTarget) == true
    }

    static func parseDIALDeviceDescription(_ data: Data) -> DIALDeviceDescription? {
        let parser = XMLParser(data: data)
        let delegate = XMLDeviceDescriptionDelegate()
        parser.delegate = delegate
        guard parser.parse() else {
            return nil
        }
        return delegate.makeDescription()
    }

    static func makeDescriptor(
        from response: Response,
        description: DIALDeviceDescription,
        includeGroups: Bool
    ) -> CastDeviceDescriptor? {
        let host = response.locationURL.host ?? response.locationURL.absoluteString
        let port = response.locationURL.port ?? 8009

        let friendlyName = description.friendlyName?.nonEmpty ?? host
        let modelName = description.modelName?.nonEmpty
        let manufacturer = description.manufacturer?.nonEmpty
        let uuid = description.uuid
        let fallbackID: CastDeviceID = uuid.map { CastDeviceID($0.uuidString.lowercased()) }
            ?? CastDeviceID("ssdp:\(host):\(port)")
        let id = description.udn.flatMap(normalizeDeviceID(fromUDN:)) ?? fallbackID

        var capabilities = Set<CastDeviceCapability>()
        if let modelNameLower = modelName?.lowercased() {
            if modelNameLower.contains("audio") || modelNameLower.contains("speaker") {
                capabilities.insert(.audio)
            }
            if modelNameLower.contains("cast group") || modelNameLower.contains("group") {
                capabilities.insert(.group)
                capabilities.insert(.multizone)
            }
        }
        if capabilities.isEmpty || capabilities.contains(.group) == false {
            capabilities.insert(.video)
        }

        let descriptor = CastDeviceDescriptor(
            id: id,
            friendlyName: friendlyName,
            host: host,
            port: port,
            modelName: modelName,
            manufacturer: manufacturer,
            uuid: uuid,
            capabilities: capabilities
        )

        guard CastBonjourDiscoveryParser.shouldInclude(descriptor, includeGroups: includeGroups) else {
            return nil
        }
        return descriptor
    }

    private static func normalizeDeviceID(fromUDN udn: String) -> CastDeviceID? {
        let trimmed = udn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }
        let normalized = trimmed.lowercased().hasPrefix("uuid:") ? String(trimmed.dropFirst(5)) : trimmed
        return CastDeviceID(normalized.lowercased())
    }

    private static func parseCacheMaxAge(_ cacheControl: String?) -> TimeInterval? {
        guard let cacheControl else {
            return nil
        }

        for part in cacheControl.split(separator: ",") {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.lowercased().hasPrefix("max-age=") else {
                continue
            }
            let raw = trimmed.dropFirst("max-age=".count)
            if let seconds = TimeInterval(raw) {
                return seconds
            }
        }
        return nil
    }
}

extension CastSSDPDiscoveryParser {
    struct Response: Sendable, Hashable {
        let locationURL: URL
        let usn: String?
        let searchTarget: String?
        let cacheMaxAge: TimeInterval?
    }

    struct DIALDeviceDescription: Sendable, Hashable {
        let friendlyName: String?
        let modelName: String?
        let manufacturer: String?
        let udn: String?
        let uuid: UUID?
    }
}

private extension CastSSDPDiscoveryParser {
    // MARK: XML Parsing Delegate

    final class XMLDeviceDescriptionDelegate: NSObject, XMLParserDelegate {
        private var currentElement: String?
        private var currentText = ""
        private var friendlyName: String?
        private var modelName: String?
        private var manufacturer: String?
        private var udn: String?

        func parser(
            _: XMLParser,
            didStartElement elementName: String,
            namespaceURI _: String?,
            qualifiedName _: String?,
            attributes _: [String: String] = [:]
        ) {
            currentElement = localElementName(elementName)
            currentText = ""
        }

        func parser(_: XMLParser, foundCharacters string: String) {
            currentText += string
        }

        func parser(
            _: XMLParser,
            didEndElement elementName: String,
            namespaceURI _: String?,
            qualifiedName _: String?
        ) {
            let element = localElementName(elementName)
            let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.isEmpty == false else {
                currentElement = nil
                currentText = ""
                return
            }

            switch element {
            case "friendlyname": friendlyName = value
            case "modelname": modelName = value
            case "manufacturer": manufacturer = value
            case "udn": udn = value
            default: break
            }

            currentElement = nil
            currentText = ""
        }

        // MARK: Description

        func makeDescription() -> DIALDeviceDescription {
            let parsedUUID: UUID?
            if let udn {
                let normalized = udn.lowercased().hasPrefix("uuid:") ? String(udn.dropFirst(5)) : udn
                parsedUUID = UUID(uuidString: normalized)
            } else {
                parsedUUID = nil
            }

            return .init(
                friendlyName: friendlyName,
                modelName: modelName,
                manufacturer: manufacturer,
                udn: udn,
                uuid: parsedUUID
            )
        }

        private func localElementName(_ name: String) -> String {
            let lowered = name.lowercased()
            guard let colon = lowered.lastIndex(of: ":") else {
                return lowered
            }
            return String(lowered[lowered.index(after: colon)...])
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
