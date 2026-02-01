//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// Message route metadata for a Cast message frame.
public struct CastMessageRoute: Sendable, Hashable, Codable {
    public let sourceID: CastEndpointID
    public let destinationID: CastEndpointID
    public let namespace: CastNamespace

    public init(
        sourceID: CastEndpointID,
        destinationID: CastEndpointID,
        namespace: CastNamespace
    ) {
        self.sourceID = sourceID
        self.destinationID = destinationID
        self.namespace = namespace
    }

    /// Standard sender route to the Cast platform destination (`receiver-0`).
    public static func platform(
        sourceID: CastEndpointID = "sender-0",
        namespace: CastNamespace
    ) -> Self {
        .init(sourceID: sourceID, destinationID: "receiver-0", namespace: namespace)
    }
}

/// A typed outbound Cast message prior to protobuf framing/transport encoding.
public struct CastOutboundMessage<Payload: Encodable & Sendable>: Sendable {
    public let route: CastMessageRoute
    public let payload: Payload

    public init(route: CastMessageRoute, payload: Payload) {
        self.route = route
        self.payload = payload
    }
}

/// A raw inbound Cast JSON message payload paired with route metadata.
public struct CastInboundMessage: Sendable, Hashable, Codable {
    public let route: CastMessageRoute
    public let payloadUTF8: String

    public init(route: CastMessageRoute, payloadUTF8: String) {
        self.route = route
        self.payloadUTF8 = payloadUTF8
    }
}
