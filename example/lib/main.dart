import 'package:flutter/material.dart';
import 'package:zv_player/zv_player.dart';

void main() => runApp(const ZvPlayerExampleApp());

/// Sample sources, one per kind of media ZV Player routes.
const List<({String title, String uri})> samples =
    <({String title, String uri})>[
      (title: 'YouTube', uri: 'https://www.youtube.com/watch?v=aqz-KE-bpKQ'),
      (title: 'MP4', uri: 'https://media.w3.org/2010/05/sintel/trailer.mp4'),
      (title: 'HLS', uri: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8'),
      (
        title: 'DASH',
        uri: 'https://dash.akamaized.net/akamai/bbb_30fps/bbb_30fps.mpd',
      ),
      (title: 'Invalid URL', uri: 'not a video'),
    ];

class ZvPlayerExampleApp extends StatelessWidget {
  const ZvPlayerExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZV Player',
      theme: ThemeData.dark(useMaterial3: true),
      home: const SamplesPage(),
    );
  }
}

class SamplesPage extends StatelessWidget {
  const SamplesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ZV Player')),
      body: ListView(
        children: <Widget>[
          for (final sample in samples)
            ListTile(
              title: Text(sample.title),
              subtitle: Text(sample.uri, maxLines: 1),
              trailing: const Icon(Icons.play_arrow_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PlayerPage(
                    source: ZvMediaSource.detect(
                      uri: sample.uri,
                      title: sample.title,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A full-screen player route: open the source, show [ZvPlayer], dispose.
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.source});

  final ZvMediaSource source;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  // The standard router: native engine for media, YouTube engine for YouTube.
  final ZvPlayerController controller = ZvPlayerController();

  @override
  void initState() {
    super.initState();
    controller.open(widget.source);
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
        title: widget.source.title,
        onBack: () => Navigator.of(context).pop(),
      ),
    );
  }
}
