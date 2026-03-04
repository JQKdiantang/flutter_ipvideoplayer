import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('隐私政策'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '隐私政策',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).primaryColor,
              ),
            ),
            SizedBox(height: 20),
            Text(
              '更新日期：2026年2月1日',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Flutter Flask Media Client应用（以下简称"本应用"）致力于保护用户的隐私。本隐私政策旨在向您说明本应用如何收集、使用、存储和保护您的个人信息，以及您享有的相关权利。请您仔细阅读本隐私政策的全部内容。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '一、我们收集的信息',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              '1.1 本应用不会主动收集您的个人信息，如姓名、电话号码、电子邮件地址等。\n1.2 为了提供更好的服务，本应用可能会收集以下非个人信息：\n   (1) 设备信息：如设备型号、操作系统版本、设备标识符等；\n   (2) 使用信息：如应用的使用时间、使用频率、功能使用情况等；\n   (3) 网络信息：如IP地址、网络类型、网络状态等。\n1.3 本应用不会收集、存储或传输您的视频文件内容。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '二、信息的使用',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              '2.1 本应用收集的非个人信息仅用于以下目的：\n   (1) 改进应用性能和用户体验；\n   (2) 排查和解决应用运行中的问题；\n   (3) 统计应用的使用情况，为未来的功能开发提供参考。\n2.2 本应用不会将收集的信息用于其他目的，也不会将其与您的个人身份相关联。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '三、信息的存储和保护',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              '3.1 本应用收集的信息仅存储在您的设备本地，不会上传到任何服务器。\n3.2 本应用采取了合理的技术措施来保护您的信息安全，防止信息丢失、被滥用或被未授权访问。\n3.3 您可以通过卸载本应用来删除所有存储在您设备上的相关信息。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '四、信息的共享',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              '4.1 本应用不会向任何第三方共享、出售、出租或交易您的信息。\n4.2 在以下情况下，本应用可能会披露您的信息：\n   (1) 获得您的明确同意；\n   (2) 遵守法律法规的要求；\n   (3) 保护本应用的合法权益；\n   (4) 保护用户或他人的人身安全和财产安全。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '五、第三方服务',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              '5.1 本应用可能会集成第三方服务或使用第三方库，这些第三方服务可能会有自己的隐私政策。\n5.2 本应用不对第三方服务的隐私政策负责，建议您在使用相关服务前阅读其隐私政策。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '六、用户权利',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              '6.1 您有权访问、修改或删除本应用存储在您设备上的信息。\n6.2 您有权拒绝本应用收集某些非个人信息，但这可能会影响应用的部分功能。\n6.3 您有权随时卸载本应用，停止使用我们的服务。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '七、隐私政策的更新',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              '7.1 本应用可能会根据法律法规的变化或业务发展的需要，随时更新本隐私政策。\n7.2 更新后的隐私政策将在本应用中公布，您应及时查阅。\n7.3 如您继续使用本应用，即表示您已接受更新后的隐私政策。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '八、联系我们',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              '8.1 如您对本隐私政策有任何疑问或建议，您可以通过以下方式联系我们：\n   - 电子邮件：support@flutterflaskmedia.com\n   - 应用内反馈：通过"我的"页面的反馈功能',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '九、其他条款',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              '9.1 本隐私政策构成您与本应用之间关于隐私保护的完整协议，取代之前的所有口头或书面协议。\n9.2 如本隐私政策的任何条款被认定为无效或不可执行，不影响其他条款的效力。\n9.3 本应用未行使或执行本隐私政策的任何权利或规定，不构成对该权利或规定的放弃。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
