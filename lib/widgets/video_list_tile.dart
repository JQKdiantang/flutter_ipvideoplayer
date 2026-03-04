// lib/widgets/video_list_tile.dart

import 'package:flutter/material.dart';
import '../models/video_item.dart';
import '../services/api_service.dart';

class VideoListTile extends StatelessWidget {
  final String folder;
  final VideoItem video;
  final VoidCallback onTap;

  // [新增] 用于选择模式的参数
  final VoidCallback? onLongPress;
  final bool isSelectionMode;
  final bool isSelected;

  const VideoListTile({
    Key? key,
    required this.folder,
    required this.video,
    required this.onTap,
    // [修改] 构造函数
    this.onLongPress,
    this.isSelectionMode = false,
    this.isSelected = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final coverUrl = ApiService.getCoverUrl(folder, video.name);

    // 根据是否选中，改变背景色
    final tileColor = isSelected
        ? Theme.of(context).primaryColor.withOpacity(0.2)
        : null;

    return ListTile(
      tileColor: tileColor,
      onTap: onTap,
      onLongPress: onLongPress,
      // [修改] leading 部分，根据选择模式显示复选框或封面
      leading: SizedBox(
        width: 60,
        height: 60,
        child: isSelectionMode
            ? Center(
          child: Icon(
            isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
            color: Theme.of(context).primaryColor,
          ),
        )
            : ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.network(
            coverUrl,
            width: 60,
            height: 60,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) {
              return Container(
                width: 60,
                height: 60,
                color: Colors.grey[300],
                child: const Icon(Icons.movie, color: Colors.grey),
              );
            },
          ),
        ),
      ),
      title: Text(
        video.name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('${video.sizeMb} MB    ${video.mtime}'),
    );
  }
}