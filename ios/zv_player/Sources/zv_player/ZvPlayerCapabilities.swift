import Foundation
import AVFoundation
import AVKit
import UIKit

/// Device capability probe for iOS.
///
/// Reports only what the platform confirms. Notably, `supportsFairPlay` is
/// false here: FairPlay requires a certificate and a key-server integration
/// that ZV Player does not have, so claiming support would be a lie even though
/// every modern iPhone has the hardware.
enum ZvPlayerCapabilities {

    static func probe() -> [String: Any?] {
        var dynamicRange: [String] = ["sdr"]
        var supportsHdr = false

        // The system reports which HDR modes it can actually play back. This is
        // available from iOS 13.4; on anything older the device is treated as
        // SDR rather than guessed from the model.
        if #available(iOS 13.4, *) {
            let modes = AVPlayer.availableHDRModes
            if modes.contains(.hlg) { dynamicRange.append("hlg") }
            if modes.contains(.hdr10) { dynamicRange.append("hdr10") }
            if modes.contains(.dolbyVision) { dynamicRange.append("dolbyVision") }
            supportsHdr = !modes.isEmpty
        }

        // nativeBounds is already in pixels.
        let bounds = UIScreen.main.nativeBounds
        let displayHeight = Int(max(bounds.width, bounds.height))

        return [
            // AVFoundation does not publish a decoder ceiling; leaving this nil
            // is honest, and the display bound below still guides selection.
            "maxSupportedHeight": nil,
            "dynamicRange": dynamicRange,
            "videoCodecs": videoCodecs(),
            "audioCodecs": audioCodecs(),
            "supportsPip": AVPictureInPictureController.isPictureInPictureSupported(),
            "supportsHdrPlayback": supportsHdr,
            "supportsDolbyAudio": true,
            "supportsWidevine": false,
            "supportsFairPlay": false,
            "supportsOfflineDrm": false,
            "isLowMemoryDevice": ProcessInfo.processInfo.physicalMemory < 3_000_000_000,
            "displayHeight": displayHeight
        ]
    }

    private static func videoCodecs() -> [String] {
        var codecs = ["video/avc"]
        if #available(iOS 11.0, *) {
            codecs.append("video/hevc")
        }
        return codecs
    }

    private static func audioCodecs() -> [String] {
        // AAC everywhere; AC-3/E-AC-3 pass-through and decode are supported by
        // AVFoundation on current iOS versions.
        return ["audio/aac", "audio/ac3", "audio/eac3"]
    }
}
