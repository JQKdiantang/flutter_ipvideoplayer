// File: models/folder_item.dart
import 'dart:convert';

class FolderItem {
  final String name;
  final int videoCount;

  FolderItem({required this.name, this.videoCount = 0});

  // 从 JSON 解析生成 FolderItem 对象
  factory FolderItem.fromJson(Map<String, dynamic> json) {
    return FolderItem(
      name: json['name'] as String,
      videoCount: json['count'] != null ? json['count'] as int : 0,
    );
  }
}
