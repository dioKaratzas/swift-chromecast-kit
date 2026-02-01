//
//  ChromecastKit
//  Swift package for Google Cast (Chromecast).
//

import Foundation

/// Helpers that build typed Cast receiver namespace wire requests.
public enum CastReceiverPayloadBuilder {
    /// Builds a receiver `GET_STATUS` request.
    public static func getStatus() -> CastWire.Receiver.GetStatusRequest {
        .init()
    }

    /// Builds a receiver `SET_VOLUME` request for a volume level.
    public static func setVolume(level: Double) -> CastWire.Receiver.SetVolumeRequest {
        .init(volume: .init(level: level, muted: nil))
    }

    /// Builds a receiver `SET_VOLUME` request for mute/unmute.
    public static func setMuted(_ muted: Bool) -> CastWire.Receiver.SetVolumeRequest {
        .init(volume: .init(level: nil, muted: muted))
    }

    /// Builds a receiver `LAUNCH` request for the specified app ID.
    public static func launch(appID: CastAppID) -> CastWire.Receiver.LaunchRequest {
        .init(appId: appID)
    }

    /// Builds a receiver `STOP` request.
    public static func stop(sessionID: CastAppSessionID? = nil) -> CastWire.Receiver.StopRequest {
        .init(sessionId: sessionID)
    }

    /// Builds a receiver `GET_APP_AVAILABILITY` request.
    public static func getAppAvailability(appIDs: [CastAppID]) -> CastWire.Receiver.GetAppAvailabilityRequest {
        .init(appId: appIDs)
    }
}
