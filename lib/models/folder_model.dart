// lib/models/folder_model.dart
//目录返回数据类型
class Folder {
  final int id;
  final String name;
  final String path;

  Folder({
    required this.id,
    required this.name,
    required this.path,
  });

  // 工厂构造函数，用于从 JSON 创建对象
  factory Folder.fromJson(Map<String, dynamic> json) {
    return Folder(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      path: json['path'] ?? '',
    );
  }
}