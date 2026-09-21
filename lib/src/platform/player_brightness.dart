import 'package:flutter/services.dart';

/// Screen brightness while the player is open.
///
/// Platform-aware by design, and deliberately conservative:
///
/// - **Android** sets a *window* brightness override. It applies only while the
///   app's window is in front and disappears when the app does, so it never
///   changes the device's own setting.
/// - **iOS** has no window-level override; `UIScreen.brightness` is the system
///   setting. The original value is captured on first change and restored on
///   [restore], including when the player is disposed or backgrounded.
///
/// If a platform cannot support it, [isSupported] is false and the control is
/// not offered rather than faked.
class PlayerBrightness {
  PlayerBrightness({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('zv_player/global');

  final MethodChannel _channel;

  double? _current;
  bool _supported = true;

  /// Last value this controller applied, or null if it has not changed it.
  double? get current => _current;

  bool get isSupported => _supported;

  /// Reads the current brightness, 0..1, or null when unavailable.
  Future<double?> read() async {
    try {
      final double? value =
          await _channel.invokeMethod<double>('getBrightness');
      if (value == null) {
        _supported = false;
        return null;
      }
      return value.clamp(0.0, 1.0);
    } on PlatformException {
      _supported = false;
      return null;
    } on MissingPluginException {
      _supported = false;
      return null;
    }
  }

  /// Applies [value] (0..1). Returns false when the platform refused, which
  /// leaves the caller free to hide the control.
  Future<bool> set(double value) async {
    final double clamped = value.clamp(0.0, 1.0);
    try {
      await _channel.invokeMethod<void>('setBrightness', <String, dynamic>{
        'brightness': clamped,
      });
      _current = clamped;
      return true;
    } on PlatformException {
      _supported = false;
      return false;
    } on MissingPluginException {
      _supported = false;
      return false;
    }
  }

  /// Hands brightness back to the system. Safe to call repeatedly and from
  /// dispose paths; does nothing if this controller never changed it.
  Future<void> restore() async {
    if (_current == null) return;
    _current = null;
    try {
      await _channel.invokeMethod<void>('restoreBrightness');
    } catch (_) {
      // Teardown must never throw.
    }
  }
}
