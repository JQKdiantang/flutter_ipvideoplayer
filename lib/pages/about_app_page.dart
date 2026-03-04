import 'package:flutter/material.dart';

class AboutAppPage extends StatelessWidget {
  const AboutAppPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("关于应用"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: 40),
            // 应用图标
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Center(
                child: Icon(
                  Icons.play_circle_fill,
                  size: 70,
                  color: Colors.white,
                ),
              ),
            ),
            SizedBox(height: 20),
            // 应用名称
            Text(
              "Flutter Flask Media Client",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
            SizedBox(height: 10),
            // 版本号
            Text(
              "版本 1.0.0",
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 40),
            // 应用简介
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "Flutter Flask Media Client是一款功能强大的视频播放应用，支持从Flask服务器或本地网络播放视频。应用采用现代化的界面设计，提供流畅的视频播放体验。",
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: 40),
            // 功能特点
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "功能特点",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 10),
                FeatureItem(
                  icon: Icons.language,
                  title: "网络视频播放",
                  description: "支持从Flask服务器或本地网络播放视频",
                ),
                SizedBox(height: 10),
                FeatureItem(
                  icon: Icons.fullscreen,
                  title: "全屏播放",
                  description: "支持横屏全屏播放，提供沉浸式体验",
                ),
                SizedBox(height: 10),
                FeatureItem(
                  icon: Icons.playlist_play,
                  title: "视频列表",
                  description: "支持浏览和选择视频列表中的视频",
                ),
                SizedBox(height: 10),
                FeatureItem(
                  icon: Icons.settings,
                  title: "播放设置",
                  description: "支持硬件解码设置，优化播放性能",
                ),
              ],
            ),
            SizedBox(height: 40),
            // 版权信息
            Text(
              "© 2026 Flutter Flask Media Client",
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 20),
            Text(
              "保留所有权利",
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

class FeatureItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const FeatureItem({
    Key? key,
    required this.icon,
    required this.title,
    required this.description,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: Icon(
              icon,
              size: 20,
              color: Theme.of(context).primaryColor,
            ),
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                description,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
