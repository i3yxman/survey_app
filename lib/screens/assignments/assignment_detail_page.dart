// lib/screens/assignments/assignment_detail_page.dart

// lib/screens/assignments/assignment_detail_page.dart

import 'package:flutter/material.dart';
import 'package:maps_launcher/maps_launcher.dart';

import '../../models/api_models.dart';
import '../../widgets/info_chip.dart';
import 'my_assignments_page.dart' show statusLabel;

import '../../utils/snackbar.dart';

class AssignmentDetailPage extends StatelessWidget {
  const AssignmentDetailPage({super.key});

  /// 主按钮文案：开始 / 继续 / 查看
  String _primaryActionLabel(Assignment a) {
    switch (a.status) {
      case 'pending':
        return '开始填写';
      case 'in_progress':
      case 'draft':
        return '继续填写';
      case 'submitted':
      case 'reviewed':
        return '查看填写';
      case 'cancelled':
        return '已取消';
      default:
        return '开始填写';
    }
  }

  bool _primaryActionEnabled(Assignment a) {
    return a.status != 'cancelled';
  }

  /// 打开地图导航（和列表里的逻辑一致）
  void _launchNav(Assignment a) {
    final lat = a.storeLatitude;
    final lng = a.storeLongitude;
    if (lat == null || lng == null) return;

    final name = a.storeName ?? '门店';
    MapsLauncher.launchCoordinates(lat, lng, name);
  }

  @override
  Widget build(BuildContext context) {
    // 从路由参数拿 Assignment
    final a = ModalRoute.of(context)!.settings.arguments as Assignment;
    final theme = Theme.of(context);

    final title = a.storeName != null && a.storeName!.isNotEmpty
        ? '${a.clientName} - ${a.projectName} - ${a.storeName}'
        : '${a.clientName} - ${a.projectName}';

    final storeLine = a.storeAddress != null && a.storeAddress!.isNotEmpty
        ? '门店：${a.storeName ?? ''}（${a.storeAddress}）'
        : (a.storeName != null ? '门店：${a.storeName}' : null);

    final primaryLabel = _primaryActionLabel(a);
    final primaryEnabled = _primaryActionEnabled(a);

    return Scaffold(
      appBar: AppBar(title: const Text('问卷填写')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶部信息卡，风格和列表保持一致
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 左侧竖条
                      Container(
                        width: 4,
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              theme.colorScheme.primary,
                              theme.colorScheme.secondary,
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 中间信息
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: theme.textTheme.titleMedium,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              a.questionnaireTitle ?? '',
                              style: theme.textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                InfoChip(
                                  icon: Icons.info_outline,
                                  text: '状态：${statusLabel(a.status)}',
                                ),
                                if (storeLine != null)
                                  InfoChip(
                                    icon: Icons.storefront_outlined,
                                    text: storeLine,
                                  ),
                                InfoChip(
                                  icon: Icons.schedule_outlined,
                                  text: '创建时间：${a.createdAt}',
                                ),
                                if (a.storeLatitude != null &&
                                    a.storeLongitude != null)
                                  InfoChip(
                                    icon: Icons.navigation_outlined,
                                    text: '导航',
                                    onTap: () => _launchNav(a),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // 主操作按钮：开始 / 继续 / 查看 填写
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: primaryEnabled
                          ? () {
                              // TODO: 这里以后接真正的问卷表单页路由
                              // Navigator.pushNamed(
                              //   context,
                              //   '/survey-fill',
                              //   arguments: a,
                              // );

                              // 现在先用统一封装的错误提示（占位）
                              showErrorSnackBar(context, '问卷表单页还没接好（占位按钮）');
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      child: Text(primaryLabel),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 下面预留给真正的问卷内容
              Expanded(
                child: Center(
                  child: Text(
                    '这里预留给问卷题目列表（后续接入）',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
