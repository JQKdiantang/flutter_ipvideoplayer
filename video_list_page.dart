// lib/pages/video_list_page.dart

import 'package:flutter/material.dart';
import '../models/video_item.dart';
import '../services/api_service.dart';
import '../widgets/video_list_tile.dart';

enum SortField { name, mtime, size }
enum SortOrder { asc, desc }

class VideoListPage extends StatefulWidget {
  final String folderName;
  const VideoListPage({Key? key, required this.folderName}) : super(key: key);

  @override
  State<VideoListPage> createState() => _VideoListPageState();
}

class _VideoListPageState extends State<VideoListPage> {
  late Future<List<VideoItem>> _futureVideos;
  List<VideoItem>? _videos;
  SortField _sortField = SortField.mtime; // 默认按时间
  SortOrder _sortOrder = SortOrder.desc; // 默认降序
  String? _errorMessage;

  // --- [新增] 选择模式的状态 ---
  bool _isSelectionMode = false;
  final Set<VideoItem> _selectedVideos = {};
  // --------------------------

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  void _loadVideos() {
    // 刷新时确保退出选择模式
    if (_isSelectionMode) _disableSelectionMode();

    setState(() {
      _errorMessage = null;
      _futureVideos = ApiService.getVideos(widget.folderName).then((videoItems) {
        _videos = videoItems;
        _applySort();
        return videoItems;
      }).catchError((e) {
        debugPrint('获取视频列表异常: $e');
        setState(() {
          _videos = [];
          _errorMessage = e.toString();
        });
        throw e;
      });
    });
  }

  // --- [新增] 选择模式的逻辑方法 ---

  void _enableSelectionMode(VideoItem video) {
    setState(() {
      _isSelectionMode = true;
      _selectedVideos.add(video);
    });
  }

  void _disableSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedVideos.clear();
    });
  }

  void _toggleSelection(VideoItem video) {
    setState(() {
      if (_selectedVideos.contains(video)) {
        _selectedVideos.remove(video);
      } else {
        _selectedVideos.add(video);
      }
      // 如果所有项都取消勾选了，自动退出选择模式
      if (_selectedVideos.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedVideos.length == _videos?.length) {
        _selectedVideos.clear(); // 如果已全选，则取消全选
      } else {
        _selectedVideos.addAll(_videos ?? []);
      }
    });
  }

  Future<void> _handleDeleteSelected() async {
    final count = _selectedVideos.length;
    if (count == 0) return;

    // 弹出确认对话框，让用户选择删除方式
    final deleteMode = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('您确定要删除这 $count 个视频吗?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(null), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.of(context).pop('trash'), child: const Text('移至回收站')),
          TextButton(
            onPressed: () => Navigator.of(context).pop('permanent'),
            child: Text('永久删除', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );

    if (deleteMode == null) return; // 用户点击了取消

    final isPermanent = deleteMode == 'permanent';
    final fileNames = _selectedVideos.map((v) => v.name).toList();
    final success = await ApiService.deleteVideos(widget.folderName, fileNames, permanent: isPermanent);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(success ? '成功删除 $count 个视频' : '删除失败'),
        backgroundColor: success ? Colors.green : Colors.red,
      ));
    }

    if (success) {
      setState(() {
        _videos?.removeWhere((v) => _selectedVideos.contains(v));
        _disableSelectionMode();
      });
    }
  }
  // ---------------------------------

  void _applySort() {
    if (_videos == null) return;
    _videos!.sort((a, b) {
      int cmp = 0;
      switch (_sortField) {
        case SortField.name: cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase()); break;
        case SortField.mtime: cmp = a.mtime.compareTo(b.mtime); break;
        case SortField.size: cmp = a.sizeMb.compareTo(b.sizeMb); break;
      }
      if (_sortOrder == SortOrder.desc) cmp = -cmp;
      return cmp;
    });
    setState(() {});
  }

  void _onSortSelected(SortField field) {
    setState(() {
      if (_sortField == field) {
        _sortOrder = (_sortOrder == SortOrder.asc) ? SortOrder.desc : SortOrder.asc;
      } else {
        _sortField = field;
        _sortOrder = SortOrder.asc;
      }
      _applySort();
    });
  }

  void _navigateToPlayer(int index) {
    Navigator.pushNamed(
      context,
      '/player',
      arguments: {
        'videoList': _videos,
        'initialIndex': index,
        'folderName': widget.folderName,
      },
    );
  }

  // [修改] 动态构建 AppBar
  AppBar _buildAppBar() {
    if (_isSelectionMode) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _disableSelectionMode,
        ),
        title: Text('已选择 ${_selectedVideos.length} 项'),
        actions: [
          IconButton(
            icon: Icon(
                _selectedVideos.length == _videos?.length
                    ? Icons.deselect
                    : Icons.select_all
            ),
            onPressed: _selectAll,
            tooltip: '全选/取消全选',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _handleDeleteSelected,
            tooltip: '删除所选项',
          ),
        ],
      );
    } else {
      return AppBar(
        title: Text(widget.folderName),
        actions: [
          // 搜索功能暂时保持原样
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => showSearch(context: context, delegate: VideoSearchDelegate(widget.folderName, _videos ?? [])),
          ),
          PopupMenuButton<SortField>(
            onSelected: _onSortSelected,
            itemBuilder: (context) => <PopupMenuEntry<SortField>>[
              PopupMenuItem(value: SortField.name, child: Text('按名称 ${_sortField == SortField.name ? (_sortOrder == SortOrder.asc ? '↑' : '↓') : ''}')),
              PopupMenuItem(value: SortField.mtime, child: Text('按时间 ${_sortField == SortField.mtime ? (_sortOrder == SortOrder.asc ? '↑' : '↓') : ''}')),
              PopupMenuItem(value: SortField.size, child: Text('按大小 ${_sortField == SortField.size ? (_sortOrder == SortOrder.asc ? '↑' : '↓') : ''}')),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadVideos,
          ),
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isSelectionMode) {
          _disableSelectionMode();
          return false; // 拦截返回事件，不退出页面
        }
        return true; // 正常退出页面
      },
      child: Scaffold(
        appBar: _buildAppBar(),
        body: FutureBuilder<List<VideoItem>>(
          future: _futureVideos,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done && _videos == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || _errorMessage != null) {
              return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text('加载失败: ${_errorMessage ?? snapshot.error}', textAlign: TextAlign.center),
                ),
                const SizedBox(height: 8),
                ElevatedButton(onPressed: _loadVideos, child: const Text('重试')),
              ]));
            }
            final videos = _videos ?? [];
            if (videos.isEmpty) {
              return const Center(child: Text('暂无视频'));
            }

            return ListView.builder(
              itemCount: videos.length,
              itemBuilder: (context, index) {
                final video = videos[index];
                return VideoListTile(
                  folder: widget.folderName,
                  video: video,
                  isSelectionMode: _isSelectionMode,
                  isSelected: _selectedVideos.contains(video),
                  // [修改] 定义点击和长按行为
                  onTap: () {
                    if (_isSelectionMode) {
                      _toggleSelection(video);
                    } else {
                      _navigateToPlayer(index);
                    }
                  },
                  onLongPress: () {
                    if (!_isSelectionMode) {
                      _enableSelectionMode(video);
                    }
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// --- VideoSearchDelegate 代码保持不变 ---
// 注意：当前的选择模式不支持在搜索结果页面进行，这是一个更复杂的交互，需要另行设计。
class VideoSearchDelegate extends SearchDelegate<List<VideoItem>> {
  final String folder;
  final List<VideoItem> videos;
  VideoSearchDelegate(this.folder, this.videos);

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return BackButton(onPressed: () => close(context, <VideoItem>[]));
  }

  @override
  Widget buildResults(BuildContext context) {
    final filtered = videos
        .where((v) => v.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
    if (filtered.isEmpty) {
      return Center(child: Text('未找到 "$query"'));
    }
    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final video = filtered[index];
        return VideoListTile( // 这里使用的是非选择模式的 Tile
          folder: folder,
          video: video,
          onTap: () {
            close(context, filtered);
            Navigator.pushNamed(
              context,
              '/player',
              arguments: {
                'videoList': filtered,
                'initialIndex': index,
                'folderName': folder
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final filtered = videos
        .where((v) => v.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final video = filtered[index];
        return ListTile(
          title: Text(video.name),
          onTap: () {
            query = video.name;
            showResults(context);
          },
        );
      },
    );
  }
}