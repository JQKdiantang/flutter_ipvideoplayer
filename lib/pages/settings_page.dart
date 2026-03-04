import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 定义一个全局常量，确保在所有文件中使用的键都是同一个
const String PREF_HWDEC_DISABLED = 'pref_hwdec_disabled';

class SettingsPage extends StatefulWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isHwdecDisabled = false;
  late SharedPreferences _prefs;
  bool _isLoading = true; // 用于在加载设置时显示加载动画

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // 从本地存储中异步加载设置值
  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        // 读取设置，如果不存在，默认为 false (即默认开启硬件解码)
        _isHwdecDisabled = _prefs.getBool(PREF_HWDEC_DISABLED) ?? false;
        _isLoading = false; // 加载完成，隐藏加载动画
      });
    }
  }

  // 异步保存设置值
  Future<void> _saveHwdecSetting(bool newValue) async {
    setState(() {
      _isHwdecDisabled = newValue;
    });
    await _prefs.setBool(PREF_HWDEC_DISABLED, newValue);

    // 给用户一个即时反馈
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("设置已保存，将在下次播放视频时生效"),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("设置"),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator()) // 正在加载设置时显示
          : ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              "播放设置",
              style: TextStyle(
                color: Theme.of(context).primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          SwitchListTile(
            title: Text("兼容模式 (软件解码)"),
            subtitle: Text("如果遇到视频播放卡顿、无声或花屏，请尝试开启此项。"),
            value: _isHwdecDisabled,
            onChanged: _saveHwdecSetting, // 当开关变化时，调用保存方法
          ),
          Divider(),
          // 您未来可以在这里添加更多设置，比如“文件夹直接播放模式”的开关
        ],
      ),
    );
  }
}