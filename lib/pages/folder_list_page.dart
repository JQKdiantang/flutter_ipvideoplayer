// lib/pages/folder_list_page.dart

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/folder_model.dart'; // 1. 引入模型

class FolderListPage extends StatefulWidget {
  const FolderListPage({Key? key}) : super(key: key);

  @override
  State<FolderListPage> createState() => _FolderListPageState();
}

class _FolderListPageState extends State<FolderListPage> {
  // 2. 将 Future<List<String>> 改为 Future<List<Folder>>
  late Future<List<Folder>> _futureFolders;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  void _loadFolders() {
    setState(() {
      _futureFolders = ApiService.getFolders();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('影视库列表'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFolders,
          ),
        ],
      ),
      // 3. 修改 Builder 的泛型类型
      body: FutureBuilder<List<Folder>>(
        future: _futureFolders,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('加载失败: ${snapshot.error}'),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _loadFolders,
                    child: const Text('重试'),
                  ),
                ],
              ),
            );
          }
          final folders = snapshot.data ?? [];
          if (folders.isEmpty) {
            return const Center(child: Text('暂无已注册影视库'));
          }
          return ListView.builder(
            itemCount: folders.length,
            itemBuilder: (context, index) {
              final folder = folders[index];
              return ListTile(
                // 4. 使用 folder.name 来显示名称
                title: Text(folder.name),
                // 可选：显示路径 subtitle: Text(folder.path),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pushNamed(
                    context,
                    '/videos',
                    // 5. 这里非常重要：
                    // 因为你的后端路由是 /videos/:name (通过名字查找)，
                    // 所以这里只传 name 字符串。
                    // 如果下一页已经改写为接收 Folder 对象，则传 folder。
                    arguments: folder.name,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}