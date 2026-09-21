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
