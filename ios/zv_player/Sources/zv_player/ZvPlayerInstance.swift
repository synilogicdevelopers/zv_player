import Flutter
import Foundation
import AVFoundation
import AVKit

/// One playback session backed by AVPlayer.
///
/// Reports state through an event channel rather than letting Flutter poll, and
/// keeps the render layer separate from the session so views can come and go.
class ZvPlayerInstance: NSObject, FlutterStreamHandler, AVPictureInPictureControllerDelegate {

    private let playerId: Int
    private let methodChannel: FlutterMethodChannel
    private let eventChannel: FlutterEventChannel
    private var eventSink: FlutterEventSink?

    private let player = AVPlayer()
    private weak var attachedView: ZvPlayerLayerView?
    private var pipController: AVPictureInPictureController?

    private var timeObserver: Any?
    private var itemObservations: [NSKeyValueObservation] = []
    private var playerObservations: [NSKeyValueObservation] = []
    private var currentAsset: AVURLAsset?
    private var lastReportedStatus: String?
    private var lastReportedLive: Bool?
    /// Where an in-flight seek is going. AVPlayer keeps reporting the old
    /// time until an exact seek lands (seconds, for HLS over the network), and
    /// reporting that stale time snaps the scrubber back as if the seek failed.
    private var seekTarget: CMTime?
    private var seekGeneration = 0
    private var pendingStartPosition: CMTime = .zero

    /// Re-applied whenever a view attaches, so fit survives a rebuild.
    private var videoGravity: AVLayerVideoGravity = .resizeAspect

    /// Track ids are `audio:<index>` / `text:<index>` / `video:<index>`, matching
    /// the order AVFoundation reports them in.
    private var audioOptions: [AVMediaSelectionOption] = []
    private var textOptions: [AVMediaSelectionOption] = []
    private var variantBitrates: [Double] = []
    private var variantSizes: [CGSize] = []

    init(messenger: FlutterBinaryMessenger, playerId: Int) {
        self.playerId = playerId
        self.methodChannel = FlutterMethodChannel(
            name: "zv_player/player_\(playerId)",
            binaryMessenger: messenger
        )
        self.eventChannel = FlutterEventChannel(
            name: "zv_player/events_\(playerId)",
            binaryMessenger: messenger
        )
        super.init()

        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
        eventChannel.setStreamHandler(self)

        observePlayer()
        observeInterruptions()
        startTimeObserver()
    }

    // MARK: - View attachment

    func attach(to view: ZvPlayerLayerView) {
        attachedView = view
        view.playerLayer.player = player
        // Mirrors Android: letterbox by default, crop when asked, never stretch.
        view.playerLayer.videoGravity = videoGravity
        setUpPictureInPicture(with: view.playerLayer)
    }

    /// Detaches `view`, or the current view when nil.
    ///
    /// The identity check matters: a replacement view can attach before the old
    /// one is deallocated, and an unconditional detach would then blank the new
    /// layer while playback continued behind it.
    func detachView(_ view: ZvPlayerLayerView? = nil) {
        if let view = view, attachedView !== view { return }
        attachedView?.playerLayer.player = nil
        attachedView = nil
        pipController = nil
    }

    private func setUpPictureInPicture(with layer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        pipController = AVPictureInPictureController(playerLayer: layer)
        pipController?.delegate = self
    }

    // MARK: - Method channel

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]

        switch call.method {
        case "load":
            load(args)
            result(nil)

        case "play":
            configureAudioSession()
            // play() always resumes at 1.0, which would silently discard a
            // chosen speed every time the viewer paused.
            if currentSpeed != 1.0 {
                player.rate = currentSpeed
            } else {
                player.play()
            }
            result(nil)

        case "pause":
            player.pause()
            result(nil)

        case "seekTo":
            let ms = (args["positionMs"] as? NSNumber)?.doubleValue ?? 0
            let time = CMTime(seconds: ms / 1000.0, preferredTimescale: 600)
            seekGeneration += 1
            let generation = seekGeneration
            seekTarget = time
            emitPosition()
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                guard let self = self else { return }
                // A superseded seek must not clear the newer seek's target.
                if generation == self.seekGeneration { self.seekTarget = nil }
                self.emitPosition()
            }
            result(nil)

        case "setSpeed":
            let speed = (args["speed"] as? NSNumber)?.floatValue ?? 1.0
            // Setting `rate` starts playback; only apply it when already playing.
            if player.timeControlStatus == .playing {
                player.rate = speed
            }
            currentSpeed = speed
            emit(["event": "speed", "speed": Double(speed)])
            result(nil)

        case "setVolume":
            let volume = (args["volume"] as? NSNumber)?.floatValue ?? 1.0
            player.volume = max(0, min(1, volume))
            emitVolume()
            result(nil)

        case "setMuted":
            player.isMuted = (args["muted"] as? Bool) ?? false
            emitVolume()
            result(nil)

        case "selectVideoTrack":
            selectVideoTrack(args["trackId"] as? String)
            result(nil)

        case "selectAudioTrack":
            selectMediaOption(args["trackId"] as? String, characteristic: .audible)
            result(nil)

        case "selectSubtitleTrack":
            selectMediaOption(args["trackId"] as? String, characteristic: .legible)
            result(nil)

        case "enterPictureInPicture":
            result(enterPictureInPicture())

        case "setVideoFit":
            // resizeAspectFill crops the overflow; resizeAspect letterboxes.
            // `resize` (stretch) is deliberately never used.
            let fill = (args["fit"] as? String) == "fill"
            videoGravity = fill ? .resizeAspectFill : .resizeAspect
            attachedView?.playerLayer.videoGravity = videoGravity
            result(nil)

        case "setSecureSurface":
            // iOS has no FLAG_SECURE equivalent. Accepting the call silently
            // would imply a guarantee the platform cannot make.
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private var currentSpeed: Float = 1.0

    private func load(_ args: [String: Any]) {
        guard let uriString = args["uri"] as? String, !uriString.isEmpty,
              let url = URL(string: uriString) ?? URL(fileURLWithPath: uriString) as URL? else {
            emitError(code: "source_unavailable", message: "Empty or invalid media URI", recoverable: false)
            return
        }

        // DRM is an extension point, not a capability yet. Fail loudly.
        if let drm = args["drm"] as? [String: Any],
           let scheme = drm["scheme"] as? String, scheme != "none" {
            emitError(
                code: "drm_unsupported",
                message: "DRM scheme '\(scheme)' is not implemented in ZV Player",
                recoverable: false
            )
            return
        }

        configureAudioSession()

        var options: [String: Any] = [:]
        if let headers = args["headers"] as? [String: String], !headers.isEmpty {
            options["AVURLAssetHTTPHeaderFieldsKey"] = headers
        }

        let asset = AVURLAsset(url: url, options: options)
        currentAsset = asset
        let item = AVPlayerItem(asset: asset)

        let startMs = (args["startPositionMs"] as? NSNumber)?.doubleValue ?? 0
        pendingStartPosition = CMTime(seconds: startMs / 1000.0, preferredTimescale: 600)

        observeItem(item)
        lastReportedLive = nil
        seekTarget = nil
        player.replaceCurrentItem(with: item)
        emitStatus("loading")

        if (args["autoPlay"] as? Bool) ?? true {
            player.play()
        }
    }

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true, options: [])
        } catch {
            emit([
                "event": "error",
                "code": "audio_session",
                "message": "Audio session could not be configured",
                "detail": error.localizedDescription,
                "recoverable": true
            ])
        }
    }

    // MARK: - Observation

    private func observePlayer() {
        playerObservations.append(
            player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                guard let self = self else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.emitStatus("playing")
                    if self.currentSpeed != 1.0 && player.rate != self.currentSpeed {
                        player.rate = self.currentSpeed
                    }
                case .paused:
                    if self.lastReportedStatus != "completed" {
                        self.emitStatus("paused")
                    }
                case .waitingToPlayAtSpecifiedRate:
                    self.emitStatus("buffering")
                @unknown default:
                    break
                }
            }
        )
    }

    private func observeItem(_ item: AVPlayerItem) {
        itemObservations.forEach { $0.invalidate() }
        itemObservations.removeAll()
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)

        itemObservations.append(
            item.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard let self = self else { return }
                switch item.status {
                case .readyToPlay:
                    if self.pendingStartPosition > .zero {
                        self.player.seek(to: self.pendingStartPosition)
                        self.pendingStartPosition = .zero
                    }
                    self.emitStatus(self.player.timeControlStatus == .playing ? "playing" : "ready")
                    self.emitTracks(for: item)
                    self.emitPosition()
                    self.emitPresentationSize(item)
                case .failed:
                    let error = item.error as NSError?
                    self.emitError(
                        code: self.errorCode(for: error),
                        message: error?.localizedDescription ?? "Playback failed",
                        detail: error?.debugDescription,
                        recoverable: self.isRecoverable(error)
                    )
                default:
                    break
                }
            }
        )

        itemObservations.append(
            item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
                if item.isPlaybackBufferEmpty {
                    self?.emitStatus("buffering")
                }
            }
        )

        itemObservations.append(
            item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
                guard let self = self else { return }
                if item.isPlaybackLikelyToKeepUp {
                    self.emitStatus(self.player.timeControlStatus == .playing ? "playing" : "ready")
                }
            }
        )

        itemObservations.append(
            item.observe(\.presentationSize, options: [.new]) { [weak self] item, _ in
                self?.emitPresentationSize(item)
            }
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaybackEnded),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }

        switch type {
        case .began:
            // A call or another app took audio focus.
            emitStatus("paused")
        case .ended:
            if let rawOptions = info[AVAudioSessionInterruptionOptionKey] as? UInt,
               AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume) {
                player.play()
            }
        @unknown default:
            break
        }
    }

    @objc private func handlePlaybackEnded() {
        emitStatus("completed")
        emit(["event": "completed"])
    }

    private func startTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] _ in
            self?.emitPosition()
        }
    }

    // MARK: - Tracks

    private func emitTracks(for item: AVPlayerItem) {
        let asset = item.asset

        audioOptions = mediaOptions(for: asset, characteristic: .audible)
        textOptions = mediaOptions(for: asset, characteristic: .legible)

        let selection = item.currentMediaSelection
        let audioGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .audible)
        let textGroup = asset.mediaSelectionGroup(forMediaCharacteristic: .legible)

        let audio: [[String: Any?]] = audioOptions.enumerated().map { index, option in
            let selected = audioGroup.flatMap { selection.selectedMediaOption(in: $0) } == option
            return [
                "id": "audio:\(index)",
                "language": option.extendedLanguageTag ?? "",
                "label": option.displayName,
                "codec": nil,
                "channels": nil,
                "isSelected": selected
            ]
        }

        let text: [[String: Any?]] = textOptions.enumerated().map { index, option in
            let selected = textGroup.flatMap { selection.selectedMediaOption(in: $0) } == option
            return [
                "id": "text:\(index)",
                "language": option.extendedLanguageTag ?? "",
                "label": option.displayName,
                "format": nil,
                "isExternal": false,
                "isSelected": selected
            ]
        }

        emit([
            "event": "tracks",
            "video": videoVariants(for: asset),
            "audio": audio,
            "text": text
        ])
    }

    private func mediaOptions(
        for asset: AVAsset,
        characteristic: AVMediaCharacteristic
    ) -> [AVMediaSelectionOption] {
        guard let group = asset.mediaSelectionGroup(forMediaCharacteristic: characteristic) else {
            return []
        }
        // Drop the "none" placeholder AVFoundation adds for subtitles; the UI
        // supplies its own Off entry.
        return group.options.filter { option in
            !(characteristic == .legible && option.mediaType == .subtitle && option.displayName.isEmpty)
        }
    }

    /// HLS renditions, when the OS exposes them (iOS 15+). Older systems get an
    /// empty list rather than invented qualities, and adaptive selection still
    /// works - it simply cannot be overridden by rung.
    private func videoVariants(for asset: AVAsset) -> [[String: Any?]] {
        variantBitrates = []
        variantSizes = []

        guard #available(iOS 15.0, *), let urlAsset = asset as? AVURLAsset else {
            return []
        }

        var result: [[String: Any?]] = []
        let sorted = urlAsset.variants.sorted { lhs, rhs in
            (lhs.peakBitRate ?? 0) > (rhs.peakBitRate ?? 0)
        }

        for (index, variant) in sorted.enumerated() {
            let size = variant.videoAttributes?.presentationSize
            let height = size.map { Int($0.height) }
            variantBitrates.append(variant.peakBitRate ?? 0)
            variantSizes.append(size ?? .zero)
            result.append([
                "id": "video:\(index)",
                "label": label(forHeight: height),
                "width": size.map { Int($0.width) },
                "height": height,
                "bitrate": variant.peakBitRate.map { Int($0) },
                "codec": nil,
                "isSelected": false
            ])
        }
        return result
    }

    private func label(forHeight height: Int?) -> String {
        guard let height = height else { return "Auto" }
        switch height {
        case 2160...: return "4K"
        case 1440..<2160: return "1440p"
        case 1080..<1440: return "1080p"
        case 720..<1080: return "720p"
        case 480..<720: return "480p"
        case 360..<480: return "360p"
        default: return "240p"
        }
    }

    /// Caps the adaptive ladder rather than pinning one rendition: AVPlayer keeps
    /// adapting below the cap, which is the platform-native way to do this.
    private func selectVideoTrack(_ trackId: String?) {
        guard let item = player.currentItem else { return }

        guard let trackId = trackId,
              let index = Int(trackId.split(separator: ":").last.map(String.init) ?? ""),
              index < variantBitrates.count else {
            item.preferredPeakBitRate = 0
            if #available(iOS 11.0, *) {
                item.preferredMaximumResolution = .zero
            }
            return
        }

        item.preferredPeakBitRate = variantBitrates[index]
        if #available(iOS 11.0, *) {
            item.preferredMaximumResolution = variantSizes[index]
        }
    }

    private func selectMediaOption(_ trackId: String?, characteristic: AVMediaCharacteristic) {
        guard let item = player.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: characteristic) else {
            return
        }

        guard let trackId = trackId,
              let index = Int(trackId.split(separator: ":").last.map(String.init) ?? "") else {
            // Null means off, which only applies to subtitles.
            if characteristic == .legible {
                item.select(nil, in: group)
            }
            return
        }

        let options = characteristic == .audible ? audioOptions : textOptions
        guard index < options.count else { return }
        item.select(options[index], in: group)
        if let currentItem = player.currentItem {
            emitTracks(for: currentItem)
        }
    }

    // MARK: - Picture in Picture

    private func enterPictureInPicture() -> Bool {
        guard AVPictureInPictureController.isPictureInPictureSupported(),
              let controller = pipController,
              controller.isPictureInPicturePossible else {
            return false
        }
        controller.startPictureInPicture()
        return true
    }

    func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        emit(["event": "pip", "isInPip": true])
    }

    func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        emit(["event": "pip", "isInPip": false])
    }

    // MARK: - Events

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    /// Sends an event to Flutter.
    ///
    /// Optionals are converted to `NSNull` first: a Swift dictionary holding a
    /// `nil` value does not bridge cleanly to the standard message codec.
    private func emit(_ payload: [String: Any?]) {
        var sanitised: [String: Any] = [:]
        for (key, value) in payload {
            sanitised[key] = value ?? NSNull()
        }
        DispatchQueue.main.async { [weak self] in
            self?.eventSink?(sanitised)
        }
    }

    private func emitStatus(_ status: String) {
        guard status != lastReportedStatus else { return }
        lastReportedStatus = status
        emit(["event": "status", "status": status])
    }

    private func emitPosition() {
        guard let item = player.currentItem else { return }
        let durationSeconds = item.duration.seconds
        let duration = durationSeconds.isFinite ? durationSeconds : 0
        let buffered = item.loadedTimeRanges.first.map { value -> Double in
            let range = value.timeRangeValue
            return range.start.seconds + range.duration.seconds
        } ?? 0

        emit([
            "event": "position",
            "positionMs": Int((seekTarget ?? player.currentTime()).seconds * 1000),
            "bufferedMs": Int(buffered * 1000),
            "durationMs": Int(duration * 1000)
        ])

        // An item's duration is indefinite until it is ready, so only a *ready*
        // item without a finite duration is live. Reporting "live" earlier
        // marked every HLS VOD as live for good, which disables seeking.
        // Reported both ways so an early value can never stick.
        if item.status == .readyToPlay {
            let isLive = !durationSeconds.isFinite
            if isLive != lastReportedLive {
                lastReportedLive = isLive
                emit(["event": "isLive", "isLive": isLive])
            }
        }
    }

    private func emitPresentationSize(_ item: AVPlayerItem) {
        let size = item.presentationSize
        guard size.width > 0, size.height > 0 else { return }
        emit([
            "event": "videoSize",
            "width": Int(size.width),
            "height": Int(size.height)
        ])
    }

    private func emitVolume() {
        emit([
            "event": "volume",
            "volume": Double(player.volume),
            "muted": player.isMuted
        ])
    }

    private func emitError(code: String, message: String, detail: String? = nil, recoverable: Bool) {
        emit([
            "event": "error",
            "code": code,
            "message": message,
            "detail": detail,
            "recoverable": recoverable
        ])
    }

    private func errorCode(for error: NSError?) -> String {
        guard let error = error else { return "unknown" }
        switch error.code {
        case NSURLErrorTimedOut: return "timeout"
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost: return "network"
        case NSURLErrorFileDoesNotExist, NSURLErrorBadURL: return "source_unavailable"
        default:
            return error.domain == AVFoundationErrorDomain ? "unsupported_format" : "unknown"
        }
    }

    private func isRecoverable(_ error: NSError?) -> Bool {
        guard let error = error else { return false }
        switch error.code {
        case NSURLErrorTimedOut,
             NSURLErrorNotConnectedToInternet,
             NSURLErrorNetworkConnectionLost,
             NSURLErrorCannotConnectToHost:
            return true
        default:
            return false
        }
    }

    // MARK: - Teardown

    func dispose() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        itemObservations.forEach { $0.invalidate() }
        itemObservations.removeAll()
        playerObservations.forEach { $0.invalidate() }
        playerObservations.removeAll()
        NotificationCenter.default.removeObserver(self)
        player.pause()
        player.replaceCurrentItem(with: nil)
        detachView()
        methodChannel.setMethodCallHandler(nil)
        eventChannel.setStreamHandler(nil)
        eventSink = nil
    }

    deinit {
        dispose()
    }
}
