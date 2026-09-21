## 0.1.1

- The YouTube engine now uses Flutter's official `webview_flutter` instead of
  `flutter_inappwebview`, whose Android implementation fails to build with
  Android Gradle Plugin 9. Fresh Flutter projects on the default AGP 9 now
  build with `zv_player`.
- No API or behaviour changes: YouTube still plays through the official IFrame
  Player API with YouTube's controls hidden, under the ZV Player controls.
- iOS: the web view's minimum is iOS 13.

## 0.1.0

- Initial release.
- `ZvPlayer` widget and `ZvPlayerController`: one capability-driven player UI
  for every source.
- Native playback of progressive, HLS, DASH and local sources on Android
  (Media3) and progressive, HLS and local sources on iOS (AVPlayer).
- YouTube playback through the official IFrame Player API under the ZV Player
  controls.
- iOS: HLS VOD is no longer treated as live while its duration is loading, and
  the timeline no longer snaps back during a pending seek.
