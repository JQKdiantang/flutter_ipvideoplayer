// lib/pages/video_player_page.dart
// [修复] 增加了状态锁(_isSwitchingVideo)来防止因快速、重复点击“下一部”而导致的并发资源冲突和APP崩溃。
// [修复] 在切换视频期间，禁用控制按钮并显示加载指示器，以提供清晰的UI反馈。
// [修复] 在销毁和重建控制器之间加入微小延迟，增强在不同设备上的稳定性。

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:media_cast_dlna/media_cast_dlna.dart';

import '../services/api_service.dart';
import '../models/video_item.dart';

enum SeekMode { proportional, fixed }

const int SEEK_STEP_SECONDS = 10;
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
  VlcPlayerController? _controller;
  bool _controllerReady = false;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isEnded = false;
  bool _showControls = true;
  bool _isFullScreen = false;
  bool _showSpeedSelector = false;
  double _playbackSpeed = 1.0;
  final List<double> _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Timer? _hideTimer;
  Timer? _periodicSaveTimer;

  // [修复] 增加一个状态锁，防止在切换视频时重复触发
  bool _isSwitchingVideo = false;

  // gesture/feedback
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
  bool _isSeeking = false;
  bool _hasSeekedInThisGesture = false;
  Duration? _pendingSeekPosition;

  // seek mode
  SeekMode _seekMode = SeekMode.proportional;

  // index & prefs
  late int _index;
  SharedPreferences? _prefs;
  Duration _lastSavedPosition = Duration.zero;

  // UI throttle
  int _lastUiUpdateMs = 0;

  // connectivity
  late StreamSubscription<dynamic> _connSub;
  bool _networkAvailable = true;

  // DLNA
  final MediaCastDlnaApi _dlnaApi = MediaCastDlnaApi();
  List<DlnaDevice> _discoveredDevices = [];
  bool _isDiscovering = false;
  DlnaDevice? _selectedRenderer;
  Timer? _dlnaTimer;

  // many protections
  bool _isDisposing = false;

  // buffering timeout
  Timer? _bufferingTimeoutTimer;
  final int _bufferingTimeoutSec = 20;

  // hw accel candidates
  final List<HwAcc> _hwCandidates = [HwAcc.full, HwAcc.auto, HwAcc.disabled];
  int _hwIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _index = widget.initialIndex;
    _initSharedPrefs();
    _listenConnectivity();
    _initDlnaService();
    try {
      VolumeController.instance.showSystemUI = false;
    } catch (_) {}
  }

  Future<void> _initSharedPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    final savedModeIndex = _prefs!.getInt(PREF_SEEK_MODE) ?? SeekMode.proportional.index;
    _seekMode = SeekMode.values[savedModeIndex];
    await _initializePlayer();
  }

  void _listenConnectivity() {
    _connSub = Connectivity().onConnectivityChanged.listen((res) {
      final available = res != ConnectivityResult.none;
      if (available && !_networkAvailable) {
        if (_controller == null || !_controllerReady) {
          _initializePlayerSafe();
        } else if (!_isPlaying) {
          try {
            _controller?.play();
          } catch (e) {
            debugPrint('恢复播放异常: $e');
          }
        }
      }
      _networkAvailable = available;
    });
    Connectivity().checkConnectivity().then((res) => _networkAvailable = res != ConnectivityResult.none);
  }

  Future<void> _initDlnaService() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        await _dlnaApi.initializeUpnpService();
      }
    } catch (e) {
      debugPrint('DLNA init failed: $e');
    }
  }

  Future<void> _tryCheckNetwork(String url) async {
    final conn = await Connectivity().checkConnectivity();
    if (conn == ConnectivityResult.none) throw Exception('无网络连接');
    try {
      final client = http.Client();
      final req = http.Request('HEAD', Uri.parse(url));
      req.headers['Connection'] = 'close';
      final resp = await client.send(req).timeout(const Duration(seconds: 5));
      client.close();
      if (resp.statusCode >= 200 && resp.statusCode < 300) return;
      final resp2 = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (resp2.statusCode >= 200 && resp2.statusCode < 300) return;
    } on TimeoutException {
      throw Exception('网络超时');
    } on SocketException catch (e) {
      throw Exception('网络错误: ${e.message}');
    } catch (e) {
      debugPrint('网络检测警告: $e');
    }
  }

  Future<void> _initializePlayer() async {
    if (_prefs == null) return;
    if (widget.videoList.isEmpty || _index < 0 || _index >= widget.videoList.length) {
      if (mounted && !_isDisposing) setState(() {});
      return;
    }

    final item = widget.videoList[_index];
    final rawUrl = ApiService.getVideoUrl(widget.folderName, item.name);

    String url;
    try {
      url = Uri.parse(rawUrl).toString();
    } catch (e) {
      debugPrint('Uri.parse 失败，回退 rawUrl: $e');
      url = rawUrl;
    }

    debugPrint('initializePlayer: parsedUrl=$url hwCandidateIndex=$_hwIndex');

    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        _brightness = await ScreenBrightness().current ?? 0.5;
        _volume = await VolumeController.instance.getVolume() ?? 0.5;
      }
    } catch (_) {}

    await _disposeController();

    try {
      await _tryCheckNetwork(url);

      final hw = _hwCandidates[_hwIndex.clamp(0, _hwCandidates.length - 1)];
      debugPrint('Creating VlcPlayerController with hwAcc=$hw');

      _controller = VlcPlayerController.network(
        url,
        hwAcc: hw,
        autoPlay: true,
        options: VlcPlayerOptions(),
      );

      _controller!.addListener(_onControllerChanged);
      _controllerReady = true;

      if (mounted && !_isDisposing) setState(() {});

      final saved = _prefs!.getInt('${item.name}_position');
      if (saved != null && saved > 0) {
        _lastSavedPosition = Duration(milliseconds: saved);
        _seekWhenReady(_lastSavedPosition);
      }

      _startHideTimer();
      _startPeriodicSave();
    } catch (e) {
      debugPrint('init player error: $e');
      if (mounted && !_isDisposing) setState(() {
        _isBuffering = false;
        _isPlaying = false;
      });
    }
  }

  Future<void> _initializePlayerSafe() async {
    try {
      await _initializePlayer();
    } catch (e) {
      debugPrint('safe initialize error: $e');
    }
  }

  void _onPlaybackStall() async {
    if (_isDisposing || _isSwitchingVideo) return;
    _cancelBufferingTimeout();
    debugPrint('Playback stalled or buffering timeout. current hwIndex=$_hwIndex');
    if (_hwIndex < _hwCandidates.length - 1) {
      _hwIndex++;
      debugPrint('尝试切换 hwAcc 并重试，new hwIndex=$_hwIndex');
      await _initializePlayerSafe();
    } else {
      if (mounted && !_isDisposing) {
        setState(() {
          _isBuffering = false;
          _isPlaying = false;
          _isEnded = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('播放失败，已尝试所有解码模式。')));
      }
    }
  }

  void _startBufferingTimeout() {
    _cancelBufferingTimeout();
    _bufferingTimeoutTimer = Timer(Duration(seconds: _bufferingTimeoutSec), () {
      debugPrint('buffering timeout triggered');
      _onPlaybackStall();
    });
  }

  void _cancelBufferingTimeout() {
    _bufferingTimeoutTimer?.cancel();
    _bufferingTimeoutTimer = null;
  }

  void _startPeriodicSave() {
    _periodicSaveTimer?.cancel();
    _periodicSaveTimer = Timer.periodic(SAVE_INTERVAL, (_) {
      if (_prefs == null) return;
      if (widget.videoList.isNotEmpty && _index >= 0 && _index < widget.videoList.length) {
        final key = widget.videoList[_index].name;
        if (_lastSavedPosition > Duration.zero) {
          try {
            _prefs!.setInt('${key}_position', _lastSavedPosition.inMilliseconds);
          } catch (e) {
            debugPrint('save pos error: $e');
          }
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
    if (_controller == null || !_controllerReady) return;
    try {
      if (_isPlaying) {
        _controller!.pause();
      } else {
        if (_isEnded) {
          _controller!.seekTo(Duration.zero);
        }
        _controller!.play();
      }
    } catch (e) {
      debugPrint('togglePlayPause error: $e');
    }
    _startHideTimer();
  }

  Future<void> _toggleFullscreen() async {
    _isFullScreen = !_isFullScreen;
    try {
      if (_isFullScreen) {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      } else {
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      }
    } catch (e) {
      debugPrint('fullscreen error: $e');
      _isFullScreen = !_isFullScreen;
    }
    if (mounted && !_isDisposing) setState(() {});
  }

  // [修复] 增加锁和UI反馈，防止快速点击崩溃
  Future<void> _playNext() async {
    if (_isSwitchingVideo) return;
    if (widget.videoList.isEmpty) return;
    final next = _index + 1;
    if (next < widget.videoList.length) {
      try {
        setState(() => _isSwitchingVideo = true);
        await _changeVideoToIndex(next);
      } finally {
        if (mounted) setState(() => _isSwitchingVideo = false);
      }
    } else {
      if (mounted && !_isDisposing) setState(() { _isEnded = true; _showControls = true; });
    }
  }

  // [修复] 增加锁和UI反馈，防止快速点击崩溃
  Future<void> _playPrevious() async {
    if (_isSwitchingVideo) return;
    if (widget.videoList.isEmpty) return;
    final prev = _index - 1;
    if (prev >= 0) {
      try {
        setState(() => _isSwitchingVideo = true);
        await _changeVideoToIndex(prev);
      } finally {
        if (mounted) setState(() => _isSwitchingVideo = false);
      }
    }
  }

  // [修复] 增加锁和UI反馈，防止快速点击崩溃 (用于播放列表)
  Future<void> _playNextWithIndex(int newIndex) async {
    if (_isSwitchingVideo) return;
    if (newIndex == _index) return;

    try {
      setState(() => _isSwitchingVideo = true);
      await _changeVideoToIndex(newIndex);
    } finally {
      if (mounted) setState(() => _isSwitchingVideo = false);
    }
  }

  // [修复] 抽取出公共的视频切换逻辑
  Future<void> _changeVideoToIndex(int newIndex) async {
    await _disposeController();
    await Future.delayed(const Duration(milliseconds: 200)); // 原生延迟

    if (mounted && !_isDisposing) {
      setState(() {
        _index = newIndex;
        _controllerReady = false;
        _showControls = true;
        _position = Duration.zero;
        _duration = Duration.zero;
      });
    }
    _hwIndex = 0;
    await _initializePlayer();
  }

  Future<void> _disposeController() async {
    _cancelBufferingTimeout();
    final toDispose = _controller;
    if (toDispose == null) return;

    _controller = null;
    _controllerReady = false;

    try {
      toDispose.removeListener(_onControllerChanged);
    } catch (e) {
      debugPrint('removeListener during dispose error: $e');
    }
    try {
      await toDispose.dispose();
    } catch (e) {
      debugPrint('controller dispose error: $e');
    }
  }

  void _seekWhenReady(Duration pos) {
    Future(() async {
      for (int i = 0; i < 20; i++) {
        if (_isDisposing || _controller == null) return;
        try {
          if (_controller!.value.isInitialized && _controller!.value.duration > Duration.zero) {
            await _controller!.seekTo(pos);
            return;
          }
        } catch (e) {}
        await Future.delayed(const Duration(milliseconds: 500));
      }
    });
  }

  void _onControllerChanged() {
    if (_isDisposing || !mounted || _controller == null) return;
    if (_isSwitchingVideo) return; // 在切换时，忽略旧控制器的事件

    try {
      final val = _controller!.value;
      _controllerReady = val.isInitialized;

      final prevBuffering = _isBuffering;
      _isPlaying = val.isPlaying;
      _isBuffering = val.isBuffering;
      _position = val.position;
      _duration = val.duration;
      if (val.position.inMilliseconds > 0) _lastSavedPosition = val.position;

      if (_isBuffering && !prevBuffering) {
        _startBufferingTimeout();
      } else if (!_isBuffering && prevBuffering) {
        _cancelBufferingTimeout();
      }

      if (val.isEnded && !_isEnded) {
        _isEnded = true;
        WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted && !_isDisposing) _playNext(); });
      } else if (!val.isEnded) {
        _isEnded = false;
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - _lastUiUpdateMs > 250) {
        _lastUiUpdateMs = now;
        if (mounted && !_isDisposing) setState(() {});
      }
    } catch (e) {
      debugPrint('onControllerChanged read error: $e');
    }
  }

  void _onPanStart(DragStartDetails d) {
    if (_isSwitchingVideo) return;
    _gestureStartX = d.globalPosition.dx;
    _gestureStartY = d.globalPosition.dy;
    _isHorizontalDrag = false; _isVerticalDrag = false;
    _isBrightnessGesture = false; _isVolumeGesture = false;
    _isSeeking = false;
    _hasSeekedInThisGesture = false;
    _hideTimer?.cancel();
    _pendingSeekPosition = _position;
    if (mounted && !_isDisposing) setState(() { _showControls = true; _showFeedback = false; });
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
        if (_gestureStartX < screenCenter) { _isBrightnessGesture = true; _feedbackIcon = Icons.brightness_6; } else { _isVolumeGesture = true; _feedbackIcon = Icons.volume_up; }
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
        if (mounted && !_isDisposing) setState(() => _showFeedback = true);
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
          if (_controller != null) {
            try { _controller!.seekTo(Duration(seconds: newSec)); } catch (e) { debugPrint('seek error: $e'); }
          }
          if (mounted && !_isDisposing) setState(() => _showFeedback = true);
          _hasSeekedInThisGesture = true;
        }
      }
    } else if (_isVerticalDrag) {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        final screenHeight = MediaQuery.of(context).size.height;
        final change = -dy / screenHeight * GESTURE_SENSITIVITY_FACTOR;
        if (_isBrightnessGesture) {
          _brightness = (_brightness + change).clamp(0.0, 1.0);
          _feedbackText = '亮度 ${(_brightness*100).toInt()}%';
          try { await ScreenBrightness().setScreenBrightness(_brightness); } catch (e) { debugPrint('set brightness error: $e'); }
        } else if (_isVolumeGesture) {
          _volume = (_volume + change).clamp(0.0, 1.0);
          _feedbackText = '音量 ${(_volume*100).toInt()}%';
          try { await VolumeController.instance.setVolume(_volume); } catch (e) { debugPrint('set volume error: $e'); }
        }
        if (mounted && !_isDisposing) setState(() => _showFeedback = true);
      }
    }
  }

  Future<void> _onPanEnd(DragEndDetails d) async {
    if (_isSwitchingVideo) return;
    _hideTimer?.cancel();
    if (_isHorizontalDrag && _pendingSeekPosition != null) {
      if (_controller != null) {
        try {
          await _controller!.seekTo(_pendingSeekPosition!);
        } catch (e) {
          debugPrint('seek on pan end error: $e');
        }
      }
    }
    _pendingSeekPosition = null;
    if (_isVolumeGesture) {
      try {
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          await VolumeController.instance.setVolume(_volume);
        }
      } catch (e) { debugPrint('final set volume error: $e'); }
    }
    Timer(const Duration(milliseconds: 700), () { if (mounted && !_isDisposing) setState(() { _showFeedback = false; _isSeeking = false; }); });
    if (_showControls) _startHideTimer();
  }

  Future<void> startDlnaDiscovery({int timeoutSeconds = 10}) async {
    if (!mounted || _isDisposing) return;
    if (_isDiscovering) return;
    _isDiscovering = true;
    try {
      await _dlnaApi.startDiscovery(DiscoveryOptions(timeout: DiscoveryTimeout(seconds: timeoutSeconds), searchTarget: SearchTarget(target: 'upnp:rootdevice')));
      _dlnaTimer?.cancel();
      int ticks = 0;
      _dlnaTimer = Timer.periodic(const Duration(seconds: 2), (t) async {
        ticks++;
        try {
          final devices = await _dlnaApi.getDiscoveredDevices();
          if (!mounted || _isDisposing) { t.cancel(); _dlnaTimer = null; return; }
          if (mounted && !_isDisposing) setState(() => _discoveredDevices = devices);
        } catch (e) {
          debugPrint('dlna periodic error: $e');
        }
        if (ticks >= (timeoutSeconds ~/ 2)) {
          t.cancel();
          _dlnaTimer = null;
          try { await _dlnaApi.stopDiscovery(); } catch (e) { debugPrint('stop discovery error: $e'); }
          if(mounted) setState(() => _isDiscovering = false);
        }
      });
    } catch (e) {
      debugPrint('DLNA discovery error: $e');
      if(mounted) setState(() => _isDiscovering = false);
      _dlnaTimer?.cancel();
      _dlnaTimer = null;
    }
  }

  Future<void> _castToRenderer(DlnaDevice renderer) async {
    if (_controller == null) return;
    final url = ApiService.getVideoUrl(widget.folderName, widget.videoList[_index].name);
    try {
      final metadata = VideoMetadata(title: widget.videoList[_index].name, duration: TimeDuration(seconds: _duration.inSeconds), resolution: 'auto', genre: 'Video', upnpClass: 'object.item.videoItem.movie');
      await _dlnaApi.setMediaUri(renderer.udn, Url(value: url), metadata);
      await _dlnaApi.play(renderer.udn);
      if (mounted && !_isDisposing) setState(() => _selectedRenderer = renderer);
      if (mounted && !_isDisposing) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('开始投屏（DLNA）')));
    } catch (e) {
      debugPrint('cast error: $e');
      if (mounted && !_isDisposing) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('投屏失败: $e')));
    }
  }

  Future<void> enterPip() async {
    if (kIsWeb) return;
    if (!Platform.isAndroid) {
      if (mounted && !_isDisposing) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('画中画仅 Android 支持')));
      return;
    }
    if (mounted && !_isDisposing) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PiP 未配置：请在 pubspec 添加并配置 simple_pip_mode 或其它 PiP 库')));
  }

  bool get _isLandscape => MediaQuery.of(context).orientation == Orientation.landscape;
  double get _bottomBarHeight => _isLandscape ? 120.0 : 160.0;
  double get _topBarHeight => _isLandscape ? 56.0 : 80.0;
  double _controlIconSize() => _isLandscape ? 30.0 : 36.0;

  Widget _buildPlayer() {
    // [修复] 切换视频时，显示加载动画
    if (_isSwitchingVideo) {
      return Container(color: Colors.black, child: const Center(child: CircularProgressIndicator(color: Colors.white,)));
    }
    if (_controller == null || !_controllerReady) {
      return Container(color: Colors.black, child: const Center(child: CircularProgressIndicator(color: Colors.white,)));
    }
    final aspect = (_controller!.value.isInitialized && _controller!.value.aspectRatio > 0) ? _controller!.value.aspectRatio : 16 / 9;
    return AspectRatio(aspectRatio: aspect, child: VlcPlayer(controller: _controller!, aspectRatio: aspect, placeholder: _isBuffering && !_isSeeking ? const Center(child: CircularProgressIndicator()) : Container()));
  }

  Widget _buildTopBar() {
    final title = (widget.videoList.isNotEmpty && _index >= 0 && _index < widget.videoList.length) ? widget.videoList[_index].name : '';
    return SafeArea(
      top: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: _topBarHeight, minHeight: _isLandscape ? 40.0 : 56.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.black87, Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
            Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16), overflow: TextOverflow.ellipsis)),
            IconButton(icon: const Icon(Icons.settings, color: Colors.white), onPressed: _openSettingsSheet),
            IconButton(icon: const Icon(Icons.queue_music, color: Colors.white), onPressed: _openPlaylistSheet),
            IconButton(icon: const Icon(Icons.cast, color: Colors.white), onPressed: _openCastSheet),
            IconButton(icon: const Icon(Icons.picture_in_picture_alt, color: Colors.white), onPressed: enterPip),
          ]),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final maxSec = _duration.inSeconds > 0 ? _duration.inSeconds.toDouble() : 1.0;
    final cur = (_position.inSeconds.toDouble()).clamp(0.0, maxSec);
    final hasPrev = widget.videoList.length > 1 && _index > 0;
    final hasNext = widget.videoList.length > 1 && _index < widget.videoList.length - 1;

    return SafeArea(
      bottom: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: _bottomBarHeight),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: _isLandscape ? 6 : 8),
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.black87, Colors.transparent], begin: Alignment.bottomCenter, end: Alignment.topCenter)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(
              children: [
                SizedBox(
                  width: _isLandscape ? 60 : 50,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(_format(_position), style: TextStyle(color: Colors.white, fontSize: _isLandscape ? 12 : 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: cur,
                    min: 0.0,
                    max: maxSec,
                    onChanged: (v) {
                      final s = v.toInt();
                      _controller?.seekTo(Duration(seconds: s));
                      if (mounted && !_isDisposing) {
                        setState(() {
                          _position = Duration(seconds: s);
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: _isLandscape ? 60 : 50,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(_format(_duration), style: TextStyle(color: Colors.white, fontSize: _isLandscape ? 12 : 12)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _isLandscape ? _buildControlRowLandscape(hasPrev, hasNext) : _buildControlRowPortrait(hasPrev, hasNext),
            if (_showSpeedSelector)
              Container(
                margin: const EdgeInsets.only(top: 8),
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: _speeds.map((s) {
                    final sel = s == _playbackSpeed;
                    return GestureDetector(
                      onTap: () {
                        if (mounted && !_isDisposing) {
                          setState(() {
                            _playbackSpeed = s;
                            _controller?.setPlaybackSpeed(s);
                            _showSpeedSelector = false;
                          });
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: sel ? Colors.redAccent : Colors.white10, borderRadius: BorderRadius.circular(6)),
                        child: Center(child: Text('${s}x', style: TextStyle(color: sel ? Colors.white : Colors.white70))),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _buildControlRowPortrait(bool hasPrev, bool hasNext) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      // [修复] 切换视频时禁用按钮
      IconButton(icon: Icon(Icons.skip_previous, color: hasPrev ? Colors.white : Colors.white30), onPressed: hasPrev && !_isSwitchingVideo ? _playPrevious : null),
      IconButton(icon: const Icon(Icons.replay_10, color: Colors.white), onPressed: () {
        final newSec = (_position.inSeconds - SEEK_STEP_SECONDS).clamp(0, _duration.inSeconds);
        _controller?.seekTo(Duration(seconds: newSec));
      }),
      IconButton(icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, color: Colors.white, size: _controlIconSize()), onPressed: _togglePlayPause),
      IconButton(icon: Icon(_isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white), onPressed: _toggleFullscreen),
      // [修复] 切换视频时禁用按钮
      IconButton(icon: Icon(Icons.skip_next, color: hasNext ? Colors.white : Colors.white30), onPressed: hasNext && !_isSwitchingVideo ? _playNext : null),
      GestureDetector(onTap: () => setState(() => _showSpeedSelector = !_showSpeedSelector), child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(6)), child: Text('${_playbackSpeed}x', style: const TextStyle(color: Colors.white)))),
    ]);
  }

  Widget _buildControlRowLandscape(bool hasPrev, bool hasNext) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Row(children: [
        // [修复] 切换视频时禁用按钮
        IconButton(icon: Icon(Icons.skip_previous, color: hasPrev ? Colors.white : Colors.white30), onPressed: hasPrev && !_isSwitchingVideo ? _playPrevious : null),
        IconButton(icon: const Icon(Icons.replay_10, color: Colors.white), onPressed: () {
          final newSec = (_position.inSeconds - SEEK_STEP_SECONDS).clamp(0, _duration.inSeconds);
          _controller?.seekTo(Duration(seconds: newSec));
        }),
      ]),
      IconButton(icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill, color: Colors.white, size: _controlIconSize()), onPressed: _togglePlayPause),
      Row(children: [
        IconButton(icon: Icon(_isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white), onPressed: _toggleFullscreen),
        // [修复] 切换视频时禁用按钮
        IconButton(icon: Icon(Icons.skip_next, color: hasNext ? Colors.white : Colors.white30), onPressed: hasNext && !_isSwitchingVideo ? _playNext : null),
        const SizedBox(width: 6),
        GestureDetector(onTap: () => setState(() => _showSpeedSelector = !_showSpeedSelector), child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(6)), child: Text('${_playbackSpeed}x', style: const TextStyle(color: Colors.white)))),
      ]),
    ]);
  }

  Widget _buildFeedback() {
    return AnimatedOpacity(
      opacity: _showFeedback ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: _showFeedback ? Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(_feedbackIcon, color: Colors.white), const SizedBox(width: 8), Text(_feedbackText, style: const TextStyle(color: Colors.white))]),
      ) : const SizedBox.shrink(),
    );
  }

  String _format(Duration d) {
    final two = (int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_prefs == null) {
      return const Scaffold(backgroundColor: Colors.black, body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () { if (mounted && !_isDisposing) setState(() => _showControls = !_showControls); },
        onDoubleTap: _togglePlayPause,
        onPanStart: _onPanStart,
        onPanUpdate: _onPanUpdate,
        onPanEnd: _onPanEnd,
        child: Stack(children: [
          Positioned.fill(child: Center(child: _buildPlayer())),
          Positioned(top: 0, left: 0, right: 0, child: AnimatedOpacity(opacity: _showControls ? 1.0 : 0.0, duration: const Duration(milliseconds: 200), child: IgnorePointer(ignoring: !_showControls, child: SizedBox(height: _topBarHeight, child: _buildTopBar())))),
          Positioned(left: 0, right: 0, bottom: 0, child: AnimatedOpacity(opacity: _showControls ? 1.0 : 0.0, duration: const Duration(milliseconds: 200), child: IgnorePointer(ignoring: !_showControls, child: _buildBottomBar()))),
          Positioned(top: MediaQuery.of(context).size.height * 0.4, left: 0, right: 0, child: Center(child: _buildFeedback())),
          if (_isEnded)
            Positioned.fill(child: Container(color: Colors.black54, child: Center(child: ElevatedButton.icon(
              onPressed: () {
                _controller?.seekTo(Duration.zero);
                _controller?.play();
                if (mounted && !_isDisposing) setState(() => _isEnded = false);
              },
              icon: const Icon(Icons.replay),
              label: const Text('重新播放'),
            )))),
        ]),
      ),
    );
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
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12), child: Text('播放设置', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))),
                  const Divider(color: Colors.white24),
                  const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8), child: Text('左右滑动快进/退方式', style: TextStyle(color: Colors.white70, fontSize: 14))),
                  RadioListTile<SeekMode>(
                    title: const Text('按滑动距离 (动态)', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('滑得越远，跳得越多', style: TextStyle(color: Colors.white60)),
                    value: SeekMode.proportional,
                    groupValue: _seekMode,
                    onChanged: (SeekMode? value) {
                      if (value != null) {
                        sheetSetState(() => _seekMode = value);
                        if (mounted && !_isDisposing) setState(() => _seekMode = value);
                        _prefs?.setInt(PREF_SEEK_MODE, value.index);
                      }
                    },
                    activeColor: Colors.redAccent,
                  ),
                  RadioListTile<SeekMode>(
                    title: const Text('按固定时长 (10秒)', style: TextStyle(color: Colors.white)),
                    subtitle: const Text('滑动一次，跳10秒', style: TextStyle(color: Colors.white60)),
                    value: SeekMode.fixed,
                    groupValue: _seekMode,
                    onChanged: (SeekMode? value) {
                      if (value != null) {
                        sheetSetState(() => _seekMode = value);
                        if (mounted && !_isDisposing) setState(() => _seekMode = value);
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
    showModalBottomSheet(context: context, backgroundColor: Colors.black87, builder: (ctx) {
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(children: [
            const SizedBox(height: 8),
            const Text('播放列表', style: TextStyle(color: Colors.white70, fontSize: 16)),
            const Divider(color: Colors.white12),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.videoList.length,
              itemBuilder: (c, i) {
                final it = widget.videoList[i];
                final sel = i == _index;
                return ListTile(
                  tileColor: sel ? Colors.white12 : Colors.transparent,
                  title: Text(it.name, style: TextStyle(color: sel ? Colors.white : Colors.white70)),
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
    showModalBottomSheet(context: context, backgroundColor: Colors.black87, builder: (ctx) {
      return SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const ListTile(title: Text('发现投屏设备', style: TextStyle(color: Colors.white))),
            if (!_isDiscovering)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  ElevatedButton(onPressed: () { startDlnaDiscovery(timeoutSeconds: 10); }, child: const Text('开始发现')),
                  const SizedBox(width: 12),
                  ElevatedButton(onPressed: () async { try { await _dlnaApi.stopDiscovery(); } catch (e) { debugPrint('stop discovery manual error: $e'); } if (mounted && !_isDisposing) setState(() => _isDiscovering = false); }, child: const Text('停止')),
                ]),
              ),
            if (_discoveredDevices.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('暂无设备', style: TextStyle(color: Colors.white70))),
            ..._discoveredDevices.map((d) => ListTile(
              title: Text(d.friendlyName ?? d.udn?.value ?? 'unknown', style: const TextStyle(color: Colors.white)),
              subtitle: Text(d.deviceType ?? '', style: const TextStyle(color: Colors.white60)),
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

  @override
  void dispose() {
    _isDisposing = true;
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _periodicSaveTimer?.cancel();
    _dlnaTimer?.cancel();
    _bufferingTimeoutTimer?.cancel();
    try { _connSub.cancel(); } catch (e) { debugPrint('connSub cancel error: $e'); }

    _disposeController();

    if (_prefs != null && widget.videoList.isNotEmpty && _index >= 0 && _index < widget.videoList.length) {
      final key = widget.videoList[_index].name;
      try {
        if (_lastSavedPosition > Duration.zero) _prefs!.setInt('${key}_position', _lastSavedPosition.inMilliseconds);
      } catch (e) {
        debugPrint('保存最后进度失败: $e');
      }
    }
    super.dispose();
  }
}