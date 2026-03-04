// lib/pages/server_input_page.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io; // 使用 'io' 前缀以保持代码清晰
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

const int DISCOVER_PORT = 9999;
const String DISCOVER_REQUEST_MESSAGE = "DISCOVER_REQUEST";
const String MULTICAST_CHANNEL = 'app.multicast_lock';

class ServerInputPage extends StatefulWidget {
  final bool active;
  const ServerInputPage({Key? key, this.active = true}) : super(key: key);

  @override
  State<ServerInputPage> createState() => _ServerInputPageState();
}

class _ServerInputPageState extends State<ServerInputPage> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  // 发现功能相关的状态
  bool _isScanning = false;
  io.RawDatagramSocket? _udpSocket;
  StreamSubscription<io.RawSocketEvent>? _socketSubscription;
  Timer? _sendTimer;
  final List<Map<String, dynamic>> _discovered = [];

  // 可选：用于在 Android 上请求 MulticastLock (需要原生端实现)
  final MethodChannel _mcChannel = const MethodChannel(MULTICAST_CHANNEL);

  @override
  void initState() {
    super.initState();
    _loadSavedServer();
    // 尝试获取多播锁 (如果原生端未实现，则此操作无效)
    _acquireMulticastLockSafely();
    if (widget.active) {
      _startDiscovery();
    }
  }

  @override
  void didUpdateWidget(covariant ServerInputPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      if (widget.active) {
        _startDiscovery();
      } else {
        _stopDiscovery();
      }
    }
  }

  Future<void> _acquireMulticastLockSafely() async {
    // 在 Android 上，这对于在屏幕可能关闭时接收UDP数据包至关重要。
    if (!io.Platform.isAndroid) return;
    try {
      await _mcChannel.invokeMethod('acquire');
      debugPrint('多播锁(MulticastLock): 已调用原生端 acquire 方法。');
    } catch (e) {
      debugPrint('多播锁(MulticastLock)在原生端不可用或失败: $e。在 Android 上的 UDP 发现功能可能会变得不可靠。');
    }
  }

  Future<void> _releaseMulticastLockSafely() async {
    if (!io.Platform.isAndroid) return;
    try {
      await _mcChannel.invokeMethod('release');
      debugPrint('多播锁(MulticastLock): 已调用原生端 release 方法。');
    } catch (e) {
      debugPrint('多播锁(MulticastLock)释放不可用或失败: $e');
    }
  }

  Future<void> _loadSavedServer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('server');
      if (saved != null && saved.isNotEmpty) {
        _controller.text = saved;
        ApiService.setBaseUrl(saved);
        // 静默测试连接
        //_testConnection(auto: true);
        debugPrint('检测到已保存服务器地址 (不自动连接): $saved');
      }
    } catch (e) {
      debugPrint('加载已保存的服务器地址时出错: $e');
    }
  }

  Future<void> _startDiscovery() async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _discovered.clear();
      _errorMessage = null;
    });

    final discoverBytes = utf8.encode(DISCOVER_REQUEST_MESSAGE);

    try {
      // 绑定到 DISCOVER_PORT (9999) - 这是接收广播的关键
      try {
        _udpSocket = await io.RawDatagramSocket.bind(
          io.InternetAddress.anyIPv4,
          DISCOVER_PORT,
          reuseAddress: true,
          reusePort: true, // 在某些平台上可能会抛出异常，下面已处理
        );
      } catch (e) {
        debugPrint('reusePort 不可用或绑定失败: $e - 回退到仅使用 reuseAddress');
        _udpSocket = await io.RawDatagramSocket.bind(
          io.InternetAddress.anyIPv4,
          DISCOVER_PORT,
          reuseAddress: true,
        );
      }

      debugPrint('UDP 绑定成功: ${_udpSocket!.address.address}:${_udpSocket!.port}');
      _udpSocket!.broadcastEnabled = true;

      // 监听传入的数据报
      _socketSubscription = _udpSocket!.listen((event) {
        if (event == io.RawSocketEvent.read) {
          try {
            final dg = _udpSocket!.receive();
            if (dg == null) return;
            final payload = utf8.decode(dg.data).trim();
            debugPrint('收到 UDP 数据: "$payload" 来自 ${dg.address.address}:${dg.port}');
            // 避免处理我们自己发送的广播
            if (dg.address.address != _udpSocket?.address.address) {
              _handleUdpPayload(payload, dg.address.address);
            }
          } catch (e) {
            debugPrint('读取数据报时出错: $e');
          }
        }
      });

      // 立即发送一次发现请求，然后周期性发送
      await _sendDiscoveryOnce(discoverBytes);
      _sendTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        _sendDiscoveryOnce(discoverBytes);
      });

      // 默认扫描30秒
      Future.delayed(const Duration(seconds: 30), () {
        if (mounted && _isScanning) {
          debugPrint('发现超时：停止发现服务。');
          _stopDiscovery();
        }
      });
    } catch (e, st) {
      debugPrint('启动发现服务失败: $e\n$st');
      if (mounted) {
        setState(() {
          _errorMessage = '启动发现服务失败: $e';
          _isScanning = false;
        });
      }
      _stopDiscovery();
    }
  }

  /// [已简化] 此函数现在仅向全局广播地址 '255.255.255.255' 发送发现请求。
  /// 这解决了编译问题，并且在大多数网络中都有效。
  Future<void> _sendDiscoveryOnce(List<int> discoverBytes) async {
    if (_udpSocket == null) return;

    final globalBroadcast = io.InternetAddress('255.255.255.255');

    try {
      _udpSocket!.send(discoverBytes, globalBroadcast, DISCOVER_PORT);
      debugPrint('已发送 DISCOVER -> ${globalBroadcast.address}:$DISCOVER_PORT');
    } catch (e) {
      debugPrint('发送到全局广播地址 ${globalBroadcast.address} 失败: $e');
    }
  }

  void _handleUdpPayload(String payload, String sourceIp) {
    // 期望格式: media_server:PORT 或者 media_server:IP:PORT
    try {
      final parts = payload.split(':');
      if (parts.isNotEmpty && parts[0] == 'media_server') {
        String ip = sourceIp; // 直接信任数据包的源 IP 地址
        int? port;

        if (parts.length >= 2) {
          port = int.tryParse(parts[1].trim());
        }
        // 可选：允许负载内容覆盖IP，例如 "media_server:1.2.3.4:1234"
        if (parts.length >= 3) {
          ip = parts[1].trim();
          port = int.tryParse(parts[2].trim());
        }

        if (ip.isNotEmpty && port != null) {
          final addr = 'http://$ip:$port';
          final exists = _discovered.any((e) => e['address'] == addr);
          if (!exists) {
            if (mounted) {
              setState(() {
                _discovered.add({'address': addr, 'ip': ip, 'port': port, 'time': DateTime.now()});
              });
            }
            debugPrint('已发现并添加服务器: $addr');
          } else {
            // 更新已存在项的时间（最近一次可见时间）
            if (mounted) {
              final idx = _discovered.indexWhere((e) => e['address'] == addr);
              if (idx >= 0) {
                setState(() {
                  _discovered[idx]['time'] = DateTime.now();
                });
              }
            }
          }
          return;
        }
      }
      debugPrint('接收到无法识别的 UDP 负载 (已忽略): $payload');
    } catch (e) {
      debugPrint('解析 UDP 负载时出错: $e');
    }
  }

  void _stopDiscovery() {
    _sendTimer?.cancel();
    _sendTimer = null;
    _socketSubscription?.cancel();
    _socketSubscription = null;
    try {
      _udpSocket?.close();
    } catch (e) {
      debugPrint('关闭 UDP socket 时出错: $e');
    }
    _udpSocket = null;
    // 停止发现时释放多播锁
    _releaseMulticastLockSafely();
    if (mounted) {
      setState(() {
        _isScanning = false;
      });
    }
    debugPrint('发现服务已停止并清理资源。');
  }

  Future<void> _saveAndConnect(String addr) async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('server', addr);
      ApiService.setBaseUrl(addr);
      await _testConnection(auto: false);
    } catch (e) {
      debugPrint('保存并连接时出错: $e');
      if (mounted) setState(() { _errorMessage = '保存或连接失败: $e'; });
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  Future<void> _connectTemporary(String addr) async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      ApiService.setBaseUrl(addr);
      // 为连接测试设置一个合理的超时时间
      await ApiService.getFolders().timeout(const Duration(seconds: 8));
      _stopDiscovery();
      if (mounted) Navigator.pushNamed(context, '/folders');
    } on TimeoutException catch (_) {
      if (mounted) setState(() { _errorMessage = '连接超时'; });
    } catch (e) {
      if (mounted) setState(() { _errorMessage = '连接失败: $e'; });
    } finally {
      if (mounted) setState(() { _isLoading = false; });
    }
  }

  Future<void> _testConnection({bool auto = false}) async {
    if (!mounted) return;
    if (!auto) setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await ApiService.getFolders().timeout(const Duration(seconds: 8));
      _stopDiscovery();
      if (mounted) Navigator.pushNamed(context, '/folders');
    } catch (e) {
      if (!auto && mounted) setState(() { _errorMessage = '连接测试失败: $e'; });
    } finally {
      if (!auto && mounted) setState(() { _isLoading = false; });
    }
  }

  @override
  void dispose() {
    _stopDiscovery();
    _controller.dispose();
    super.dispose();
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s 前';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m 前';
    if (diff.inHours < 24) return '${diff.inHours}h 前';
    return '${diff.inDays}d 前';
  }

  Widget _buildDiscoveredList() {
    if (_isScanning && _discovered.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [CircularProgressIndicator(), SizedBox(height: 16), Text("正在扫描局域网服务器...")])) ,
      );
    }
    if (_discovered.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('未发现可用服务器。'),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: _startDiscovery,
                  child: const Text('重新扫描'),
                )
              ],
            )) ,
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _discovered.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final s = _discovered[index];
        final addr = s['address'] as String;
        final ip = s['ip'] as String? ?? '-';
        final port = s['port']?.toString() ?? '-';
        final time = s['time'] as DateTime? ?? DateTime.now();
        final timeAgo = _timeAgo(time);

        // 点击整行直接临时连接（更符合“点击连接即可”的需求）
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            title: Text(
              addr,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.blue,
                decoration: TextDecoration.underline,
              ),
            ),
            subtitle: Row(
              children: [
                Flexible(
                  child: Text('IP: $ip  •  端口: $port  •  最近: $timeAgo',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ),
              ],
            ),
            // 右侧只保留保存按钮；播放行为由点击整行触发（更直观）
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '保存并连接',
                  icon: const Icon(Icons.save_alt_rounded),
                  onPressed: () => _saveAndConnect(addr),
                ),
              ],
            ),
            onTap: () {
              // 直接临时连接（原来是播放按钮的行为）
              _connectTemporary(addr);
            },
            onLongPress: () {
              // 长按填入输入框，供用户复制/编辑（如果需要）
              setState(() {
                _controller.text = addr;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('服务器地址已填入输入框，长按可复制或编辑')),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('服务器设置'),
        actions: [
          IconButton(
            tooltip: _isScanning ? '停止扫描' : '扫描局域网',
            icon: Icon(_isScanning ? Icons.stop_circle_outlined : Icons.search_rounded),
            onPressed: () {
              if (_isScanning) {
                _stopDiscovery();
              } else {
                _startDiscovery();
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'http://your-server-ip:port',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                ),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12)
                ),
                onPressed: _isLoading ? null : () {
                  final v = _controller.text.trim();
                  if (v.isEmpty) {
                    setState(() { _errorMessage = '请输入服务器地址'; });
                    return;
                  }
                  _saveAndConnect(v);
                },
                child: _isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 3)) : const Text('保存并连接'),
              ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(_errorMessage!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                ),
              const Divider(height: 30),
              const Text("或从局域网发现：", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Expanded(child: _buildDiscoveredList()),
            ],
          ),
        ),
      ),
    );
  }
}
