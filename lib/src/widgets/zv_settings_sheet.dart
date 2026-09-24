import 'package:flutter/material.dart';

import '../services/player_command_sink.dart';
import '../models/player_tracks.dart';
import '../state/zv_player_state.dart';
import '../capabilities/engine_capabilities.dart';
import '../ui/zv_player_theme.dart';

/// Which secondary panel is open, or null for the root list.
enum SettingsPanel {
  quality,
  speed,
  captions,
  audioTrack,
  fit,
  display,
  volume
}

/// Player settings: a short root list, with sub-options on a second panel.
///
/// The root never grows with the media. Each supported setting is one row -
/// icon, title, current value, chevron - so the whole control surface is
/// readable at a glance; choosing a value happens on a panel that replaces the
/// root in place rather than extending it downwards.
///
/// Two rules decide what appears, unchanged from before:
///
/// 1. The engine must be able to change it ([EngineCapabilities]).
/// 2. There must be something to choose ([PlayerTracks]).
///
/// A setting failing either test is not rendered - never a "Quality" row above
/// an empty list. If nothing qualifies at all, the sheet says so rather than
/// opening blank.
class ZvSettingsSheet extends StatefulWidget {
  const ZvSettingsSheet({
    super.key,
    required this.sink,
    required this.state,
    required this.capabilities,
    this.onSetBrightness,
    this.brightness,
    this.initialPanel,
    this.onSetVideoFit,
    this.onClose,
  });

  final PlayerCommandSink sink;
  final ZvPlayerState state;

  /// Rows appear only for things the active engine can actually change.
  final EngineCapabilities capabilities;

  /// Supplied only when the platform really can change brightness.
  final ValueChanged<double>? onSetBrightness;
  final double? brightness;

  final VoidCallback? onClose;

  /// An optional contextual panel to open directly.
  final SettingsPanel? initialPanel;

  /// Supplied only when the engine can crop to fill without distorting.
  final ValueChanged<VideoFitMode>? onSetVideoFit;

  static Future<void> show(
    BuildContext context,
    PlayerCommandSink sink,
    ZvPlayerState state,
    EngineCapabilities capabilities, {
    ValueChanged<double>? onSetBrightness,
    double? brightness,
    SettingsPanel? initialPanel,
    ValueChanged<VideoFitMode>? onSetVideoFit,
  }) {
    final ZvPlayerTheme theme = ZvPlayerTheme.of(context);
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (BuildContext sheetContext) => ZvPlayerThemeScope(
        theme: theme,
        child: Dialog(
          alignment: Alignment.centerRight,
          backgroundColor: theme.sheetBackground,
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
              width: 340,
              child: ZvSettingsSheet(
                sink: sink,
                state: state,
                capabilities: capabilities,
                onSetBrightness: onSetBrightness,
                brightness: brightness,
                initialPanel: initialPanel,
                onSetVideoFit: onSetVideoFit,
              )),
        ),
      ),
    );
  }

  @override
  State<ZvSettingsSheet> createState() => _ZvSettingsSheetState();
}

class _ZvSettingsSheetState extends State<ZvSettingsSheet> {
  late SettingsPanel? _panel = widget.initialPanel;

  /// Mirrors of the values this sheet can change, so a choice is reflected
  /// immediately. The command still goes to the engine; this only keeps the
  /// row from showing a stale value while the engine catches up.
  late double _volume = widget.state.volume;
  late bool _muted = widget.state.isMuted;
  late double _speed = widget.state.speed;
  late VideoFitMode _fit = widget.state.videoFit;
  late double? _brightness = widget.brightness;
  late VideoQualityTrack? _quality = widget.state.tracks.selectedVideo;
  late AudioTrackOption? _audio = widget.state.tracks.selectedAudio;
  late SubtitleTrackOption? _subtitle = widget.state.tracks.selectedSubtitle;

  ZvPlayerState get _state => widget.state;

  EngineCapabilities get _capabilities => widget.capabilities;

  bool get _showQuality =>
      _capabilities.canSelectQuality && _state.tracks.hasQualityChoice;

  bool get _showAudioTracks =>
      _capabilities.canSelectAudioTrack && _state.tracks.hasAudioChoice;

  bool get _showSubtitles =>
      _capabilities.canSelectSubtitle && _state.tracks.hasSubtitles;

  bool get _showSpeed =>
      _capabilities.canSetSpeed && _capabilities.speeds.length > 1;

  bool get _showVolume => _capabilities.canSetVolume;

  bool get _showMute => _capabilities.canMute;

  bool get _showBrightness =>
      widget.onSetBrightness != null && _brightness != null;

  bool get _showVideoFit => widget.onSetVideoFit != null;

  /// Brightness is available only after the platform reports support.
  bool get _showDisplay => _showBrightness;

  bool get _hasPlayback =>
      _showQuality || _showSpeed || _showSubtitles || _showAudioTracks;

  bool get _hasVideo => _showVideoFit || _showDisplay;

  bool get _hasAudio => _showVolume || _showMute;

  bool get _hasAnything => _hasPlayback || _hasVideo || _hasAudio;

  void _open(SettingsPanel panel) => setState(() => _panel = panel);

  void _back() => setState(() => _panel = null);

  @override
  Widget build(BuildContext context) {
    final ZvPlayerTheme theme = ZvPlayerTheme.of(context);

    // Poppins here rather than at the call site: a Dialog resets the default
    // text style to the host theme's.
    return DefaultTextStyle.merge(
      style: ZvPlayerTheme.textStyle,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.78,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: 10),
              _Grabber(theme: theme),
              _Header(
                theme: theme,
                title: _panel == null ? 'More' : _panelTitle(_panel!),
                onBack: _panel == null ? null : _back,
                onClose: widget.onClose,
              ),
              Flexible(
                // Height changes between root and panel are animated so the sheet
                // resizes rather than jumping.
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                    child: _panel == null ? _buildRoot(theme) : _buildPanel(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _panelTitle(SettingsPanel panel) {
    switch (panel) {
      case SettingsPanel.quality:
        return 'Quality';
      case SettingsPanel.speed:
        return 'Playback speed';
      case SettingsPanel.captions:
        return 'Captions';
      case SettingsPanel.audioTrack:
        return 'Audio';
      case SettingsPanel.fit:
        return 'Video fit';
      case SettingsPanel.display:
        return 'Brightness';
      case SettingsPanel.volume:
        return 'Volume';
    }
  }

  // --- Root -----------------------------------------------------------------

  Widget _buildRoot(ZvPlayerTheme theme) {
    if (!_hasAnything) return _EmptyState(theme: theme);

    return Column(
      key: const ValueKey<String>('settings-root'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (_hasPlayback) ...<Widget>[
          _GroupLabel(theme: theme, label: 'Playback'),
          if (_showQuality)
            _SettingRow(
              icon: Icons.high_quality_outlined,
              title: 'Quality',
              value: _quality?.label ?? 'Auto',
              onTap: () => _open(SettingsPanel.quality),
            ),
          if (_showSpeed)
            _SettingRow(
              icon: Icons.speed_rounded,
              title: 'Speed',
              value: _speedLabel(_speed),
              onTap: () => _open(SettingsPanel.speed),
            ),
          if (_showSubtitles)
            _SettingRow(
              icon: Icons.closed_caption_off_rounded,
              title: 'Captions',
              value: _subtitle?.label ?? 'Off',
              onTap: () => _open(SettingsPanel.captions),
            ),
          if (_showAudioTracks)
            _SettingRow(
              icon: Icons.graphic_eq_rounded,
              title: 'Audio',
              value: _audio?.label ?? 'Original',
              onTap: () => _open(SettingsPanel.audioTrack),
            ),
        ],
        if (_hasVideo) ...<Widget>[
          _GroupLabel(theme: theme, label: 'Video'),
          if (_showVideoFit)
            _SettingRow(
              icon: Icons.aspect_ratio_rounded,
              title: 'Fit',
              value: _fitLabel(_fit),
              onTap: () => _open(SettingsPanel.fit),
            ),
          if (_showDisplay)
            _SettingRow(
              icon: Icons.tv_rounded,
              title: 'Brightness',
              value: '${((_brightness ?? 0) * 100).round()}%',
              onTap: () => _open(SettingsPanel.display),
            ),
        ],
        if (_hasAudio)
          _SettingRow(
              icon: Icons.volume_up_rounded,
              title: 'Volume',
              value: _muted ? 'Muted' : '${(_volume * 100).round()}%',
              onTap: () => _open(SettingsPanel.volume)),
      ],
    );
  }

  // --- Secondary panels -----------------------------------------------------

  Widget _buildPanel() {
    switch (_panel!) {
      case SettingsPanel.volume:
        final ZvPlayerTheme theme = ZvPlayerTheme.of(context);
        return _panelBody(key: 'panel-volume', children: <Widget>[
          if (_showVolume)
            _SliderRow(
              theme: theme,
              icon: _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              label: 'Volume',
              value: _muted ? 0 : _volume,
              onChanged: (double value) {
                setState(() {
                  _volume = value;
                  // Moving the slider off zero is an unmute; it must never
                  // resume playback, and setVolume/setMuted never do.
                  if (value > 0 && _muted) _muted = false;
                });
                if (value > 0 && widget.capabilities.canMute) {
                  widget.sink.setMuted(false);
                }
                widget.sink.setVolume(value);
              },
            ),
          if (_showMute)
            _ToggleRow(
              theme: theme,
              icon: _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              title: 'Mute',
              value: _muted,
              onChanged: (bool muted) {
                setState(() => _muted = muted);
                // Mute is an audio command only. Playback state is untouched,
                // so unmuting while paused leaves the video paused.
                widget.sink.setMuted(muted);
              },
            ),
        ]);

      case SettingsPanel.quality:
        return _panelBody(
          key: 'panel-quality',
          caption: _state.source?.isAdaptive == true
              ? 'Adapts automatically to your connection'
              : 'Switching reloads the video at this position',
          children: _state.tracks.video
              .map(
                (VideoQualityTrack track) => _OptionTile(
                  // Two renditions can carry the same label; the set decides
                  // what distinguishes them, from real metadata only.
                  label: _state.tracks.videoLabelFor(track),
                  trailingNote: track.isAuto && track.isSelected
                      ? _autoDetail(_state)
                      : null,
                  // Identity is the track id: matching on label would mark
                  // every same-resolution rendition as selected at once.
                  selected: _quality == null
                      ? track.isSelected
                      : track.id == _quality!.id,
                  onTap: () {
                    setState(() => _quality = track);
                    widget.sink.selectQuality(track);
                    _back();
                  },
                ),
              )
              .toList(),
        );

      case SettingsPanel.speed:
        return _panelBody(
          key: 'panel-speed',
          // The engine's own list, not a hard-coded ladder: an embed accepts a
          // different set from the native pipeline.
          children: _capabilities.speeds
              .map(
                (double speed) => _OptionTile(
                  label: _speedLabel(speed),
                  selected: (_speed - speed).abs() < 0.01,
                  onTap: () {
                    setState(() => _speed = speed);
                    widget.sink.setSpeed(speed);
                    _back();
                  },
                ),
              )
              .toList(),
        );

      case SettingsPanel.captions:
        return _panelBody(
          key: 'panel-captions',
          children: <Widget>[
            _OptionTile(
              label: 'Off',
              selected: _subtitle == null,
              onTap: () {
                setState(() => _subtitle = null);
                widget.sink.selectSubtitle(null);
                _back();
              },
            ),
            ..._state.tracks.subtitles.map(
              (SubtitleTrackOption track) => _OptionTile(
                label: track.label,
                trailingNote: PlayerTracks.subtitleNoteFor(track),
                selected: _subtitle?.id == track.id,
                onTap: () {
                  setState(() => _subtitle = track);
                  widget.sink.selectSubtitle(track);
                  _back();
                },
              ),
            ),
          ],
        );

      case SettingsPanel.audioTrack:
        return _panelBody(
          key: 'panel-audio-track',
          children: _state.tracks.audio
              .map(
                (AudioTrackOption track) => _OptionTile(
                  label: track.label,
                  // Dolby is surfaced only when the track's own codec says so.
                  trailingNote: track.isDolby ? 'Dolby' : null,
                  selected: _audio == null
                      ? track.isSelected
                      : track.id == _audio!.id,
                  onTap: () {
                    setState(() => _audio = track);
                    widget.sink.selectAudioTrack(track);
                    _back();
                  },
                ),
              )
              .toList(),
        );

      case SettingsPanel.fit:
        return _panelBody(
          key: 'panel-fit',
          caption: 'Fill crops the edges; it never stretches the picture',
          children: VideoFitMode.values
              .map(
                (VideoFitMode fit) => _OptionTile(
                  label: _fitLabel(fit),
                  selected: _fit == fit,
                  onTap: () {
                    setState(() => _fit = fit);
                    widget.onSetVideoFit!(fit);
                    _back();
                  },
                ),
              )
              .toList(),
        );

      case SettingsPanel.display:
        final ZvPlayerTheme theme = ZvPlayerTheme.of(context);
        return _panelBody(
          key: 'panel-display',
          children: <Widget>[
            if (_showBrightness)
              _SliderRow(
                theme: theme,
                icon: Icons.brightness_6_rounded,
                label: 'Brightness',
                value: _brightness!,
                onChanged: (double value) {
                  setState(() => _brightness = value);
                  widget.onSetBrightness!(value);
                },
              ),
          ],
        );
    }
  }

  Widget _panelBody({
    required String key,
    required List<Widget> children,
    String? caption,
  }) {
    final ZvPlayerTheme theme = ZvPlayerTheme.of(context);
    return Column(
      key: ValueKey<String>(key),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (caption != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Text(
              caption,
              style: TextStyle(color: theme.onSurfaceMuted, fontSize: 12),
            ),
          ),
        ...children,
      ],
    );
  }

  /// Shows what Auto actually settled on, when the player has told us.
  String? _autoDetail(ZvPlayerState state) {
    final int? height = state.videoHeight;
    if (height == null || height <= 0) return null;
    final QualityRung? rung = QualityRung.nearest(height);
    return rung == null ? null : 'Now ${rung.label}';
  }

  static String _speedLabel(double speed) =>
      (speed - 1.0).abs() < 0.01 ? 'Normal' : '${_trim(speed)}x';

  static String _fitLabel(VideoFitMode fit) =>
      fit == VideoFitMode.fit ? 'Fit' : 'Fill';

  static String _trim(double value) {
    final String text = value.toString();
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber({required this.theme});

  final ZvPlayerTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 3,
      decoration: BoxDecoration(
        color: theme.onSurfaceMuted.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

/// Title row. On a secondary panel the title is preceded by a back affordance,
/// so the panel reads as a step rather than a separate sheet.
class _Header extends StatelessWidget {
  const _Header(
      {required this.theme, required this.title, this.onBack, this.onClose});

  final ZvPlayerTheme theme;
  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 44,
            child: onBack == null
                ? null
                : IconButton(
                    onPressed: onBack,
                    tooltip: 'Back',
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 44, minHeight: 44),
                    color: theme.onSurface,
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
          ),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
          SizedBox(
              width: 44,
              child: onClose == null
                  ? null
                  : IconButton(
                      tooltip: 'Close player options',
                      onPressed: onClose,
                      icon: const Icon(Icons.close, size: 20),
                      color: theme.onSurface)),
        ],
      ),
    );
  }
}

/// One root row: icon, title, current value, chevron.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ZvPlayerTheme theme = ZvPlayerTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 19, color: theme.onSurfaceMuted),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(color: theme.onSurface, fontSize: 14),
              ),
            ),
            Text(
              value,
              style: TextStyle(color: theme.onSurfaceMuted, fontSize: 13.5),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: theme.onSurfaceMuted,
            ),
          ],
        ),
      ),
    );
  }
}

/// A root row whose value is a switch rather than a panel.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.theme,
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final ZvPlayerTheme theme;
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 19, color: theme.onSurfaceMuted),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: TextStyle(color: theme.onSurface, fontSize: 14),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: theme.accent,
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.theme,
    required this.label,
    required this.value,
    required this.icon,
    required this.onChanged,
  });

  final ZvPlayerTheme theme;
  final String label;
  final double value;
  final IconData icon;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: <Widget>[
          Icon(icon, color: theme.onSurfaceMuted, size: 19),
          const SizedBox(width: 14),
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(color: theme.onSurface, fontSize: 14),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                activeTrackColor: theme.accent,
                inactiveTrackColor: theme.trackInactive,
                thumbColor: theme.accent,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: value.clamp(0.0, 1.0),
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              '${(value.clamp(0.0, 1.0) * 100).round()}%',
              textAlign: TextAlign.end,
              style: TextStyle(color: theme.onSurfaceMuted, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown instead of a blank sheet when the current engine exposes nothing.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.theme});

  final ZvPlayerTheme theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text(
          'No settings are available for this video',
          style: TextStyle(color: theme.onSurfaceMuted, fontSize: 13),
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.theme, required this.label});

  final ZvPlayerTheme theme;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 2),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: theme.onSurfaceMuted,
          fontSize: 10.5,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailingNote,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? trailingNote;

  @override
  Widget build(BuildContext context) {
    final ZvPlayerTheme theme = ZvPlayerTheme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? theme.onSurface : theme.onSurfaceMuted,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (trailingNote != null)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Text(
                  trailingNote!,
                  style: TextStyle(color: theme.onSurfaceMuted, fontSize: 12),
                ),
              ),
            if (selected)
              Icon(Icons.check_rounded, color: theme.accent, size: 18),
          ],
        ),
      ),
    );
  }
}
