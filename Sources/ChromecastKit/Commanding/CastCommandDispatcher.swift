//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

struct CastEncodedCommand: Sendable, Hashable {
    let requestID: Int
    let route: CastMessageRoute
    let payloadUTF8: String
}

protocol CastCommandTransport: Sendable {
    func send(_ command: CastEncodedCommand) async throws
}

/// Actor responsible for route resolution, request ID assignment, and payload encoding.
///
/// This layer sits between high-level controllers and the eventual socket/protobuf transport.
/// It keeps transport concerns out of controller APIs while preserving typed payload models.
actor CastCommandDispatcher {
    private let transport: any CastCommandTransport
    private var requestIDs = CastRequestIDGenerator()
    private var sourceID: String
    private var currentApplicationTransportID: String?

    init(
        transport: any CastCommandTransport,
        sourceID: String = "sender-0"
    ) {
        self.transport = transport
        self.sourceID = sourceID
    }

    func setSourceID(_ sourceID: String) {
        self.sourceID = sourceID
    }

    func setCurrentApplicationTransportID(_ transportID: String?) {
        currentApplicationTransportID = transportID
    }

    @discardableResult
    func send<Payload: Encodable & Sendable>(
        namespace: CastNamespace,
        target: CastMessageTarget,
        payload: Payload
    ) async throws -> Int {
        let route = try resolveRoute(namespace: namespace, target: target)
        let requestID = requestIDs.next()
        let payloadUTF8 = try encodePayloadUTF8(payload, requestID: requestID, route: route)
        try await transport.send(.init(requestID: requestID, route: route, payloadUTF8: payloadUTF8))
        return requestID
    }

    private func resolveRoute(
        namespace: CastNamespace,
        target: CastMessageTarget
    ) throws -> CastMessageRoute {
        let destinationID: String

        switch target {
        case .platform:
            destinationID = "receiver-0"
        case let .transport(id):
            destinationID = id
        case .currentApplication:
            guard let currentApplicationTransportID else {
                throw CastError.noActiveMediaSession
            }
            destinationID = currentApplicationTransportID
        }

        return CastMessageRoute(
            sourceID: sourceID,
            destinationID: destinationID,
            namespace: namespace
        )
    }

    private func encodePayloadUTF8<Payload: Encodable & Sendable>(
        _ payload: Payload,
        requestID: Int,
        route: CastMessageRoute
    ) throws -> String {
        let outbound = CastOutboundMessage(route: route, payload: payload)
        let encoded = try CastMessageJSONCodec.encodePayload(outbound)
        var object = try CastMessageJSONCodec.decodePayload([String: JSONValue].self, from: encoded)
        object["requestId"] = .number(Double(requestID))
        return try encodeJSONObject(object)
    }

    private func encodeJSONObject(_ object: [String: JSONValue]) throws -> String {
        let data = try JSONEncoder().encode(object)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CastError.invalidResponse("Failed to encode JSON object payload")
        }
        return string
    }
}

