// lib/pages/fullscreen_player_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import '../services/api_service.dart';

class FullscreenPage extends StatefulWidget {
  final Map<String, String> videoInfo;
  const FullscreenPage({Key? key, required this.videoInfo}) : super(key: key);

  @override
  _FullscreenPageState createState() => _FullscreenPageState();
}

class _FullscreenPageState extends State<FullscreenPage> {
  late VlcPlayerController _vlcController;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();

    // 横屏沉浸式
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    final folder = widget.videoInfo['folder']!;
    final path = widget.videoInfo['path']!;
    final url = ApiService.getVideoUrl(folder, path);

    _vlcController = VlcPlayerController.network(
      url,
      hwAcc: HwAcc.auto,
      autoPlay: true,
      options: VlcPlayerOptions(),
    );

    // 获取上次播放进度，并在 seekTo 后 setState
    ApiService.getPosition(folder, path).then((dynamic result) {
      final int posMs = result is int ? result : 0; // 强制类型安全
      if (posMs > 0) {
        _vlcController.seekTo(Duration(milliseconds: posMs));
      }
      setState(() {
        _initialized = true;
      });
    });

  }

  @override
  void dispose() {
    // 恢复竖屏
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    final folder = widget.videoInfo['folder']!;
    final path = widget.videoInfo['path']!;
    _vlcController.getPosition().then((duration) {
      final posMs = duration?.inMilliseconds ?? 0;
      ApiService.reportPosition(folder, path, posMs);
    }).catchError((_) {});
    _vlcController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: _initialized
            ? VlcPlayer(
          controller: _vlcController,
          aspectRatio: MediaQuery.of(context).size.aspectRatio,
        )
            : const CircularProgressIndicator(),
      ),
    );
  }
}
