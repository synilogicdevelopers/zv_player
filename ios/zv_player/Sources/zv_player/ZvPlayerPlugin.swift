import Flutter
import UIKit
import AVFoundation
import AVKit

/// Entry point for FilmiLallten Player V1 on iOS.
///
/// Mirrors the Android plugin: players are created and owned here, views attach
/// to them, and one playback session survives any number of views.
public class ZvPlayerPlugin: NSObject, FlutterPlugin {

    private let messenger: FlutterBinaryMessenger
    private var players: [Int: ZvPlayerInstance] = [:]
    private var nextPlayerId = 1

    /// iOS has no window-level brightness override - `UIScreen.brightness` is
    /// the device setting - so the original value is captured before the first
    /// change and put back on restore, dispose or backgrounding.
    private var originalBrightness: CGFloat?

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "zv_player/global",
            binaryMessenger: registrar.messenger()
        )
        let instance = ZvPlayerPlugin(messenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.register(
            ZvPlayerViewFactory(plugin: instance),
            withId: "zv_player/view"
        )
    }

    func player(for id: Int) -> ZvPlayerInstance? {
        return players[id]
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "create":
            let id = nextPlayerId
            nextPlayerId += 1
            players[id] = ZvPlayerInstance(messenger: messenger, playerId: id)
            result(id)

        case "dispose":
            let args = call.arguments as? [String: Any]
            if let id = args?["playerId"] as? Int, let player = players.removeValue(forKey: id) {
                player.dispose()
            }
            result(nil)

        case "getBrightness":
            result(Double(UIScreen.main.brightness))

        case "setBrightness":
            let args = call.arguments as? [String: Any]
            guard let requested = (args?["brightness"] as? NSNumber)?.doubleValue else {
                result(nil)
                return
            }
            if originalBrightness == nil {
                originalBrightness = UIScreen.main.brightness
            }
            UIScreen.main.brightness = CGFloat(max(0, min(1, requested)))
            result(nil)

        case "restoreBrightness":
            if let original = originalBrightness {
                UIScreen.main.brightness = original
                originalBrightness = nil
            }
            result(nil)

        case "capabilities":
            result(ZvPlayerCapabilities.probe())

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

/// Creates the `AVPlayerLayer`-backed view for an existing player.
class ZvPlayerViewFactory: NSObject, FlutterPlatformViewFactory {

    private weak var plugin: ZvPlayerPlugin?

    init(plugin: ZvPlayerPlugin) {
        self.plugin = plugin
        super.init()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        let params = args as? [String: Any]
        let playerId = params?["playerId"] as? Int
        let instance = playerId.flatMap { plugin?.player(for: $0) }
        return ZvPlayerPlatformView(frame: frame, instance: instance)
    }
}

/// Hosts the player's render layer. Disposing detaches; it never stops playback.
class ZvPlayerPlatformView: NSObject, FlutterPlatformView {

    private let container: ZvPlayerLayerView
    private weak var instance: ZvPlayerInstance?

    init(frame: CGRect, instance: ZvPlayerInstance?) {
        self.container = ZvPlayerLayerView(frame: frame)
        self.instance = instance
        super.init()
        container.backgroundColor = .black
        if let instance = instance {
            instance.attach(to: container)
        }
    }

    func view() -> UIView {
        return container
    }

    deinit {
        // Detach only this view, never whichever view is current.
        instance?.detachView(container)
    }
}

/// A view whose backing layer *is* the `AVPlayerLayer`, so the layer always
/// matches the view's bounds - no manual frame syncing on rotation.
class ZvPlayerLayerView: UIView {

    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }

    var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }
}
