// lib/screens/job_postings/job_postings_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/api_models.dart';
import '../../providers/job_postings_provider.dart';
import '../../services/api_service.dart';

class JobPostingsPage extends StatefulWidget {
  const JobPostingsPage({super.key});

  @override
  State<JobPostingsPage> createState() => _JobPostingsPageState();
}

class _JobPostingsPageState extends State<JobPostingsPage> {
  @override
  void initState() {
    super.initState();
    // 首帧后加载任务大厅
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<JobPostingsProvider>().loadJobPostings();
    });
  }

  Future<void> _refresh() async {
    await context.read<JobPostingsProvider>().loadJobPostings();
  }

  /// 申请任务
  Future<void> _handleApply(JobPosting p) async {
    final provider = context.read<JobPostingsProvider>();

    try {
      await provider.apply(p.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('申请已提交，请等待审核')),
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
        SnackBar(content: Text('申请出错：$e')),
      );
    }
  }

  /// 撤销申请
  Future<void> _handleCancelApply(JobPosting p) async {
    final provider = context.read<JobPostingsProvider>();

    // 先确认一下
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('确认撤销申请'),
          content: const Text('确定要撤销该任务的申请吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('撤销申请'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await provider.cancelApply(p.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('申请已撤回')),
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
        SnackBar(content: Text('撤销出错：$e')),
      );
    }
  }

  /// 根据任务状态决定显示什么按钮/文案
  Widget _buildTrailing(JobPosting p) {
    final isPostingOpen = p.status == 'open';
    final appStatus = p.applicationStatus;

    // 统一按钮区域宽度，保证“申请任务”和“撤销申请”视觉上一致
    const double trailingWidth = 120;

    // 非 open 的任务：统一显示“已关闭”
    if (!isPostingOpen) {
      return const SizedBox(
        width: trailingWidth,
        child: Center(
          child: Text(
            '已关闭',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    // 已申请：两行（已申请 + 撤销申请），整体垂直居中
    if (appStatus == 'applied') {
      return SizedBox(
        width: trailingWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              '已申请',
              style: TextStyle(
                color: Colors.green,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            ElevatedButton(
              onPressed: () => _handleCancelApply(p),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 14),
              ),
              child: const Text('撤销申请'),
            ),
          ],
        ),
      );
    }

    // 可申请：单行按钮，整体垂直居中
    return SizedBox(
      width: trailingWidth,
      child: Center(
        child: ElevatedButton(
          onPressed: () => _handleApply(p),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(fontSize: 14),
          ),
          child: const Text('申请任务'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<JobPostingsProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && provider.jobPostings.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.error != null && provider.jobPostings.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '加载任务大厅失败：${provider.error}',
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

        final items = provider.jobPostings;

        if (items.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              children: const [
                SizedBox(height: 200),
                Center(child: Text('当前没有可申请的任务')),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final p = items[index];

              final title = p.storeName != null && p.storeName!.isNotEmpty
                  ? '${p.clientName} - ${p.projectName} - ${p.storeName}'
                  : '${p.clientName} - ${p.projectName}';

              final storeLine =
                  p.storeAddress != null && p.storeAddress!.isNotEmpty
                      ? '门店：${p.storeName ?? ''}（${p.storeAddress}）'
                      : (p.storeName != null ? '门店：${p.storeName}' : null);

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center, // ⭐ 垂直居中
                    children: [
                      // 左边：标题 + 副标题
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              [
                                p.questionnaireTitle,
                                if (p.description.isNotEmpty) '说明：${p.description}',
                                if (storeLine != null) storeLine,
                                '发布时间：${p.createdAt}',
                              ].join('\n'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 12),

                      // 右边：申请 / 已申请 + 撤销
                      _buildTrailing(p),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}