//
//  ChromecastKit
//  SPDX-License-Identifier: Apache-2.0
//  Copyright 2026 Dionysis Karatzas
//

import Foundation

struct CastInboundBinaryMessage: Sendable, Hashable, Codable {
    let route: CastMessageRoute
    let payloadBinary: Data
}

enum CastInboundTransportEvent: Sendable, Hashable {
    case utf8(CastInboundMessage)
    case binary(CastInboundBinaryMessage)
    case closed
    case failure(CastError)
}

/// Transport capability for streaming inbound Cast transport events.
protocol CastInboundEventTransport: Sendable {
    func inboundEvents() async -> AsyncStream<CastInboundTransportEvent>
}

/// Transport capability for streaming inbound Cast JSON messages to higher layers.
protocol CastInboundMessageTransport: Sendable {
    func inboundMessages() async -> AsyncStream<CastInboundMessage>
}
