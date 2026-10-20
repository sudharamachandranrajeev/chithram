import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Placeholder desktop player (libmpv through media_kit). No media is opened;
/// it only exists so the release pipeline packages and exercises libmpv.
class PlayerTestPage extends StatefulWidget {
  const PlayerTestPage({super.key});

  @override
  State<PlayerTestPage> createState() => _PlayerTestPageState();
}

class _PlayerTestPageState extends State<PlayerTestPage> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Player test')),
      body: Video(controller: _controller),
    );
  }
}
