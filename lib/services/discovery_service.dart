// lib/services/discovery_service.dart

import 'dart:async';
import 'dart:io';

class DiscoveryService {
  RawDatagramSocket? _socket;
  StreamController<String> _controller = StreamController.broadcast();

  /// 广播监听端口
  final int port;

  DiscoveryService({this.port = 9999});

  /// 启动监听。返回一个 Stream<String>，当接收到消息时向外推送 "<ip>:<port>" 字符串。
  Future<Stream<String>> startListening() async {
    // 如果已经在监听，直接返回 stream
    if (_socket != null) {
      return _controller.stream;
    }
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
      _socket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _socket!.receive();
          if (datagram == null) return;
          final msg = String.fromCharCodes(datagram.data).trim();
          // 预期格式: "media_server:<ip>:<port>"
          if (msg.startsWith('media_server:')) {
            final parts = msg.split(':');
            if (parts.length >= 3) {
              final ip = parts[1];
              final portPart = parts[2];
              // 过滤无效
              if (ip.isNotEmpty && portPart.isNotEmpty) {
                final addr = '$ip:$portPart';
                // 推送到 stream
                _controller.add(addr);
              }
            }
          }
        }
      });
      print('DiscoveryService: Listening UDP broadcast on port $port');
    } catch (e) {
      print('DiscoveryService 启动失败: $e');
      // 若失败（如模拟器环境不支持），可以将 _socket 置 null 并外部退回手动输入
      _socket = null;
    }
    return _controller.stream;
  }

  void stop() {
    _socket?.close();
    _socket = null;
    _controller.close();
  }

  /// 启动服务器发现
  void startDiscovery({
    required Function(dynamic) onServerFound,
    required Function() onScanComplete,
  }) {
    // 这里简化实现，实际项目中应该调用 startListening() 并处理流数据
    // 为了测试，我们可以模拟发现一个服务器
    Future.delayed(Duration(seconds: 1), () {
      // 模拟发现一个服务器
      final mockServer = {
        'name': 'Flask Media Server',
        'address': '192.168.1.100',
        'port': 5000,
      };
      onServerFound(mockServer);
      
      // 扫描完成
      Future.delayed(Duration(seconds: 2), () {
        onScanComplete();
      });
    });
  }

  /// 停止服务器发现
  void stopDiscovery() {
    stop();
  }
}
