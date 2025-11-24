// lib/screens/assignments/survey_fill_page.dart

import 'package:flutter/material.dart';

import '../../models/api_models.dart';
import '../../widgets/info_chip.dart';
import 'my_assignments_page.dart' show statusLabel;

class SurveyFillPage extends StatelessWidget {
  const SurveyFillPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 从路由参数拿到当前任务
    final a = ModalRoute.of(context)!.settings.arguments as Assignment;
    final theme = Theme.of(context);

    final title = a.storeName != null && a.storeName!.isNotEmpty
        ? '${a.clientName} - ${a.projectName} - ${a.storeName}'
        : '${a.clientName} - ${a.projectName}';

    final storeLine = a.storeAddress != null && a.storeAddress!.isNotEmpty
        ? '门店：${a.storeName ?? ''}（${a.storeAddress}）'
        : (a.storeName != null ? '门店：${a.storeName}' : null);

    return Scaffold(
      appBar: AppBar(
        title: const Text('问卷填写'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 顶部固定信息卡（和 detail 风格保持统一）
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                          InfoChip(
                            icon: Icons.schedule_outlined,
                            text: '创建时间：${a.createdAt}',
                          ),
                          if (storeLine != null)
                            InfoChip(
                              icon: Icons.storefront_outlined,
                              text: storeLine,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const Divider(height: 1),

            // 下面是预留给真正问卷表单的区域
            Expanded(
              child: Center(
                child: Text(
                  '这里将展示真正的问卷表单（后续接入 API / 表单引擎）',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}