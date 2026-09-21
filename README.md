# zv_player

A cinematic, capability-driven video player for Flutter: one player UI for
every source.

| Source | Engine | Android | iOS |
|---|---|---|---|
| Progressive (MP4, MKV, WebM, MOV…) | Native | Media3 / ExoPlayer | AVPlayer |
| HLS (`.m3u8`) | Native | Media3 | AVPlayer |
| DASH (`.mpd`) | Native | Media3 | Not supported by AVPlayer (reported as an error) |
| Local files | Native | Media3 | AVPlayer |
| YouTube URLs | YouTube | IFrame Player API | IFrame Player API |
| Vimeo / generic iframes | – | Unsupported (reported as an error) | Unsupported |

Every source is shown with the same ZV Player chrome: back, title, cast, mini
player, captions, settings, brightness, centre play/pause with ±10 s, double-tap
seek, a full-width timeline with played / buffered / remaining ranges,
fullscreen, lock, speed and audio & subtitles. Controls are
**capability-driven**: a control appears only when the active engine can
really honour it for the current media.

## YouTube

YouTube URLs play through YouTube's official
[IFrame Player API](https://developers.google.com/youtube/iframe_api_reference)
with YouTube's own controls switched off (`controls: 0`). The embed receives no
touches; ZV Player's controls drive it through the API (play, pause, seek,
volume, mute, speed). Media is never extracted or downloaded from YouTube.
Quality, captions and audio tracks stay under YouTube's control, so those
controls are not shown for YouTube sources. YouTube may still show its own
branding, ads or end screens inside the video area.

YouTube requires a valid referrer for embedded playback. Pass your own https
origin:

```dart
ZvPlayerController(
  router: SourceRouter.standard(
    youTubeOrigin: Uri.parse('https://your-domain.example'),
  ),
);
```

## Usage

```dart
import 'package:zv_player/zv_player.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.url});
  final String url;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final ZvPlayerController controller = ZvPlayerController();

  @override
  void initState() {
    super.initState();
    controller.open(ZvMediaSource.detect(uri: widget.url, title: 'Movie'));
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ZvPlayer(
        controller: controller,
        title: 'Movie',
        onBack: () => Navigator.of(context).pop(),
      ),
    );
  }
}
```

`ZvMediaSource.detect` classifies a URL from its host and extension, and an
optional backend `declaredType` (`'hls'`, `'dash'`, `'youtube'`, `'local'`…).
Pass `startPosition` to resume, `variants` for multiple renditions and
`externalSubtitles` for side-loaded subtitle files.

### Architecture

```
ZvMediaSource ─▶ ZvPlayerController ─▶ SourceRouter ─▶ PlaybackEngine
                        │                               ├─ NativeMediaEngine (Media3 / AVPlayer)
                        ▼                               └─ YouTubeEngine (IFrame API)
                    ZvPlayer (UI, capability-driven)
```

- `ZvPlayerController` owns one playback session: routing, engine lifecycle,
  connectivity recovery, and a single `ZvPlayerState` for the UI.
- `SourceRouter` is the only place a source type maps to an engine. Supply your
  own builders to add engines (for example DRM).
- `EngineCapabilities` states what the active engine can do; the UI reads it
  instead of branching on source type.
- `PlaybackProgressStore` persists resume positions (in memory by default).

### Theming

`ZvPlayer(theme: ZvPlayerTheme(accent: ...))` sets the accent and scrims. The
default palette is black, crimson `#DC143C` and white, with bundled Poppins.

## Platform setup

**Android**: `minSdkVersion 24`; builds with Android Gradle Plugin 8 and 9. Add
the INTERNET permission for network sources. For picture-in-picture, forward the Activity callback:

```kotlin
override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean) {
    super.onPictureInPictureModeChanged(isInPictureInPictureMode)
    ZvPlayerPlugin.notifyPictureInPictureModeChanged(isInPictureInPictureMode)
}
```

**iOS**: iOS 13+. Brightness control is unavailable on the Simulator.

## Status

- DRM: `DrmConfig` is an extension point; no DRM scheme is implemented yet, and
  a DRM source reports an error rather than playing unprotected.
- Casting: the UI shows Cast only when the host supplies an `onCast` handler.

## License

MIT. See [LICENSE](LICENSE).
