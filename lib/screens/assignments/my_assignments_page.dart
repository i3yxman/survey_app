// lib/screens/assignments/my_assignments_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/api_models.dart';
import '../../providers/assignment_provider.dart';
import '../../services/api_service.dart';

/// 把后端的状态英文码映射成前端展示用的中文文案
String statusLabel(String status) {
  switch (status) {
    case 'pending':
      return '未开始';
    case 'draft':
      return '草稿';
    case 'submitted':
      return '已提交';
    case 'reviewed':
      return '已审核';
    default:
      return status;
  }
}

class MyAssignmentsPage extends StatefulWidget {
  const MyAssignmentsPage({super.key});

  @override
  State<MyAssignmentsPage> createState() => _MyAssignmentsPageState();
}

class _MyAssignmentsPageState extends State<MyAssignmentsPage> {
  @override
  void initState() {
    super.initState();
    // 首帧后拉取一次列表
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AssignmentProvider>().loadAssignments();
    });
  }

  Future<void> _refresh() async {
    await context.read<AssignmentProvider>().loadAssignments();
  }

  Future<void> _handleCancelAssignment(Assignment assignment) async {
    final provider = context.read<AssignmentProvider>();

    try {
      // 第一步：confirm = false，拿预览
      final preview = await provider.cancelAssignment(
        assignmentId: assignment.id,
        confirm: false,
      );

      // 如果不需要确认，直接提示并刷新
      if (!preview.confirmRequired) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(preview.detail)),
        );
        await _refresh();
        return;
      }

      // 需要确认：弹对话框
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('确认取消任务'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(preview.detail),
                if (preview.rule != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    preview.rule!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('保留任务'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('确认取消'),
              ),
            ],
          );
        },
      );

      if (confirmed != true) {
        return;
      }

      // 第二步：confirm = true，真正取消
      final result = await provider.cancelAssignment(
        assignmentId: assignment.id,
        confirm: true,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.detail)),
      );
      await _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('取消任务失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AssignmentProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && provider.assignments.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.error != null && provider.assignments.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '加载任务失败：${provider.error}',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _refresh,
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          );
        }

        final items = provider.assignments;

        if (items.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              children: const [
                SizedBox(height: 200),
                Center(child: Text('当前没有任务')),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final a = items[index];

              final title = a.storeName != null && a.storeName!.isNotEmpty
                  ? '${a.clientName} - ${a.projectName} - ${a.storeName}'
                  : '${a.clientName} - ${a.projectName}';

              return Card(
                margin:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: ListTile(
                  title: Text(title),
                  subtitle: Text(
                    [
                      a.questionnaireTitle,
                      '状态：${statusLabel(a.status)}',
                      '创建时间：${a.createdAt}',
                    ].join('\n'),
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    icon: const Icon(Icons.cancel_outlined, size: 20),
                    tooltip: '取消任务',
                    onPressed: (a.status == 'submitted' ||
                            a.status == 'reviewed')
                        ? null
                        : () => _handleCancelAssignment(a),
                  ),
                  onTap: () {
                    // 这里先保留一个占位点击逻辑，你后面可以改成跳转详情页
                    // Navigator.pushNamed(context, '/assignment-detail', arguments: a);
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}