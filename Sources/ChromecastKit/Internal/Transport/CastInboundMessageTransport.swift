//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// Transport capability for streaming inbound Cast JSON messages to higher layers.
protocol CastInboundMessageTransport: Sendable {
    func inboundMessages() async -> AsyncStream<CastInboundMessage>
}
