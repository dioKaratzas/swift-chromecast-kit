//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Foundation

/// Message route metadata for a Cast message frame.
struct CastMessageRoute: Sendable, Hashable, Codable {
    let sourceID: CastEndpointID
    let destinationID: CastEndpointID
    let namespace: CastNamespace

    /// Standard sender route to the Cast platform destination (`receiver-0`).
    static func platform(
        sourceID: CastEndpointID = "sender-0",
        namespace: CastNamespace
    ) -> Self {
        .init(sourceID: sourceID, destinationID: "receiver-0", namespace: namespace)
    }
}

/// A typed outbound Cast message prior to protobuf framing/transport encoding.
struct CastOutboundMessage<Payload: Encodable & Sendable>: Sendable {
    let route: CastMessageRoute
    let payload: Payload
}

/// A raw inbound Cast JSON message payload paired with route metadata.
struct CastInboundMessage: Sendable, Hashable, Codable {
    let route: CastMessageRoute
    let payloadUTF8: String
}
