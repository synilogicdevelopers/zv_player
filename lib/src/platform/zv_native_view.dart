import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// The native video surface.
///
/// This widget renders nothing itself - it hosts the platform's own video view
/// (a Media3 `PlayerView` on Android, an `AVPlayerLayer` on iOS) and attaches
/// it to an already-running player identified by [playerId].
///
/// Android uses hybrid composition, which keeps the video on a real
/// `SurfaceView`. That is what preserves hardware decoding, HDR output and
/// secure-surface support; a texture copy would quietly cost all three.
class ZvNativeView extends StatelessWidget {
  const ZvNativeView({
    super.key,
    required this.playerId,
    this.alignment = Alignment.center,
  });

  static const String viewType = 'zv_player/view';

  final int playerId;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> creationParams = <String, dynamic>{
      'playerId': playerId,
    };

    if (defaultTargetPlatform == TargetPlatform.android) {
      return PlatformViewLink(
        viewType: viewType,
        surfaceFactory: (BuildContext context, PlatformViewController control) {
          return AndroidViewSurface(
            controller: control as AndroidViewController,
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
            hitTestBehavior: PlatformViewHitTestBehavior.transparent,
          );
        },
        onCreatePlatformView: (PlatformViewCreationParams params) {
          return PlatformViewsService.initExpensiveAndroidView(
            id: params.id,
            viewType: viewType,
            layoutDirection: TextDirection.ltr,
            creationParams: creationParams,
            creationParamsCodec: const StandardMessageCodec(),
            onFocus: () => params.onFocusChanged(true),
          )
            ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
            ..create();
        },
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: viewType,
        layoutDirection: TextDirection.ltr,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
      );
    }

    // Other platforms are not supported yet. Say so rather than showing a
    // broken surface.
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: Text(
          'Video playback is not supported on this platform',
          style: TextStyle(color: Colors.white70, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
