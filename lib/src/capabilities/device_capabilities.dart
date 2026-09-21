import 'package:flutter/foundation.dart';

/// Dynamic-range formats a device may support.
enum DynamicRangeFormat { sdr, hdr10, hdr10Plus, hlg, dolbyVision }

/// What this specific device can actually do.
///
/// Every field is read from the platform. Nothing is assumed from the brand or
/// the OS version, so no phone is told it supports 4K or Dolby Vision because
/// of what it happens to be.
@immutable
class DeviceCapabilities {
  const DeviceCapabilities({
    this.maxSupportedHeight,
    this.dynamicRange = const <DynamicRangeFormat>{DynamicRangeFormat.sdr},
    this.videoCodecs = const <String>{},
    this.audioCodecs = const <String>{},
    this.supportsPip = false,
    this.supportsHdrPlayback = false,
    this.supportsDolbyAudio = false,
    this.supportsWidevine = false,
    this.supportsFairPlay = false,
    this.supportsOfflineDrm = false,
    this.isLowMemoryDevice = false,
    this.displayHeight,
    this.probed = false,
  });

  /// Highest decodable video height reported by the platform decoders.
  final int? maxSupportedHeight;
  final Set<DynamicRangeFormat> dynamicRange;
  final Set<String> videoCodecs;
  final Set<String> audioCodecs;
  final bool supportsPip;
  final bool supportsHdrPlayback;
  final bool supportsDolbyAudio;
  final bool supportsWidevine;
  final bool supportsFairPlay;

  /// Persistable DRM licences. False everywhere today - no DRM is wired up.
  final bool supportsOfflineDrm;
  final bool isLowMemoryDevice;

  /// Display height in pixels; a 1080p panel makes 4K decoding pointless.
  final int? displayHeight;

  /// False until the platform has answered, so callers can tell "unknown"
  /// from "unsupported".
  final bool probed;

  bool get supportsDolbyVision =>
      dynamicRange.contains(DynamicRangeFormat.dolbyVision);

  bool get supportsHdr10 => dynamicRange.contains(DynamicRangeFormat.hdr10);

  /// The highest rendition worth requesting: never beyond what the decoder
  /// handles, and never far beyond what the screen can show.
  int? get practicalMaxHeight {
    final int? decoder = maxSupportedHeight;
    final int? display = displayHeight;
    if (decoder == null) return display;
    if (display == null) return decoder;
    return decoder < display ? decoder : display;
  }

  static DeviceCapabilities fromMap(Map<dynamic, dynamic> map) {
    final Set<DynamicRangeFormat> ranges = <DynamicRangeFormat>{
      DynamicRangeFormat.sdr,
    };
    final Object? rawRanges = map['dynamicRange'];
    if (rawRanges is List) {
      for (final Object? entry in rawRanges) {
        switch ('$entry') {
          case 'hdr10':
            ranges.add(DynamicRangeFormat.hdr10);
            break;
          case 'hdr10Plus':
            ranges.add(DynamicRangeFormat.hdr10Plus);
            break;
          case 'hlg':
            ranges.add(DynamicRangeFormat.hlg);
            break;
          case 'dolbyVision':
            ranges.add(DynamicRangeFormat.dolbyVision);
            break;
        }
      }
    }

    return DeviceCapabilities(
      maxSupportedHeight: _asInt(map['maxSupportedHeight']),
      dynamicRange: ranges,
      videoCodecs: _asStringSet(map['videoCodecs']),
      audioCodecs: _asStringSet(map['audioCodecs']),
      supportsPip: map['supportsPip'] == true,
      supportsHdrPlayback: map['supportsHdrPlayback'] == true,
      supportsDolbyAudio: map['supportsDolbyAudio'] == true,
      supportsWidevine: map['supportsWidevine'] == true,
      supportsFairPlay: map['supportsFairPlay'] == true,
      supportsOfflineDrm: map['supportsOfflineDrm'] == true,
      isLowMemoryDevice: map['isLowMemoryDevice'] == true,
      displayHeight: _asInt(map['displayHeight']),
      probed: true,
    );
  }

  static Set<String> _asStringSet(Object? value) {
    if (value is List) {
      return value.map((Object? e) => '$e'.toLowerCase()).toSet();
    }
    return <String>{};
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }
}
