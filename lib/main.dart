// lib/main.dart

import 'package:flutter/material.dart';
import 'pages/video_player_page.dart';
import 'pages/video_list_page.dart';
import 'pages/server_input_page.dart'; // <-- 要是包含 UDP 发现逻辑的文件
import 'pages/folder_list_page.dart';
import 'models/video_item.dart';
import 'package:media_kit/media_kit.dart';
import 'pages/my_page.dart';
import 'pages/discover_page.dart';


void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized(); // 必须添加
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Flask Media Client',
      themeMode: ThemeMode.system,
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.white,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.black,
      ),
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (_) => const MainNavigation(),
      },
      onGenerateRoute: (settings) {
        final args = settings.arguments;
        switch (settings.name) {
          case '/':
            return null;
          case '/folders':
            return MaterialPageRoute(builder: (_) => const FolderListPage());
          case '/videos':
            if (args is String) {
              return MaterialPageRoute(
                builder: (_) => VideoListPage(folderName: args),
              );
            }
            return _errorRoute('未提供文件夹名称');
          case '/player':
            if (args is Map<String, dynamic>) {
              final videoList = args['videoList'];
              final initialIndex = args['initialIndex'];
              final folderName = args['folderName'];
              if (videoList is List<VideoItem> && initialIndex is int && folderName is String) {
                return MaterialPageRoute(
                  builder: (_) => VideoPlayerPage(
                    videoList: videoList,
                    initialIndex: initialIndex,
                    folderName: folderName,
                  ),
                );
              }
              return _errorRoute('播放参数类型错误');
            }
            return _errorRoute('未提供播放参数');
          default:
            return _errorRoute('未知的路由: ${settings.name}');
        }
      },
    );
  }

  Route<dynamic> _errorRoute(String msg) {
    return MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('错误')),
        body: Center(child: Text(msg)),
      ),
    );
  }
}

/// 主导航页面（底部导航）
class MainNavigation extends StatefulWidget {
  const MainNavigation({Key? key}) : super(key: key);

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 使用 IndexedStack 保持各页面状态（特别是 ServerInputPage 的发现 socket）
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // 把 active 状态传给 ServerInputPage（只有首页可见时才会自动 discovery）
          ServerInputPage(active: _currentIndex == 0),
          const DiscoverPage(), // 发现页
          const MyPage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '首页'),
          BottomNavigationBarItem(icon: Icon(Icons.explore), label: '发现'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: '我的'),
        ],
      ),
    );
  }
}
