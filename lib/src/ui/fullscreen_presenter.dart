import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The orientation and system-UI state the app uses everywhere except the
/// player. One definition, so the player and the app cannot disagree.
///
/// [restore] exists because orientation is **native Activity state, not Dart
/// state**. `SystemChrome.setPreferredOrientations` ends up as
/// `Activity.setRequestedOrientation(...)`, which survives a Dart hot restart -
/// while the widget tree that would have released it is torn down without
/// running `dispose()`. A player left in landscape therefore leaked landscape
/// into the whole app until the process was killed. Calling [restore] during
/// app start-up (which also runs on hot restart) re-establishes the baseline
/// deterministically.
class AppOrientationBaseline {
  const AppOrientationBaseline._();

  /// Never the full orientation set: that unlocks rotation app-wide.
  static const List<DeviceOrientation> orientations = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ];

  static const SystemUiMode uiMode = SystemUiMode.edgeToEdge;

  /// How many player presentations currently hold landscape.
  ///
  /// Dart statics are destroyed by a hot restart, which is exactly what makes
  /// this useful: after a restart the count is zero even though the Activity is
  /// still landscape, so [restoreIfUnowned] can tell "nobody owns this any
  /// more, heal it" apart from "a player legitimately wants landscape".
  static int _owners = 0;

  static bool get isOwnedByPlayer => _owners > 0;

  /// Claimed by a presentation before it asks for landscape.
  static void acquire() => _owners++;

  /// Released on every exit path. Never goes negative, so a double release
  /// cannot make a live player look unowned.
  static void release() {
    if (_owners > 0) _owners--;
  }

  /// Puts the app back on its baseline. Safe to call repeatedly.
  static Future<void> restore() async {
    await SystemChrome.setEnabledSystemUIMode(
      uiMode,
      overlays: SystemUiOverlay.values,
    );
    await SystemChrome.setPreferredOrientations(orientations);
  }

  /// Heals stale native orientation without fighting a live player.
  ///
  /// Start-up calls [restore] unconditionally; this runs once the first frame
  /// is up, which is the point at which a recreated player route would already
  /// have claimed landscape for itself. Returns false when it deferred to a
  /// player.
  static Future<bool> restoreIfUnowned() async {
    if (isOwnedByPlayer) return false;
    await restore();
    return true;
  }

  /// Test-only reset of the ownership count, standing in for the fresh statics
  /// a hot restart produces.
  @visibleForTesting
  static void debugResetOwners() => _owners = 0;
}

/// Owns the system-level side of fullscreen: orientation and system chrome.
///
/// Kept separate from the player widget because the previous inline version
/// leaked app-wide state. On exit it called
/// `setPreferredOrientations(DeviceOrientation.values)`, which does not restore
/// what the app had - it *unlocks every orientation for the whole application*,
/// so unrelated screens started rotating after the player had been used once.
///
/// This class instead restores an explicit baseline, supplied by the host, and
/// is safe to call repeatedly.
class FullscreenPresenter {
  FullscreenPresenter({
    this.baseOrientations = AppOrientationBaseline.orientations,
    this.baseUiMode = AppOrientationBaseline.uiMode,
    this.landscapeOrientations = const <DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ],
  });

  /// What the app used before the player appeared. The app locks itself to
  /// portrait in its manifest, so that is the default.
  final List<DeviceOrientation> baseOrientations;
  final SystemUiMode baseUiMode;
  final List<DeviceOrientation> landscapeOrientations;

  /// True from the moment landscape is *asked for* until it is given back -
  /// not from the moment the platform confirms it.
  ///
  /// The distinction is the whole point. Entering takes two awaited platform
  /// calls, and a route can be popped in between. Keying release off "entry
  /// finished" meant a player dismissed mid-entry released nothing: landscape
  /// had already been applied to the Activity, the widget was gone, and nothing
  /// was left alive to put it back.
  bool _owned = false;
  bool _active = false;
  bool _busy = false;

  bool get isActive => _active;

  /// Whether this presentation currently holds landscape, including while it is
  /// still being applied.
  bool get ownsOrientation => _owned;

  /// Enters cinematic fullscreen: landscape plus hidden system bars.
  ///
  /// Idempotent - a second call while already fullscreen does nothing, and
  /// overlapping calls are ignored while one is in flight. If ownership is
  /// released while this is in flight, the baseline is re-applied so the
  /// half-finished entry cannot leave the app rotated.
  Future<bool> enter() async {
    if (_owned || _busy) return false;
    _busy = true;
    _owned = true;
    AppOrientationBaseline.acquire();
    try {
      await SystemChrome.setPreferredOrientations(landscapeOrientations);
      if (!_owned) return await _abandonEntry();
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (!_owned) return await _abandonEntry();
      _active = true;
      return true;
    } finally {
      _busy = false;
    }
  }

  /// Something released us mid-entry; undo whatever reached the platform.
  Future<bool> _abandonEntry() async {
    _active = false;
    await _restoreBaselineUnlessHandedOver();
    return false;
  }

  /// Gives the platform back to the app - unless another presentation has
  /// already taken landscape for itself.
  ///
  /// Replacing one player route with another (a "play next", a re-keyed
  /// rebuild, an Activity recreation) builds the incoming player *before* the
  /// outgoing one is unmounted. Restoring unconditionally therefore let a
  /// dying player overwrite the orientation a live player had just asked for,
  /// leaving a fullscreen video in portrait. Deferring to the registry keeps
  /// the hand-over seamless while still guaranteeing the last player out
  /// restores the baseline.
  Future<void> _restoreBaselineUnlessHandedOver() async {
    if (AppOrientationBaseline.isOwnedByPlayer) return;
    await SystemChrome.setEnabledSystemUIMode(
      baseUiMode,
      overlays: SystemUiOverlay.values,
    );
    await SystemChrome.setPreferredOrientations(baseOrientations);
  }

  /// Restores exactly the orientation set and chrome the app started with.
  ///
  /// Idempotent, and safe to call from dispose paths - including while an
  /// [enter] is still in flight, which is the case that used to leak.
  Future<bool> exit() async {
    if (!_owned) return false;
    _release();
    await _restoreBaselineUnlessHandedOver();
    return true;
  }

  /// Restores the baseline without awaiting, for use in `dispose()`.
  void restoreSynchronously() {
    if (!_owned) return;
    _release();
    if (AppOrientationBaseline.isOwnedByPlayer) return;
    SystemChrome.setEnabledSystemUIMode(
      baseUiMode,
      overlays: SystemUiOverlay.values,
    );
    SystemChrome.setPreferredOrientations(baseOrientations);
  }

  void _release() {
    _owned = false;
    _active = false;
    AppOrientationBaseline.release();
  }
}
