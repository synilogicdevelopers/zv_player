import 'package:zv_player/zv_player.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mapNativeError', () {
    test('classifies Media3 network codes as recoverable', () {
      final PlayerErrorInfo info = mapNativeError(
        code: 'ERROR_CODE_IO_NETWORK_CONNECTION_FAILED',
        message: 'Unable to connect',
      );
      expect(info.type, PlayerErrorType.network);
      expect(info.isRecoverable, isTrue);
    });

    test('classifies timeouts as recoverable', () {
      expect(
        mapNativeError(code: 'ERROR_CODE_TIMEOUT', message: null).type,
        PlayerErrorType.bufferingTimeout,
      );
    });

    test('classifies decoder failures as unrecoverable', () {
      final PlayerErrorInfo info = mapNativeError(
        code: 'ERROR_CODE_DECODING_FAILED',
        message: 'decoder init failed',
      );
      expect(info.type, PlayerErrorType.decoder);
      expect(info.isRecoverable, isFalse);
    });

    test('classifies DRM failures and never suggests retrying them', () {
      final PlayerErrorInfo info = mapNativeError(
        code: 'ERROR_CODE_DRM_LICENSE_ACQUISITION_FAILED',
        message: 'licence request rejected',
      );
      expect(info.type, PlayerErrorType.drm);
      expect(info.isRecoverable, isFalse);
    });

    test('classifies unsupported containers', () {
      expect(
        mapNativeError(code: 'unsupported_format', message: null).type,
        PlayerErrorType.unsupportedFormat,
      );
    });

    test('keeps technical detail out of the viewer-facing message', () {
      final PlayerErrorInfo info = mapNativeError(
        code: 'ERROR_CODE_IO_BAD_HTTP_STATUS',
        message: 'Response code: 403',
        detail: 'com.google.android.exoplayer2.upstream.HttpDataSource...',
      );
      expect(info.message, isNot(contains('403')));
      expect(info.message, isNot(contains('com.google')));
      expect(info.technicalDetail, contains('com.google'));
    });

    test('falls back to a recoverable unknown error', () {
      final PlayerErrorInfo info =
          mapNativeError(code: 'something_new', message: 'odd failure');
      expect(info.type, PlayerErrorType.unknown);
      expect(info.isRecoverable, isTrue);
      expect(info.message, isNotEmpty);
    });
  });
}
