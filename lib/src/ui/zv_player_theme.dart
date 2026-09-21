import 'package:flutter/material.dart';

/// Visual tokens for the player surface.
///
/// The player is a dark, cinematic context regardless of the host app's theme,
/// so it carries its own tokens rather than inheriting light-mode colours. The
/// defaults are the ZV Player palette: black, crimson, gold, white.
@immutable
class ZvPlayerTheme {
  const ZvPlayerTheme({
    // ZV crimson: played range, thumb, active states.
    this.accent = const Color(0xFFDC143C),
    this.background = const Color(0xFF000000),
    this.onSurface = Colors.white,
    this.onSurfaceMuted = const Color(0xB3FFFFFF),
    this.scrimTop = const Color(0xB3000000),
    this.scrimBottom = const Color(0xE6000000),
    this.trackInactive = const Color(0x40FFFFFF),
    this.trackBuffered = const Color(0x8CFFFFFF),
    this.sheetBackground = const Color(0xF20A0A0A),
    this.controlsFade = const Duration(milliseconds: 220),
    this.autoHideDelay = const Duration(seconds: 4),
    this.seekStep = const Duration(seconds: 10),
  });

  final Color accent;
  final Color background;
  final Color onSurface;
  final Color onSurfaceMuted;
  final Color scrimTop;
  final Color scrimBottom;
  final Color trackInactive;
  final Color trackBuffered;
  final Color sheetBackground;
  final Duration controlsFade;
  final Duration autoHideDelay;
  final Duration seekStep;

  static const ZvPlayerTheme standard = ZvPlayerTheme();

  /// Poppins, bundled with this package so the player looks the same in any
  /// host. Applied as the default text style under the player.
  static const TextStyle textStyle =
      TextStyle(fontFamily: 'Poppins', package: 'zv_player');

  /// Nearest theme from the widget tree, or [standard] when there is none.
  static ZvPlayerTheme of(BuildContext context) {
    final ZvPlayerThemeScope? scope =
        context.dependOnInheritedWidgetOfExactType<ZvPlayerThemeScope>();
    return scope?.theme ?? standard;
  }
}

/// Supplies a [ZvPlayerTheme] to the player subtree.
class ZvPlayerThemeScope extends InheritedWidget {
  const ZvPlayerThemeScope({
    super.key,
    required this.theme,
    required super.child,
  });

  final ZvPlayerTheme theme;

  @override
  bool updateShouldNotify(ZvPlayerThemeScope oldWidget) =>
      oldWidget.theme != theme;
}

/// Formats a duration for the transport bar: `8:07`, or `1:08:07` past an hour.
String formatPlayerDuration(Duration duration) {
  final Duration value = duration < Duration.zero ? Duration.zero : duration;
  final int hours = value.inHours;
  final int minutes = value.inMinutes.remainder(60);
  final int seconds = value.inSeconds.remainder(60);
  final String twoDigitSeconds = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$twoDigitSeconds';
  }
  return '$minutes:$twoDigitSeconds';
}
