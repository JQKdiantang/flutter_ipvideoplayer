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

const Duration CONTROL_HIDE_DELAY = Duration(seconds: 4);
const Duration SAVE_INTERVAL = Duration(seconds: 10);
const String PREF_SEEK_MODE = 'seek_mode';
const String PREF_HWDEC_DISABLED = 'hwdec_disabled';

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

  final List<StreamSubscription> _subscriptions =[];

  bool _showControls = true;
  bool _isFullscreen = false;
  bool _showSpeedSelector = false;
  final List<double> _speeds =[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  Timer? _hideTimer;
  Timer? _periodicSaveTimer;

  bool _isSwitchingVideo = false;
  bool _isDisposing = false;
  bool _hasError = false;

  // 滑动手势参数 (彻底重构防弹回逻辑)
  bool _isSeeking = false; // 快进锁：滑动时阻断播放器进度刷新
  double _accumulatedDx = 0; // 累计横滑距离
  Duration _startSeekPosition = Duration.zero; // 滑动开始时的基准时间
  Duration? _pendingSeekPosition; // 即将跳往的时间

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

  SeekMode _seekMode = SeekMode.proportional;
  late int _index;
  SharedPreferences? _prefs;
  Duration _lastSavedPosition = Duration.zero;
  late StreamSubscription<List<ConnectivityResult>> _connSub;

  OverlayEntry? _seekTooltipEntry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    player = Player();
    videoController = VideoController(player);

    _index = widget.initialIndex;
    _listenToPlayerEvents();
    _initSharedPrefsAndLoadVideo();
    _listenConnectivity();

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
        if (completed && !_isEnded && mounted) {
          setState(() => _isEnded = true);
          _playNext();
        }
      }),
      player.stream.buffering.listen((buffering) {
        if (mounted) setState(() => _isBuffering = buffering);
      }),
      player.stream.position.listen((pos) {
        // 【关键修复】：如果用户正在拖动，绝对不更新真实进度，防止 UI 被拉回起点
        if (mounted && !_isSeeking) {
          setState(() => _position = pos);
        }
        _lastSavedPosition = pos;
      }),
      player.stream.duration.listen((dur) {
        if (mounted) setState(() => _duration = dur);
      }),
      player.stream.error.listen((error) {
        if (mounted) setState(() => _hasError = true);
      }),
    ]);
  }

  Future<void> _initSharedPrefsAndLoadVideo() async {
    _prefs = await SharedPreferences.getInstance();
    final savedModeIndex = _prefs!.getInt(PREF_SEEK_MODE) ?? SeekMode.proportional.index;
    if (mounted) setState(() => _seekMode = SeekMode.values[savedModeIndex]);
    await _initializePlayer();
  }

  void _listenConnectivity() {
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final isConnected = results.any((result) => result != ConnectivityResult.none);
      if (isConnected && !_isPlaying) player.play();
    });
  }

  Future<void> _initializePlayer() async {
    if (_isDisposing || _prefs == null) return;
    if (widget.videoList.isEmpty || _index < 0 || _index >= widget.videoList.length) return;

    if (_hasError) setState(() => _hasError = false);

    final item = widget.videoList[_index];
    final url = ApiService.getVideoUrl(widget.folderName, item.name);

    try {
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        _brightness = await ScreenBrightness().current ?? 0.5;
        _volume = await VolumeController.instance.getVolume() ?? 0.5;
      }
    } catch (_) {}

    final isHwdecDisabled = _prefs!.getBool(PREF_HWDEC_DISABLED) ?? false;

    final media = Media(url, httpHeaders: {
      'Accept': '*/*',
      'Accept-Ranges': 'bytes',
    }, extras: {
      'force-seekable': 'yes',
      'hwdec': isHwdecDisabled ? 'no' : 'auto-safe',
    });

    await player.open(media, play: true);
    await player.setPlaylistMode(PlaylistMode.none);

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
      if (widget.videoList.isNotEmpty && _index >= 0 && _index < widget.videoList.length) {
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
        _hasError = false;
      });
    }
    await _initializePlayer();
  }

  Future<void> _playNext() async {
    if (_isSwitchingVideo) return;
    final next = _index + 1;
    if (next < widget.videoList.length) {
      if (mounted) setState(() => _isSwitchingVideo = true);
      await _changeVideoToIndex(next);
      if (mounted) setState(() => _isSwitchingVideo = false);
    }
  }

  Future<void> _playPrevious() async {
    if (_isSwitchingVideo) return;
    final prev = _index - 1;
    if (prev >= 0) {
      if (mounted) setState(() => _isSwitchingVideo = true);
      await _changeVideoToIndex(prev);
      if (mounted) setState(() => _isSwitchingVideo = false);
    }
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });

    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }
  }

  // ================== 重构的手势与滑幅控制 ==================
  void _onPanStart(DragStartDetails d) {
    if (_isSwitchingVideo) return;

    // 初始化锁定状态
    _isSeeking = true;
    _accumulatedDx = 0;
    _startSeekPosition = _position;
    _pendingSeekPosition = _position;

    _gestureStartX = d.globalPosition.dx;
    _gestureStartY = d.globalPosition.dy;
    _isHorizontalDrag = false;
    _isVerticalDrag = false;
    _isBrightnessGesture = false;
    _isVolumeGesture = false;
    _hideTimer?.cancel();

    if (mounted) {
      setState(() {
        _showControls = true;
        _showFeedback = false;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!mounted || _isDisposing || _isSwitchingVideo) return;

    final dx = d.globalPosition.dx - _gestureStartX;
    final dy = d.globalPosition.dy - _gestureStartY;

    if (!_isHorizontalDrag && !_isVerticalDrag) {
      if (dx.abs() > 10) {
        _isHorizontalDrag = true;
      } else if (dy.abs() > 10) {
        _isVerticalDrag = true;
        final screenCenter = MediaQuery.of(context).size.width / 2;
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
      // 累加真正的滑动距离
      _accumulatedDx += d.delta.dx;
      final screenWidth = MediaQuery.of(context).size.width;

      // 【重点突破】：规定无论视频多长，滑满全屏=180秒(3分钟)。
      // 这样就不会出现因为视频 duration 没读出来而滑不动的问题。
      final double deltaSecs = (_accumulatedDx / screenWidth) * 180.0;

      int totalSec = _duration.inSeconds;
      if (totalSec <= 0) totalSec = 86400; // 如果未知总长，提供一个极大的容错范围(24小时)

      int newSec = _startSeekPosition.inSeconds + deltaSecs.toInt();
      newSec = newSec.clamp(0, totalSec);

      setState(() {
        _pendingSeekPosition = Duration(seconds: newSec);
      });

      _showSeekTooltip(deltaSecs.toInt());

    } else if (_isVerticalDrag && !kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      final delta = dy / MediaQuery.of(context).size.height;
      if (_isBrightnessGesture) {
        final newBrightness = (_brightness - delta * 1.5).clamp(0.0, 1.0);
        ScreenBrightness().setScreenBrightness(newBrightness);
        _brightness = newBrightness;
        _feedbackText = '亮度 ${(newBrightness * 100).toInt()}%';
      } else if (_isVolumeGesture) {
        final newVolume = (_volume - delta * 1.5).clamp(0.0, 1.0);
        VolumeController.instance.setVolume(newVolume);
        _volume = newVolume;
        _feedbackText = '音量 ${(newVolume * 100).toInt()}%';
      }
      if (mounted) setState(() => _showFeedback = true);
    }
  }

  void _onPanEnd(DragEndDetails d) async {
    _removeSeekTooltip();

    if (_isHorizontalDrag && _pendingSeekPosition != null) {
      final target = _pendingSeekPosition!;
      await player.seek(target);
    }

    // 【防弹回机制】：延迟 500 毫秒再解除 _isSeeking 锁，给播放器一点缓冲时间
    // 彻底解决松手瞬间进度条弹回起点的问题
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isSeeking = false;
          _pendingSeekPosition = null;
        });
      }
    });

    Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _showFeedback = false);
    });

    if (_showControls) _startHideTimer();
  }

  void _showSeekTooltip(int deltaSec) {
    _removeSeekTooltip();
    _seekTooltipEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).size.height * 0.35,
        left: 0,
        right: 0,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(30)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children:[
                Icon(deltaSec >= 0 ? Icons.fast_forward : Icons.fast_rewind, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  deltaSec >= 0 ? '+$deltaSec秒' : '$deltaSec秒',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
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
    _isDisposing = true;
    _hideTimer?.cancel();
    _periodicSaveTimer?.cancel();
    _connSub.cancel();
    for (var sub in _subscriptions) sub.cancel();

    if (widget.videoList.isNotEmpty && _index >= 0 && _index < widget.videoList.length) {
      final key = widget.videoList[_index].name;
      if (_lastSavedPosition > Duration.zero) {
        ApiService.reportPosition(widget.folderName, key, _lastSavedPosition.inMilliseconds);
      }
    }

    player.dispose();
    _removeSeekTooltip();
    WidgetsBinding.instance.removeObserver(this);

    // 退出页面时，无论刚才处于横竖屏，都强行恢复系统原状
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Widget _buildPlayer() {
    if (_hasError) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children:[
              const Icon(Icons.error_outline, color: Colors.white70, size: 48),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white12),
                icon: const Icon(Icons.refresh),
                label: const Text('播放失败，点击重试'),
                onPressed: _initializePlayer,
              )
            ],
          ),
        ),
      );
    }
    return Video(
      controller: videoController,
      controls: (state) => const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // 允许页面正常关闭，不再强行阻拦返回键
      onWillPop: () async {
        if (_isFullscreen) {
          await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
          await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        }
        return true;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            setState(() => _showControls = !_showControls);
            if (_showControls) _startHideTimer();
          },
          onDoubleTap: _togglePlayPause,
          onPanStart: _onPanStart,
          onPanUpdate: _onPanUpdate,
          onPanEnd: _onPanEnd,
          child: Stack(
            children:[
              Positioned.fill(
                child: Center(child: _buildPlayer()),
              ),

              if (_showFeedback)
                Positioned(
                  top: MediaQuery.of(context).size.height * 0.35,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(30)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children:[
                          Icon(_feedbackIcon, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(_feedbackText, style: const TextStyle(color: Colors.white, fontSize: 18)),
                        ],
                      ),
                    ),
                  ),
                ),

              if (_showControls)
                Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),
              if (_showControls)
                Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomBar()),
              if (_showSpeedSelector)
                Positioned(bottom: 80, left: 0, right: 0, child: Center(child: _buildSpeedSelector())),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      color: Colors.black38,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children:[
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                onPressed: () async {
                  // 【修复点】：点击左上角返回按钮，永远直接退出播放页面
                  if (_isFullscreen) {
                    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
                    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                  }
                  if (mounted) Navigator.pop(context);
                },
              ),
              Expanded(
                child: Text(
                  widget.videoList[_index].name,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      color: Colors.black38,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children:[
              _buildProgressBar(),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children:[
                  IconButton(
                    icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                    onPressed: _togglePlayPause,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous, color: Colors.white),
                    onPressed: _playPrevious,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next, color: Colors.white),
                    onPressed: _playNext,
                  ),
                  IconButton(
                    icon: const Icon(Icons.speed, color: Colors.white),
                    onPressed: () => setState(() => _showSpeedSelector = !_showSpeedSelector),
                  ),
                  IconButton(
                    icon: Icon(_isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen, color: Colors.white),
                    onPressed: _toggleFullscreen,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return Row(
      children:[
        Text(_formatDuration(_pendingSeekPosition ?? _position), style: const TextStyle(color: Colors.white70)),
        Expanded(
          child: Slider(
            value: _duration.inMilliseconds > 0
                ? ((_pendingSeekPosition ?? _position).inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
                : 0,
            onChanged: (value) {
              setState(() {
                _isSeeking = true;
                _pendingSeekPosition = Duration(milliseconds: (value * _duration.inMilliseconds).toInt());
              });
            },
            onChangeEnd: (value) async {
              if (_pendingSeekPosition != null) {
                await player.seek(_pendingSeekPosition!);
                // 拖动底部进度条同样加入 500 毫秒防弹回延迟
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (mounted) {
                    setState(() {
                      _isSeeking = false;
                      _pendingSeekPosition = null;
                    });
                  }
                });
              }
            },
          ),
        ),
        Text(_formatDuration(_duration), style: const TextStyle(color: Colors.white70)),
      ],
    );
  }

  Widget _buildSpeedSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _speeds.map((speed) {
          return TextButton(
            onPressed: () {
              player.setRate(speed);
              setState(() => _showSpeedSelector = false);
            },
            child: Text('$speed×', style: TextStyle(color: player.state.rate == speed ? Colors.blue : Colors.white)),
          );
        }).toList(),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${d.inHours > 0 ? '${d.inHours}:' : ''}$minutes:$seconds';
  }
}