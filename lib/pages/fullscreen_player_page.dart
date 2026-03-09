// lib/pages/fullscreen_player_page.dart
// 【最终完美修复版】强制横屏全屏 + 正确比例 + 滑动快进 + Tooltip + clamp 红线已解决

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/api_service.dart';

class FullscreenPlayerPage extends StatefulWidget {
  final Map<String, dynamic> videoInfo;

  const FullscreenPlayerPage({Key? key, required this.videoInfo}) : super(key: key);

  @override
  State<FullscreenPlayerPage> createState() => _FullscreenPlayerPageState();
}

class _FullscreenPlayerPageState extends State<FullscreenPlayerPage> {
  late final Player player;
  late final VideoController controller;

  bool _initialized = false;
  bool _hasError = false;
  String _errorMessage = '';

  // 滑动快进
  Timer? _seekDebounceTimer;
  double _seekOffset = 0;
  OverlayEntry? _seekTooltipEntry;

  @override
  void initState() {
    super.initState();
    player = Player();
    controller = VideoController(player);

    _forceLandscape();   // 首次强制横屏
    _loadVideo();
  }

  // 新增：每次依赖变化都重新强制横屏（解决点击全屏不横屏的核心问题）
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _forceLandscape();
  }

  void _forceLandscape() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _loadVideo() async {
    final String folder = widget.videoInfo['folder'] ?? '';
    final String path = widget.videoInfo['path'] ?? '';

    if (folder.isEmpty || path.isEmpty) {
      _showError('视频信息错误');
      return;
    }

    final String url = ApiService.getVideoUrl(folder, path);

    try {
      await player.open(Media(url));

      final int posMs = (await ApiService.getPosition(folder, path)) ?? 0;
      if (posMs > 0) await player.seek(Duration(milliseconds: posMs));

      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      _showError(e.toString());
    }

    player.stream.error.listen((error) => _showError(error));
  }

  void _showError(String msg) {
    if (mounted) setState(() {
      _hasError = true;
      _errorMessage = msg;
    });
  }

  Future<void> _retry() async {
    setState(() { _hasError = false; _initialized = false; });
    await _loadVideo();
  }

  // ================== 滑动快进（带 Tooltip）==================
  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    _seekOffset += details.delta.dx * 0.8;
    _seekDebounceTimer?.cancel();
    _seekDebounceTimer = Timer(const Duration(milliseconds: 80), () {
      final target = player.state.position + Duration(milliseconds: _seekOffset.round());
      // 【已修复 clamp 红线】使用手动安全 clamp
      final clamped = Duration(
        milliseconds: target.inMilliseconds.clamp(0, player.state.duration.inMilliseconds),
      );
      player.seek(clamped);
      _showSeekTooltip(_seekOffset.round());
    });
  }

  void _onHorizontalDragEnd(DragEndDetails _) {
    _seekDebounceTimer?.cancel();
    _removeSeekTooltip();
    player.play();
    _seekOffset = 0;
  }

  void _showSeekTooltip(int delta) {
    _removeSeekTooltip();
    _seekTooltipEntry = OverlayEntry(
      builder: (_) => Positioned(
        top: MediaQuery.of(context).size.height * 0.35,
        left: 0,
        right: 0,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(30)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(delta >= 0 ? Icons.fast_forward : Icons.fast_rewind, color: Colors.white),
                const SizedBox(width: 12),
                Text(delta >= 0 ? '+$delta 秒' : '$delta 秒',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_seekTooltipEntry!);
  }

  void _removeSeekTooltip() {
    _seekTooltipEntry?.remove();
    _seekTooltipEntry = null;
  }

  @override
  void dispose() {
    final String folder = widget.videoInfo['folder'] ?? '';
    final String path = widget.videoInfo['path'] ?? '';
    if (folder.isNotEmpty && path.isNotEmpty) {
      ApiService.reportPosition(folder, path, player.state.position.inMilliseconds);
    }

    _seekDebounceTimer?.cancel();
    _removeSeekTooltip();
    player.dispose();

    // 恢复竖屏
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: _onHorizontalDragUpdate,
        onHorizontalDragEnd: _onHorizontalDragEnd,
        child: Stack(
          children: [
            // 真正全屏 + 正确比例（SizedBox.expand + BoxFit.contain）
            SizedBox.expand(
              child: _hasError
                  ? _buildErrorWidget()
                  : _initialized
                  ? Video(
                controller: controller,
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
              )
                  : const Center(child: CircularProgressIndicator(color: Colors.white)),
            ),

            if (_hasError) Positioned.fill(child: _buildErrorWidget()),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.white70, size: 60),
          const SizedBox(height: 20),
          Text('播放失败\n$_errorMessage', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 30),
          ElevatedButton.icon(onPressed: _retry, icon: const Icon(Icons.refresh), label: const Text('重试')),
        ],
      ),
    );
  }
}