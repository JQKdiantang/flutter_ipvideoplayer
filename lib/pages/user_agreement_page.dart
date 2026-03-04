import 'package:flutter/material.dart';

class UserAgreementPage extends StatelessWidget {
  const UserAgreementPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('用户协议'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '用户协议',
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
              '欢迎使用Flutter Flask Media Client应用（以下简称"本应用"）。本协议是您与本应用之间关于使用本应用的权利义务的法律协议。请您仔细阅读本协议的全部内容，特别是涉及您重大权益的条款，如免责条款、争议解决条款等。您点击"同意"或开始使用本应用，即表示您已阅读并同意受本协议的约束。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '一、协议的接受',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              '1.1 您在使用本应用前，应充分阅读、理解本协议各条款内容，特别是关于本应用的权利、义务、免责条款等。\n1.2 您通过点击"同意"按钮或其他类似方式，或通过访问、使用本应用，即表示您已完全理解并接受本协议的全部内容。\n1.3 如您不同意本协议的任何条款，您应立即停止注册、登录或使用本应用。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '二、用户账号',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              '2.1 您在使用本应用时，可能需要注册并创建账号。您应提供真实、准确、完整的个人信息，并在信息变更时及时更新。\n2.2 您应妥善保管您的账号及密码，对使用您账号进行的所有操作负全部责任。\n2.3 如发现账号被他人非法使用，您应立即通知本应用。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '三、用户行为规范',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              '3.1 您在使用本应用时，应遵守中华人民共和国法律法规及相关国际公约。\n3.2 您不得利用本应用从事以下行为：\n   (1) 违反宪法确定的基本原则；\n   (2) 危害国家安全，泄露国家秘密，颠覆国家政权，破坏国家统一；\n   (3) 损害国家荣誉和利益；\n   (4) 煽动民族仇恨、民族歧视，破坏民族团结；\n   (5) 破坏国家宗教政策，宣扬邪教和封建迷信；\n   (6) 散布谣言，扰乱社会秩序，破坏社会稳定；\n   (7) 散布淫秽、色情、赌博、暴力、恐怖或教唆犯罪；\n   (8) 侮辱或诽谤他人，侵害他人合法权益；\n   (9) 违反法律法规、社会公德、公序良俗的其他内容。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '四、知识产权',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              '4.1 本应用及其相关的所有内容（包括但不限于文字、图片、音频、视频、软件、程序、图标等）的知识产权归本应用所有。\n4.2 未经本应用书面许可，您不得对本应用进行反向工程、反向编译、反向汇编或其他类似行为。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '五、免责声明',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              '5.1 本应用不对因网络故障、系统故障、自然灾害等不可抗力因素导致的服务中断或数据丢失承担责任。\n5.2 本应用不对用户因使用本应用而产生的任何间接损失、附带损失、惩罚性赔偿或特殊损失承担责任。\n5.3 本应用仅提供视频播放功能，不对视频内容的合法性、真实性、准确性负责。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '六、协议的修改',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              '6.1 本应用有权根据法律法规的变化或业务发展的需要，随时修改本协议。\n6.2 修改后的协议将在本应用中公布，您应及时查阅。\n6.3 如您继续使用本应用，即表示您已接受修改后的协议。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '七、协议的终止',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              '7.1 如您违反本协议的任何条款，本应用有权立即终止您对本应用的使用权限。\n7.2 本应用有权在必要时终止本协议，并停止提供相关服务。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 20),
            Text(
              '八、争议解决',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 10),
            Text(
              '8.1 本协议的订立、执行、解释及争议的解决均适用中华人民共和国法律。\n8.2 如就本协议发生任何争议，双方应首先通过友好协商解决；协商不成的，任何一方均有权向有管辖权的人民法院提起诉讼。',
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
              '9.1 本协议构成您与本应用之间关于使用本应用的完整协议，取代之前的所有口头或书面协议。\n9.2 如本协议的任何条款被认定为无效或不可执行，不影响其他条款的效力。\n9.3 本应用未行使或执行本协议的任何权利或规定，不构成对该权利或规定的放弃。',
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
