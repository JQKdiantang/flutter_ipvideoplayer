import 'package:flutter/material.dart';
import 'package:deomotwo_video/pages/settings_page.dart'; // 稍后我们会创建这个文件
import 'package:deomotwo_video/pages/user_agreement_page.dart';
import 'package:deomotwo_video/pages/privacy_policy_page.dart';
import 'package:deomotwo_video/pages/about_app_page.dart';
import 'package:deomotwo_video/pages/user_info_page.dart';

class MyPage extends StatelessWidget {
  const MyPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("我的"),
      ),
      body: ListView(
        children: [
          // 这里可以放一些用户头像、昵称等信息
          ListTile(
            leading: Icon(Icons.person),
            title: Text("用户信息"),
            trailing: Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => UserInfoPage()),
              );
            },
          ),

          Divider(), // 分割线

          // --- 这是我们增加的设置入口 ---
          ListTile(
            leading: Icon(Icons.settings),
            title: Text("设置"),
            trailing: Icon(Icons.chevron_right), // 右侧小箭头
            onTap: () {
              // 点击后，导航到设置页面
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => SettingsPage()),
              );
            },
          ),

          ListTile(
            leading: Icon(Icons.info_outline),
            title: Text("关于应用"),
            trailing: Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => AboutAppPage()),
              );
            },
          ),

          Divider(), // 分割线

          // --- 法律信息 --- 
          ListTile(
            leading: Icon(Icons.description),
            title: Text("用户协议"),
            trailing: Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => UserAgreementPage()),
              );
            },
          ),

          ListTile(
            leading: Icon(Icons.lock),
            title: Text("隐私政策"),
            trailing: Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => PrivacyPolicyPage()),
              );
            },
          ),
        ],
      ),
    );
  }
}