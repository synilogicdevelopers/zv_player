import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../state/zv_player_state.dart';
import '../ui/zv_player_theme.dart';

/// Failure state shown over the video surface.
///
/// The viewer sees the plain-language message; the native detail goes to logs
/// and, in debug builds only, behind a disclosure. Stack traces never surface.
class ZvErrorView extends StatelessWidget {
  const ZvErrorView({
    super.key,
    required this.error,
    this.onRetry,
    this.onBack,
  });

  final PlayerErrorInfo error;

  /// Null hides the retry action, for failures a retry cannot fix.
  final VoidCallback? onRetry;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final ZvPlayerTheme theme = ZvPlayerTheme.of(context);

    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.86),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(_iconFor(error.type), color: theme.onSurface, size: 34),
              const SizedBox(height: 14),
              Text(
                error.message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.onSurface,
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
              if (error.retryAttempt > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Tried ${error.retryAttempt} '
                    '${error.retryAttempt == 1 ? 'time' : 'times'} already',
                    style: TextStyle(
                      color: theme.onSurfaceMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (onBack != null) ...<Widget>[
                    TextButton(
                      onPressed: onBack,
                      style: TextButton.styleFrom(
                        foregroundColor: theme.onSurfaceMuted,
                      ),
                      child: const Text('Go back'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (onRetry != null)
                    FilledButton.icon(
                      onPressed: onRetry,
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Try again'),
                    ),
                ],
              ),
              if (kDebugMode && error.technicalDetail != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    '[debug] ${error.code}: ${error.technicalDetail}',
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.onSurfaceMuted,
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconFor(PlayerErrorType type) {
    switch (type) {
      case PlayerErrorType.network:
      case PlayerErrorType.bufferingTimeout:
        return Icons.wifi_off_rounded;
      case PlayerErrorType.drm:
        return Icons.lock_outline_rounded;
      case PlayerErrorType.unsupportedFormat:
      case PlayerErrorType.decoder:
        return Icons.videocam_off_outlined;
      case PlayerErrorType.casting:
        return Icons.cast_connected_rounded;
      default:
        return Icons.error_outline_rounded;
    }
  }
}
