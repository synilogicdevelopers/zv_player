/// ZV Player: one cinematic player UI for every source.
///
/// Progressive files, HLS, DASH and local files play natively (AndroidX Media3
/// on Android, AVPlayer on iOS). YouTube URLs play through YouTube's official
/// IFrame Player API, hidden beneath the same ZV Player controls. The host app
/// hands over a [ZvMediaSource]; routing, engines and chrome are the package's.
///
/// ```dart
/// final controller = ZvPlayerController();
/// controller.open(ZvMediaSource.detect(uri: 'https://example.com/movie.m3u8'));
/// ZvPlayer(controller: controller, title: 'Movie');
/// ```
library;

export 'src/capabilities/device_capabilities.dart';
export 'src/capabilities/engine_capabilities.dart';
export 'src/controller/zv_native_controller.dart'
    show ZvNativeController, UpNextItem, kPlaybackSpeeds;
export 'src/controller/zv_player_controller.dart'
    show ZvPlayerController, ZvPlayerLog;
export 'src/engine/native_media_engine.dart';
export 'src/engine/playback_engine.dart';
export 'src/engine/youtube_engine.dart' show YouTubeEngine;
export 'src/models/player_event.dart';
export 'src/models/player_tracks.dart';
export 'src/platform/zv_platform.dart'
    show ZvPlatform, MethodChannelZvPlatform, mapNativeError;
export 'src/platform/zv_native_view.dart' show ZvNativeView;
export 'src/services/cast_delegate.dart';
export 'src/services/offline_source_resolver.dart';
export 'src/services/playback_progress_store.dart';
export 'src/services/player_command_sink.dart';
export 'src/source/source_router.dart';
export 'src/source/youtube_video_id.dart' show youTubeVideoId;
export 'src/source/zv_media_source.dart';
export 'src/state/zv_player_state.dart';
export 'src/ui/fullscreen_presenter.dart'
    show AppOrientationBaseline, FullscreenPresenter;
export 'src/ui/zv_player_theme.dart'
    show ZvPlayerTheme, ZvPlayerThemeScope, formatPlayerDuration;
export 'src/ui/zv_player_view.dart' show ZvPlayer;
export 'src/widgets/zv_settings_sheet.dart' show ZvSettingsSheet, SettingsPanel;
