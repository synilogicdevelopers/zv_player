## 0.1.2

- Source routing: a YouTube or Vimeo address is recognised by its host before
  any declared type or extension, so a mislabelled watch URL can never reach
  Media3/AVPlayer. A Google redirect whose destination is readable
  (`google.<tld>/url?q=…`) is unwrapped locally; an opaque one
  (`google.com/goto?url=…`) is reported as unsupported instead of being
  guessed to be a media file. Nothing is fetched to resolve either.
- `ZvPlayerController.open()` now releases the previous engine (listener,
  native player or web view) before starting the next source, and a
  superseded or disposed open stops cleanly. Playback state resets for the
  new source; fullscreen and fit carry over.
- Seek preview: while the timeline is dragged, the target time is shown in a
  small bubble above the thumb, kept inside the bar. Timestamp only; no video
  frames are fetched, so it behaves identically for native media and YouTube.

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
