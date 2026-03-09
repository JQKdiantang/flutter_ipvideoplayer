// lib/pages/video_player_page.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:media_cast_dlna/media_cast_dlna.dart';

import '../services/api_service.dart';
import '../models/video_item.dart';
import 'settings_page.dart';

enum SeekMode { proportional, fixed }

const int SEEK_STEP_SECONDS = 10;
const double LONG_PRESS_RATE = 2.5;
const double GESTURE_SENSITIVITY_FACTOR = 0.3;
const Duration CONTROL_HIDE_DELAY = Duration(seconds: 4);
const Duration SAVE_INTERVAL = Duration(seconds: 10);
const String PREF_SEEK_MODE = 'seek_mode';

class VideoPlayerPage extends StatefulWidget {
  final List<VideoItem> videoList;
  final int initialIndex;
  final String folderName;

  const VideoPlayerPage({
    Key? key,
    required this.videoList,
    required this.initialIndex,
    required this.folderName,
  }) : super(key: key);

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> with WidgetsBindingObserver {
  late final Player player;
  late final VideoController videoController;

  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isEnded = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _aspectRatio = 16 / 9;

  final List<StreamSubscription> _subscriptions = [];

  bool _showControls = true;
  bool _isFullScreen = false;
  bool _showSpeedSelector = false;
  final List<double> _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  Timer? _hideTimer;
  Timer? _periodicSaveTimer;

  bool _isSwitchingVideo = false;
  bool _isDisposing = false;
  bool _hasError = false; // [新增] 状态：用于标记是否发生播放错误

  double _gestureStartX = 0;
  double _gestureStartY = 0;
  bool _isHorizontalDrag = false;
  bool _isVerticalDrag = false;
  bool _isBrightnessGesture = false;
  bool _isVolumeGesture = false;
  double _brightness = 0.5;
  double _volume = 0.5;
  String _feedbackText = '';
  IconData _feedbackIcon = Icons.volume_up;
  bool _showFeedback = false;
  Duration? _pendingSeekPosition;
  bool _hasSeekedInThisGesture = false;

  bool _isSeeking = false;
  double _originalRate = 1.0;
  bool _isLongPressSeeking = false;

  SeekMode _seekMode = SeekMode.proportional;
  late int _index;
  SharedPreferences? _prefs;
  Duration _lastSavedPosition = Duration.zero;
  late StreamSubscription<List<ConnectivityResult>> _connSub;

  final MediaCastDlnaApi _dlnaApi = MediaCastDlnaApi();
  List<DlnaDevice> _discoveredDevices = [];
  bool _isDiscovering = false;
  DlnaDevice? _selectedRenderer;
  Timer? _dlnaTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // ================== 正确的缓冲配置方式 ==================
    player = Player();

    videoController = VideoController(player);

    _index = widget.initialIndex;
    _listenToPlayerEvents();
    _initSharedPrefsAndLoadVideo();
    _listenConnectivity();
    _initDlnaService();

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        VolumeController.instance.showSystemUI = false;
      } catch (_) {}
    }
  }

  void _listenToPlayerEvents() {
    _subscriptions.addAll([
      player.stream.playing.listen((playing) {
        if (mounted) setState(() => _isPlaying = playing);
      }),
      player.stream.completed.listen((completed) {
        if (completed && !_isEnded) {
          if (mounted) {
            setState(() => _isEnded = true);
            _playNext();
          }
        }
      }),
      player.stream.buffering.listen((buffering) {
        if (mounted) setState(() => _isBuffering = buffering);
      }),
      player.stream.position.listen((pos) {
        if (mounted && !_isSeeking) {
          setState(() => _position = pos);
        }
        _lastSavedPosition = pos;
      }),
      player.stream.duration.listen((dur) {
        if (mounted) setState(() => _duration = dur);
      }),
      player.stream.videoParams.listen((params) {
        if (params.w != null && params.h != null) {
          final width = params.w!;
          final height = params.h!;
          if (width > 0 && height > 0) {
            if (mounted) {
              setState(() => _aspectRatio = width / height);
            }
          }
        }
      }),
      // [新增] 监听播放器错误流
      player.stream.error.listen((error) {
        debugPrint('播放器错误: $error');
        if (mounted) setState(() => _hasError = true);
      }),
    ]);
  }

  Future<void> _initSharedPrefsAndLoadVideo() async {
    _prefs = await SharedPreferences.getInstance();
    final savedModeIndex =
        _prefs!.getInt(PREF_SEEK_MODE) ?? SeekMode.proportional.index;
    if (mounted) {
      setState(() => _seekMode = SeekMode.values[savedModeIndex]);
    }
    await _initializePlayer();
  }

  void _listenConnectivity() {
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final isConnected = results.any((result) => result != ConnectivityResult.none);
      if (isConnected && !_isPlaying) {
        player.play();
      }
    });
  }

  Future<void> _initDlnaService() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _dlnaApi.initializeUpnpService();
    } catch (e) {
      debugPrint('DLNA init failed: $e');
    }
  }

  Future<void> _initializePlayer() async {
    if (_isDisposing || _prefs == null) return;
    if (widget.videoList.isEmpty ||
        _index < 0 ||
        _index >= widget.videoList.length) {
      return;
    }

    // [新增] 在开始加载前重置错误状态
    if (_hasError) {
      setState(() => _hasError = false);
    }

    final item = widget.videoList[_index];
    final url = ApiService.getVideoUrl(widget.folderName, item.name);

    debugPrint('initializePlayer: opening url=$url');

    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        _brightness = await ScreenBrightness().current ?? 0.5;
        _volume = await VolumeController.instance.getVolume() ?? 0.5;
      }
    } catch (_) {}

    final isHwdecDisabled = _prefs!.getBool(PREF_HWDEC_DISABLED) ?? false;
    debugPrint("硬件解码是否被禁用? -> $isHwdecDisabled");

    final media = Media(url,
      httpHeaders: {
        // 确保支持 Range 请求，这是快进秒进的关键
        'Accept': '*/*',
        'Accept-Ranges': 'bytes',
      },
      extras: {
        // 1. 降低预读取时间（3-5秒足够局域网使用）
        'demuxer-readahead-secs': '3.0',

        // 2. 限制最大缓冲内存（避免内存暴涨）
        'demuxer-max-bytes': '${50 * 1024 * 1024}', // 50MB足够

        // 3. 关键：确保流可 seek，即使 HTTP 服务器没有明确标识
        'force-seekable': 'yes',

        // 4. 启用 seek 缓存优化（避免快进时重新下载）
        'cache-seekable': 'yes',
        'demuxer-seekable-cache': 'yes',

        // 5. 网络优化：减少 TCP 延迟
        'tcp-nodelay': 'yes',

        // 6. 缓存策略：边下边播，不等缓冲满
        'cache-pause': 'no',  // 缓冲时不暂停播放

        // 7. 短启动时间（快速开始播放）
        'vd-lavc-fast': 'yes',

        // 8. 硬件解码控制
        if (isHwdecDisabled) 'hwdec': 'no' else 'hwdec': 'auto-safe',

        // 9. 用户标识（某些服务器需要）
        'user-agent': 'MediaKit/1.0',
      },
    );
    await player.open(media, play: true);
    // 关键：设置播放器的缓冲模式（media_kit 特定 API）
    await player.setPlaylistMode(PlaylistMode.none);
    // 预加载下一集（如果适用）
    if (_index < widget.videoList.length - 1) {
      final nextItem = widget.videoList[_index + 1];
      final nextUrl = ApiService.getVideoUrl(widget.folderName, nextItem.name);
      // 可选：预加载下一集元数据，但不缓冲视频内容
    }
    final saved = _prefs!.getInt('${item.name}_position');
    if (saved != null && saved > 0) {
      _lastSavedPosition = Duration(milliseconds: saved);
      player.seek(_lastSavedPosition);
    }

    _startHideTimer();
    _startPeriodicSave();
  }

  void _startPeriodicSave() {
    _periodicSaveTimer?.cancel();
    _periodicSaveTimer = Timer.periodic(SAVE_INTERVAL, (_) {
      if (_prefs == null || _isDisposing) return;
      if (widget.videoList.isNotEmpty &&
          _index >= 0 &&
          _index < widget.videoList.length) {
        final key = widget.videoList[_index].name;
        if (_lastSavedPosition > Duration.zero) {
          _prefs!.setInt('${key}_position', _lastSavedPosition.inMilliseconds);
        }
      }
    });
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (_showControls) {
      _hideTimer = Timer(CONTROL_HIDE_DELAY, () {
        if (mounted && !_isDisposing) setState(() => _showControls = false);
      });
    }
  }

  void _togglePlayPause() {
    player.playOrPause();
    _startHideTimer();
  }

  Future<void> _changeVideoToIndex(int newIndex) async {
    if (mounted) {
      setState(() {
        _index = newIndex;
        _position = Duration.zero;
        _duration = Duration.zero;
        _isEnded = false;
        _aspectRatio = 16 / 9;
        _hasError = false; // [新增] 切换视频时重置错误状态
      });
    }
    await _initializePlayer();
  }

  Future<void> _playNext() async {
    if (_isSwitchingVideo) return;
    final next = _index + 1;
    if (next < widget.videoList.length) {
      try {
        if (mounted) setState(() => _isSwitchingVideo = true);
        await _changeVideoToIndex(next);
      } finally {
        if (mounted) setState(() => _isSwitchingVideo = false);
      }
    }
  }

  Future<void> _playPrevious() async {
    if (_isSwitchingVideo) return;
    final prev = _index - 1;
    if (prev >= 0) {
      try {
        if (mounted) setState(() => _isSwitchingVideo = true);
        await _changeVideoToIndex(prev);
      } finally {
        if (mounted) setState(() => _isSwitchingVideo = false);
      }
    }
  }

  Future<void> _playNextWithIndex(int newIndex) async {
    if (_isSwitchingVideo || newIndex == _index) return;
    try {
      if (mounted) setState(() => _isSwitchingVideo = true);
      await _changeVideoToIndex(newIndex);
    } finally {
      if (mounted) setState(() => _isSwitchingVideo = false);
    }
  }

  void _onPanStart(DragStartDetails d) {
    if (_isSwitchingVideo) return;
    _gestureStartX = d.globalPosition.dx;
    _gestureStartY = d.globalPosition.dy;
    _isHorizontalDrag = false;
    _isVerticalDrag = false;
    _isBrightnessGesture = false;
    _isVolumeGesture = false;
    _isSeeking = false;
    _hasSeekedInThisGesture = false;
    _hideTimer?.cancel();
    _pendingSeekPosition = _position;
    if (mounted)
      setState(() {
        _showControls = true;
        _showFeedback = false;
      });
  }

  Future<void> _onPanUpdate(DragUpdateDetails d) async {
    if (!mounted || _pendingSeekPosition == null || _isDisposing || _isSwitchingVideo) return;
    final dx = d.globalPosition.dx - _gestureStartX;
    final dy = d.globalPosition.dy - _gestureStartY;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenCenter = screenWidth / 2;

    if (!_isHorizontalDrag && !_isVerticalDrag) {
      if (dx.abs() > dy.abs()) {
        _isHorizontalDrag = true;
      } else {
        _isVerticalDrag = true;
        if (_gestureStartX < screenCenter) {
          _isBrightnessGesture = true;
          _feedbackIcon = Icons.brightness_6;
        } else {
          _isVolumeGesture = true;
          _feedbackIcon = Icons.volume_up;
        }
      }
    }

    if (_isHorizontalDrag) {
      _isSeeking = true;
      if (_seekMode == SeekMode.proportional) {
        final fraction = dx / screenWidth;
        final totalSec = _duration.inSeconds <= 0 ? 60 : _duration.inSeconds;
        final deltaSec = (fraction * totalSec * 0.3).toInt();
        final startSec = _position.inSeconds;
        final newSec = (startSec + deltaSec).clamp(0, totalSec);
        _pendingSeekPosition = Duration(seconds: newSec);
        _feedbackText = '${_format(_pendingSeekPosition!)} / ${_format(_duration)}';
        _feedbackIcon = deltaSec >= 0 ? Icons.fast_forward : Icons.fast_rewind;
        if (mounted) setState(() => _showFeedback = true);
      } else {
        if (!_hasSeekedInThisGesture) {
          final currentSeconds = _position.inSeconds;
          final totalSeconds = _duration.inSeconds;
          int newSec;
          if (dx > 0) {
            newSec = (currentSeconds + SEEK_STEP_SECONDS).clamp(0, totalSeconds);
            _feedbackText = '+${SEEK_STEP_SECONDS}s';
            _feedbackIcon = Icons.forward_10;
          } else {
            newSec = (currentSeconds - SEEK_STEP_SECONDS).clamp(0, totalSeconds);
            _feedbackText = '-${SEEK_STEP_SECONDS}s';
            _feedbackIcon = Icons.replay_10;
          }
          await player.seek(Duration(seconds: newSec));
          _hasSeekedInThisGesture = true;
          if (mounted) setState(() => _showFeedback = true);
        }
      }
    } else if (_isVerticalDrag) {
      if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
      final screenHeight = MediaQuery.of(context).size.height;
      final change = -dy / screenHeight * GESTURE_SENSITIVITY_FACTOR;
      if (_isBrightnessGesture) {
        _brightness = (_brightness + change).clamp(0.0, 1.0);
        _feedbackText = '亮度 ${(_brightness * 100).toInt()}%';
        try {
          await ScreenBrightness().setScreenBrightness(_brightness);
        } catch (e) {
          debugPrint('set brightness error: $e');
        }
      } else if (_isVolumeGesture) {
        _volume = (_volume + change).clamp(0.0, 1.0);
        _feedbackText = '音量 ${(_volume * 100).toInt()}%';
        try {
          await VolumeController.instance.setVolume(_volume);
        } catch (e) {
          debugPrint('set volume error: $e');
        }
      }
      if (mounted) setState(() => _showFeedback = true);
    }
  }

  Future<void> _onPanEnd(DragEndDetails d) async {
    if (_isSwitchingVideo) return;
    _hideTimer?.cancel();
    if (_isHorizontalDrag && _pendingSeekPosition != null) {
      await player.seek(_pendingSeekPosition!);
    }
    if(mounted) {
      setState(() {
        _pendingSeekPosition = null;
        _isSeeking = false;
      });
    }

    Timer(const Duration(milliseconds: 700), () {
      if (mounted)
        setState(() {
          _showFeedback = false;
        });
    });
    if (_showControls) _startHideTimer();
  }

  Future<void> _toggleFullscreen() async {
    _isFullScreen = !_isFullScreen;
    if (_isFullScreen) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await SystemChrome.setPreferredOrientations(
            [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      }
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await SystemChrome.setPreferredOrientations(
            [DeviceOrientation.portraitUp]);
      }
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_prefs == null) {
      return const Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _showControls = !_showControls),
        onDoubleTap: _togglePlayPause,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: _aspectRatio,
                child: _buildPlayer(),
              ),
            ),
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_showControls,
                child: Stack(
                  children: [
                    Positioned(
                        top: 0, left: 0, right: 0, child: _buildTopBar()),
                    Positioned(
                        bottom: 0, left: 0, right: 0, child: _buildBottomBar()),
                  ],
                ),
              ),
            ),
            Center(child: _buildFeedback()),
            if (_isEnded)
              Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  child: Center(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        player.seek(Duration.zero);
                        player.play();
                        setState(() => _isEnded = false);
                      },
                      icon: const Icon(Icons.replay),
                      label: const Text('重新播放'),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // [优化] _buildPlayer 方法现在包含错误处理UI
  Widget _buildPlayer() {
    if (_hasError) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.white70, size: 48),
              const SizedBox(height: 16),
              const Text('视频加载失败', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white12,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.refresh),
                label: const Text('点击重试'),
                onPressed: () {
                  _initializePlayer();
                },
              )
            ],
          ),
        ),
      );
    }
    if (_isSwitchingVideo || (_isBuffering && !_isPlaying)) {
      return Container(
          color: Colors.black,
          child: const Center(child: CircularProgressIndicator()));
    }
    return Video(
      controller: videoController,
      controls: (state) => const SizedBox.shrink(),
    );
  }

  bool get _isLandscape =>
      MediaQuery.of(context).orientation == Orientation.landscape;

  double get _controlIconSize => _isLandscape ? 30.0 : 36.0;

  Widget _buildTopBar() {
    final title =
    widget.videoList.isNotEmpty ? widget.videoList[_index].name : '';
    return SafeArea(
      top: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.black87, Colors.transparent],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Row(
          children: [
            IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context)),
            Expanded(
                child: Text(title,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    overflow: TextOverflow.ellipsis)),
            IconButton(
                icon: const Icon(Icons.settings, color: Colors.white),
                onPressed: _openSettingsSheet),
            IconButton(
                icon: const Icon(Icons.queue_music, color: Colors.white),
                onPressed: _openPlaylistSheet),
            if (!kIsWeb && Platform.isAndroid)
              IconButton(
                  icon: const Icon(Icons.cast, color: Colors.white),
                  onPressed: _openCastSheet),
            if (!kIsWeb && Platform.isAndroid)
              IconButton(
                  icon: const Icon(Icons.picture_in_picture_alt,
                      color: Colors.white),
                  onPressed: enterPip),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final maxSec = _duration.inSeconds > 0 ? _duration.inSeconds.toDouble() : 1.0;
    final cur = _position.inSeconds.toDouble().clamp(0.0, maxSec);
    final hasPrev = widget.videoList.length > 1 && _index > 0;
    final hasNext =
        widget.videoList.length > 1 && _index < widget.videoList.length - 1;

    return SafeArea(
      bottom: true,
      child: Container(
        padding:
        EdgeInsets.symmetric(horizontal: 10, vertical: _isLandscape ? 6 : 8),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.black87, Colors.transparent],
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                    width: _isLandscape ? 60 : 50,
                    child: Text(_format(_position),
                        style:
                        const TextStyle(color: Colors.white, fontSize: 12))),
                Expanded(
                  child: Slider(
                    value: cur,
                    min: 0.0,
                    max: maxSec,
                    // [优化] 在与Slider交互时，重置控制栏隐藏计时器
                    onChanged: (v) {
                      setState(() => _position = Duration(seconds: v.toInt()));
                      _startHideTimer();
                    },
                    onChangeEnd: (v) {
                      player.seek(Duration(seconds: v.toInt()));
                      _startHideTimer();
                    },
                  ),
                ),
                SizedBox(
                    width: _isLandscape ? 60 : 50,
                    child: Text(_format(_duration),
                        style:
                        const TextStyle(color: Colors.white, fontSize: 12))),
              ],
            ),
            const SizedBox(height: 6),
            _isLandscape
                ? _buildControlRowLandscape(hasPrev, hasNext)
                : _buildControlRowPortrait(hasPrev, hasNext),
            if (_showSpeedSelector)
              Container(
                margin: const EdgeInsets.only(top: 8),
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: _speeds.map((s) {
                    final sel = s == player.state.rate;
                    return GestureDetector(
                      onTap: () {
                        player.setRate(s);
                        setState(() => _showSpeedSelector = false);
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                            color: sel ? Colors.redAccent : Colors.white10,
                            borderRadius: BorderRadius.circular(6)),
                        child: Center(
                            child: Text('${s}x',
                                style: TextStyle(
                                    color: sel
                                        ? Colors.white
                                        : Colors.white70))),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlRowPortrait(bool hasPrev, bool hasNext) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        IconButton(
            icon: Icon(Icons.skip_previous,
                color: hasPrev ? Colors.white : Colors.white30),
            onPressed:
            hasPrev && !_isSwitchingVideo ? _playPrevious : null),
        _buildSeekButton(
            icon: Icons.replay_10,
            isForward: false
        ),
        IconButton(
            icon: Icon(
                _isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_fill,
                color: Colors.white,
                size: _controlIconSize),
            onPressed: _togglePlayPause),
        _buildSeekButton(
            icon: Icons.forward_10,
            isForward: true
        ),
        IconButton(
            icon: Icon(Icons.skip_next,
                color: hasNext ? Colors.white : Colors.white30),
            onPressed: hasNext && !_isSwitchingVideo ? _playNext : null),
        GestureDetector(
          onTap: () => setState(() => _showSpeedSelector = !_showSpeedSelector),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
                color: Colors.white12, borderRadius: BorderRadius.circular(6)),
            child: Text('${player.state.rate}x',
                style: const TextStyle(color: Colors.white)),
          ),
        ),
        IconButton(
            icon: Icon(
                _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                color: Colors.white),
            onPressed: _toggleFullscreen),
      ],
    );
  }

  Widget _buildControlRowLandscape(bool hasPrev, bool hasNext) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            IconButton(
                icon: Icon(Icons.skip_previous,
                    color: hasPrev ? Colors.white : Colors.white30,
                    size: _controlIconSize
                ),
                onPressed:
                hasPrev && !_isSwitchingVideo ? _playPrevious : null),
            _buildSeekButton(
                icon: Icons.replay_10,
                isForward: false,
                iconSize: _controlIconSize
            ),
          ],
        ),
        IconButton(
            icon: Icon(
                _isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_fill,
                color: Colors.white,
                size: _controlIconSize * 1.2),
            onPressed: _togglePlayPause),
        Row(
          children: [
            _buildSeekButton(
                icon: Icons.forward_10,
                isForward: true,
                iconSize: _controlIconSize
            ),
            IconButton(
                icon: Icon(Icons.skip_next,
                    color: hasNext ? Colors.white : Colors.white30,
                    size: _controlIconSize
                ),
                onPressed: hasNext && !_isSwitchingVideo ? _playNext : null),
            const SizedBox(width: 12),
            GestureDetector(
              onTap: () =>
                  setState(() => _showSpeedSelector = !_showSpeedSelector),
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(6)),
                child: Text('${player.state.rate}x',
                    style: const TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
                icon: Icon(
                    _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    color: Colors.white,
                    size: _controlIconSize
                ),
                onPressed: _toggleFullscreen),
          ],
        ),
      ],
    );
  }

  Widget _buildSeekButton({
    required IconData icon,
    required bool isForward,
    double? iconSize,
  }) {
    return GestureDetector(
      onTap: () {
        if (_isLongPressSeeking) return;

        final targetPosition = isForward
            ? _position + const Duration(seconds: SEEK_STEP_SECONDS)
            : _position - const Duration(seconds: SEEK_STEP_SECONDS);
        player.seek(targetPosition);
        _startHideTimer();
      },
      onLongPressStart: (_) {
        _hideTimer?.cancel();
        setState(() {
          _isLongPressSeeking = true;
          _originalRate = player.state.rate;
          player.setRate(LONG_PRESS_RATE);
          _feedbackIcon = isForward ? Icons.fast_forward : Icons.fast_rewind;
          _feedbackText = '${LONG_PRESS_RATE}x';
          _showFeedback = true;
        });
      },
      onLongPressEnd: (_) {
        _startHideTimer();
        setState(() {
          player.setRate(_originalRate);
          _showFeedback = false;
        });
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted) {
            _isLongPressSeeking = false;
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Icon(icon, color: Colors.white, size: iconSize),
      ),
    );
  }

  Widget _buildFeedback() {
    return AnimatedOpacity(
      opacity: _showFeedback ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: _showFeedback
          ? Container(
        padding:
        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_feedbackIcon, color: Colors.white),
            const SizedBox(width: 8),
            Text(_feedbackText,
                style: const TextStyle(color: Colors.white)),
          ],
        ),
      )
          : const SizedBox.shrink(),
    );
  }

  String _format(Duration d) {
    final two = (int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  void _openSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter sheetSetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Text('播放设置',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold))),
                      const Divider(color: Colors.white24),
                      const Padding(
                          padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text('左右滑动快进/退方式',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 14))),
                      RadioListTile<SeekMode>(
                        title: const Text('按滑动距离 (动态)',
                            style: TextStyle(color: Colors.white)),
                        subtitle: const Text('滑得越远，跳得越多',
                            style: TextStyle(color: Colors.white60)),
                        value: SeekMode.proportional,
                        groupValue: _seekMode,
                        onChanged: (SeekMode? value) {
                          if (value != null) {
                            sheetSetState(() => _seekMode = value);
                            if (mounted) setState(() => _seekMode = value);
                            _prefs?.setInt(PREF_SEEK_MODE, value.index);
                          }
                        },
                        activeColor: Colors.redAccent,
                      ),
                      RadioListTile<SeekMode>(
                        title: const Text('按固定时长 (10秒)',
                            style: TextStyle(color: Colors.white)),
                        subtitle: const Text('滑动一次，跳10秒',
                            style: TextStyle(color: Colors.white60)),
                        value: SeekMode.fixed,
                        groupValue: _seekMode,
                        onChanged: (SeekMode? value) {
                          if (value != null) {
                            sheetSetState(() => _seekMode = value);
                            if (mounted) setState(() => _seekMode = value);
                            _prefs?.setInt(PREF_SEEK_MODE, value.index);
                          }
                        },
                        activeColor: Colors.redAccent,
                      ),
                      const SizedBox(height: 16),
                    ]),
              ),
            );
          },
        );
      },
    );
  }

  void _openPlaylistSheet() {
    final double itemHeight = 56.0;
    final double initialScrollOffset = _index * itemHeight;
    final scrollController = ScrollController(initialScrollOffset: initialScrollOffset);

    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.black87,
        builder: (ctx) {
          return SafeArea(
            child: SingleChildScrollView(
              controller: scrollController,
              child: Column(children: [
                const SizedBox(height: 8),
                const Text('播放列表',
                    style: TextStyle(color: Colors.white70, fontSize: 16)),
                const Divider(color: Colors.white12),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: widget.videoList.length,
                  itemBuilder: (c, i) {
                    final it = widget.videoList[i];
                    final sel = i == _index;
                    return ListTile(
                      tileColor: sel ? Colors.red.withOpacity(0.3) : Colors.transparent,
                      title: Text(it.name,
                        style: TextStyle(
                          color: sel ? Colors.white : Colors.white70,
                          fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      leading: sel
                          ? const Icon(Icons.play_arrow, color: Colors.white)
                          : const SizedBox(width: 24),
                      onTap: () {
                        Navigator.pop(ctx);
                        _playNextWithIndex(i);
                      },
                    );
                  },
                ),
                const SizedBox(height: 16),
              ]),
            ),
          );
        });
  }

  void _openCastSheet() {
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.black87,
        builder: (ctx) {
          return SafeArea(
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const ListTile(
                    title: Text('发现投屏设备',
                        style: TextStyle(color: Colors.white))),
                if (!_isDiscovering)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [
                      ElevatedButton(
                          onPressed: () {
                            startDlnaDiscovery(timeoutSeconds: 10);
                            Navigator.pop(ctx);
                          },
                          child: const Text('开始发现')),
                      const SizedBox(width: 12),
                      ElevatedButton(
                          onPressed: () async {
                            try {
                              await _dlnaApi.stopDiscovery();
                            } catch (e) {
                              debugPrint('stop discovery manual error: $e');
                            }
                            if (mounted)
                              setState(() => _isDiscovering = false);
                          },
                          child: const Text('停止')),
                    ]),
                  ),
                if (_discoveredDevices.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('暂无设备',
                          style: TextStyle(color: Colors.white70))),
                ..._discoveredDevices.map((d) => ListTile(
                  title: Text(
                      d.friendlyName ?? d.udn?.value ?? 'unknown',
                      style: const TextStyle(color: Colors.white)),
                  subtitle: Text(d.deviceType ?? '',
                      style: const TextStyle(color: Colors.white60)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _castToRenderer(d);
                  },
                )),
                const SizedBox(height: 16),
              ]),
            ),
          );
        });
  }

  Future<void> enterPip() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('画中画仅 Android 支持')));
      return;
    }
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
          Text('PiP 未配置：请在 pubspec 添加并配置 simple_pip_mode 或其它 PiP 库')));
  }

  Future<void> startDlnaDiscovery({int timeoutSeconds = 10}) async {
    if (!mounted || _isDisposing) return;
    if (_isDiscovering) return;
    if (mounted) setState(() => _isDiscovering = true);
    try {
      await _dlnaApi.startDiscovery(DiscoveryOptions(
          timeout: DiscoveryTimeout(seconds: timeoutSeconds),
          searchTarget: SearchTarget(target: 'upnp:rootdevice')));
      _dlnaTimer?.cancel();
      int ticks = 0;
      _dlnaTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
        ticks++;
        try {
          final devices = await _dlnaApi.getDiscoveredDevices();
          if (!mounted || _isDisposing) {
            t.cancel();
            _dlnaTimer = null;
            return;
          }
          if (mounted) setState(() => _discoveredDevices = devices);
        } catch (e) {
          debugPrint('dlna periodic error: $e');
        }
        if (ticks >= (timeoutSeconds ~/ 2)) {
          t.cancel();
          _dlnaTimer = null;
          try {
            await _dlnaApi.stopDiscovery();
          } catch (e) {
            debugPrint('stop discovery error: $e');
          }
          if (mounted) setState(() => _isDiscovering = false);
        }
      });
    } catch (e) {
      debugPrint('DLNA discovery error: $e');
      if (mounted) setState(() => _isDiscovering = false);
      _dlnaTimer?.cancel();
      _dlnaTimer = null;
    }
  }

  Future<void> _castToRenderer(DlnaDevice renderer) async {
    final url =
    ApiService.getVideoUrl(widget.folderName, widget.videoList[_index].name);
    try {
      final metadata = VideoMetadata(
          title: widget.videoList[_index].name,
          duration: TimeDuration(seconds: _duration.inSeconds),
          resolution: 'auto',
          genre: 'Video',
          upnpClass: 'object.item.videoItem.movie');
      await _dlnaApi.setMediaUri(renderer.udn, Url(value: url), metadata);
      await _dlnaApi.play(renderer.udn);
      if (mounted) setState(() => _selectedRenderer = renderer);
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('开始投屏（DLNA）')));
    } catch (e) {
      debugPrint('cast error: $e');
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('投屏失败: $e')));
    }
  }


  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([]);

    Future.delayed(Duration.zero, () {
      if (!_isDisposing) return;

      for (var sub in _subscriptions) {
        sub.cancel();
      }
      player.dispose();
      _hideTimer?.cancel();
      _periodicSaveTimer?.cancel();
      _dlnaTimer?.cancel();
      _connSub.cancel();
    });

    _isDisposing = true;
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }
}