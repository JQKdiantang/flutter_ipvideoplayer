// lib/services/api_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/video_item.dart';
import 'dart:io'; // 用于 SocketException
import 'dart:async'; // 用于 TimeoutException
import '../models/folder_model.dart';

class ApiService {
  static String baseUrl = ''; // 例如 "http://192.168.5.7:5000"

  /// 设置 baseUrl，去除末尾斜杠
  static void setBaseUrl(String url) {
    baseUrl = url;
    if (baseUrl.endsWith('/')) {
      baseUrl = baseUrl.substring(0, baseUrl.length - 1);
    }
    print('ApiService: baseUrl 设置为 $baseUrl');
  }

  static String getFoldersUrl() => '$baseUrl/folders';

  static String getVideosUrl(String folder) {
    final encFolder = Uri.encodeComponent(folder);
    return '$baseUrl/videos/$encFolder';
  }

  static String getVideoUrl(String folder, String name) {
    final encFolder = Uri.encodeComponent(folder);
    final parts = name.split('/');
    final encNamePath = parts.map(Uri.encodeComponent).join('/');
    return '$baseUrl/video/$encFolder/$encNamePath';
  }

  static String getCoverUrl(String folder, String name) {
    final encFolder = Uri.encodeComponent(folder);
    final parts = name.split('/');
    final encNamePath = parts.map(Uri.encodeComponent).join('/');
    return '$baseUrl/cover/$encFolder/$encNamePath.jpg';
  }

  /// 获取影视库列表
  static Future<List<Folder>> getFolders() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/folders'));

      if (response.statusCode == 200) {
        final List<dynamic> body = jsonDecode(response.body);
        // 将 JSON 列表转换为 Folder 对象列表
        return body.map((dynamic item) => Folder.fromJson(item)).toList();
      } else {
        throw Exception('Failed to load folders: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error connecting to server: $e');
    }
  }

  /// 获取某目录下的视频列表
  static Future<List<VideoItem>> getVideos(String folder) async {
    final url = getVideosUrl(folder);
    print('ApiService.getVideos: GET $url');
    if (baseUrl.isEmpty) {
      throw Exception("服务器基础 URL 未设置，请先在服务器设置页面输入。");
    }

    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        final List<dynamic> arr = jsonDecode(resp.body);

        List<VideoItem> videoItems = arr.map((item) {
          if (item is Map<String, dynamic>) {
            return VideoItem.fromJson(item);
          } else {
            throw FormatException('ApiService.getVideos: 期望数组元素为 Map，但实际是 ${item.runtimeType}');
          }
        }).toList();
        return videoItems;
      }
      throw Exception('获取视频列表失败: ${resp.statusCode} - ${resp.body}');
    } catch (e) {
      print("ApiService.getVideos 异常: $e");
      throw e;
    }
  }

  /// 可选：搜索接口
  static Future<List<Map<String, dynamic>>> searchVideos(String keyword) async {
    final enc = Uri.encodeQueryComponent(keyword);
    final url = '$baseUrl/search?q=$enc';
    print('ApiService.searchVideos: GET $url');
    if (baseUrl.isEmpty) {
      throw Exception("服务器基础 URL 未设置");
    }
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode == 200) {
      final List<dynamic> arr = jsonDecode(resp.body);
      return arr.cast<Map<String, dynamic>>();
    }
    throw Exception('搜索失败: ${resp.statusCode}');
  }

  /// 获取指定视频的播放进度（毫秒）
  static Future<int?> getPosition(String folder, String path) async {
    final encFolder = Uri.encodeComponent(folder);
    final encPath = path.split('/').map(Uri.encodeComponent).join('/');
    final url = '$baseUrl/position/$encFolder/$encPath';
    print('ApiService.getPosition: GET $url');
    if (baseUrl.isEmpty) {
      throw Exception("服务器基础 URL 未设置");
    }
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      return data['position'] as int?;
    }
    return null; // 无法获取进度
  }

  /// 上报当前播放进度
  static Future<void> reportPosition(String folder, String path, int posMs) async {
    final encFolder = Uri.encodeComponent(folder);
    final encPath = Uri.encodeComponent(path);
    final url = '$baseUrl/progress/$encFolder/$encPath';
    if (baseUrl.isEmpty) {
      print("警告: 服务器基础 URL 未设置，无法上报进度");
      return;
    }
    try {
      await http.post(Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'position': posMs}));
    } catch (e) {
      print("上报播放进度失败: $e");
    }
  }
  static Future<bool> deleteVideos(String folder, List<String> fileNames, {bool permanent = false}) async {
    if (baseUrl.isEmpty) {
      print("错误: 服务器基础 URL 未设置，无法删除视频。");
      return false;
    }
    if (fileNames.isEmpty) {
      return true; // 没有要删除的，直接返回成功
    }

    final url = Uri.parse('$baseUrl/api/delete_files');
    print('ApiService.deleteVideos: POST $url for ${fileNames.length} files.');

    // 构建请求体，现在 files 是一个列表
    final body = jsonEncode({
      'folder': folder,
      'files': fileNames,
      'permanent': permanent,
    });

    final headers = {
      'Content-Type': 'application/json',
      // 'X-Admin-Token': 'YOUR_ADMIN_TOKEN', // 如果需要
    };

    try {
      final response = await http.post(url, headers: headers, body: body)
          .timeout(const Duration(seconds: 60)); // 延长超时以应对批量操作

      if (response.statusCode == 200) {
        print('成功删除 ${fileNames.length} 个文件. Permanent: $permanent');
        return true;
      } else {
        print('删除视频时发生错误. 状态码: ${response.statusCode}, 响应: ${response.body}');
        return false;
      }
    } catch (e) {
      print('删除视频时发生异常: $e');
      return false;
    }
  }
}