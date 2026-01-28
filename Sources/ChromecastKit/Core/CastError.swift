//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// Errors surfaced by `ChromecastKit`.
public enum CastError: Error, Sendable, Hashable {
    case discoveryFailed(String)
    case connectionFailed(String)
    case disconnected
    case timeout(operation: String)
    case unsupportedNamespace(String)
    case unsupportedFeature(String)
    case invalidResponse(String)
    case requestFailed(code: Int?, message: String)
    case loadFailed(code: Int?, message: String)
    case noActiveMediaSession
    case invalidArgument(String)
}
