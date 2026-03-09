import 'package:flutter/material.dart';
import 'package:deomotwo_video/services/discovery_service.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({Key? key}) : super(key: key);

  @override
  _DiscoverPageState createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final DiscoveryService _discoveryService = DiscoveryService();
  List<DiscoveredServer> _servers = [];
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  @override
  void dispose() {
    _discoveryService.stopDiscovery();
    super.dispose();
  }

  void _startScan() {
    setState(() {
      _isScanning = true;
      _servers = [];
    });

    _discoveryService.startDiscovery(
      onServerFound: (serverMap) {
        setState(() {
          // 将 Map 转换为 DiscoveredServer 对象，并进行类型检查
          try {
            final server = DiscoveredServer(
              name: serverMap['name'] ?? '未知服务器',
              address: serverMap['address'] ?? '',
              port: serverMap['port'] ?? 0,
            );
            if (!_servers.any((s) => s.address == server.address)) {
              _servers.add(server);
            }
          } catch (e) {
            print('Error creating server: $e');
          }
        });
      },
      onScanComplete: () {
        setState(() {
          _isScanning = false;
        });
      },
    );

    // 3秒后停止扫描
    Future.delayed(Duration(seconds: 3), () {
      if (mounted) {
        _discoveryService.stopDiscovery();
        setState(() {
          _isScanning = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("发现"),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _startScan,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "附近的视频服务器",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 16),
            _isScanning
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text("正在搜索附近的服务器..."),
                      ],
                    ),
                  )
                : _servers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.devices,
                              size: 80,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 16),
                            Text("未发现服务器"),
                            SizedBox(height: 8),
                            Text(
                              "请确保服务器已启动并在同一局域网内",
                              style: TextStyle(color: Colors.grey),
                            ),
                            SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _startScan,
                              child: Text("重新搜索"),
                            ),
                          ],
                        ),
                      )
                    : Expanded(
                        child: ListView.builder(
                          itemCount: _servers.length,
                          itemBuilder: (context, index) {
                            final server = _servers[index];
                            return ServerCard(server: server);
                          },
                        ),
                      ),
          ],
        ),
      ),
    );
  }
}

class DiscoveredServer {
  final String name;
  final String address;
  final int port;

  DiscoveredServer({
    required this.name,
    required this.address,
    required this.port,
  });
}

class ServerCard extends StatelessWidget {
  final DiscoveredServer server;

  const ServerCard({Key? key, required this.server}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.computer,
                  color: Theme.of(context).primaryColor,
                  size: 32,
                ),
                SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        server.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "${server.address}:${server.port}",
                        style: TextStyle(
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    // TODO: 连接到服务器
                  },
                  child: Text("连接"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
