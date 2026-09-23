## 0.1.3

- Playback now stops when another page is pushed over the player's route. A
  pushed route does not dispose the page beneath it, so an autoplaying trailer
  used to keep running - and keep making sound - behind the screen the viewer
  had moved on to. The player watches its own route and pauses the engine (the
  native session or the YouTube web view) the moment it is covered, including
  when a still-loading `open()` only finishes after the viewer has left.
  Non-opaque overlays - the settings sheet, dialogs - leave playback alone, and
  a player already in Picture in Picture is exempt. Opt out with
  `ZvPlayer(pauseWhenRouteObscured: false)`.
- New `ZvPlayerController.release()`: ends the session and releases the engine
  without ending the controller, which stays reusable for a later `open()`.
- Picture in Picture now reflects what the device can actually do. Android
  hardware that does not report `FEATURE_PICTURE_IN_PICTURE` - a large share of
  phones - previously still showed a PiP button that could never work; the
  native engine now takes the answer from the device probe and hides it.
- Android no longer needs the host Activity to forward
  `onPictureInPictureModeChanged` for the player to know it is in PiP. The
  plugin watches the Activity's own mode while a PiP window is up, so
  `isPip` is reported on entering *and* leaving. Hosts that already forward the
  callback keep working and are no longer double-reported.
- Picture in Picture is documented and covered by tests as an engine-reported
  capability: native media (MP4/HLS/DASH) offers real platform PiP - Android
  `PictureInPictureParams`, iOS `AVPictureInPictureController` - while the
  YouTube IFrame engine reports it as unsupported, so no PiP button is shown
  for it. Nothing is extracted or scraped to make YouTube fit.

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
