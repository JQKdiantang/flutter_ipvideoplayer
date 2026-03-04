// lib/models/video_item.dart

class VideoItem {
  final String folder; // API 返回的数据中没有，设为空字符串
  final String name;
  final DateTime mtime;
  final double sizeMb;

  VideoItem({
    required this.folder,
    required this.name,
    required this.mtime,
    required this.sizeMb,
  });

  // fromJson 构造函数，根据你提供的数据格式解析
  factory VideoItem.fromJson(Map<String, dynamic> json) {
    return VideoItem(
      folder: '', // API 没有返回 folder，所以这里设为空
      name: json['name'] ?? '',
      // 解析 mtime 字符串为 DateTime 对象
      mtime: DateTime.parse(json['mtime'] ?? DateTime.now().toIso8601String()),
      // size_mb 在 JSON 中是 snake_case，在 Dart 中是 camelCase
      sizeMb: (json['size_mb'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  String toString() {
    return 'VideoItem(folder: $folder, name: $name, mtime: $mtime, sizeMb: $sizeMb)';
  }
}