// lib/screens/assignments/my_assignments_page.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/api_models.dart';
import '../../providers/assignment_provider.dart';
import '../../providers/location_provider.dart'; // ⭐ 新增
import '../../services/api_service.dart';
import '../../widgets/info_chip.dart';
import '../../utils/location_utils.dart';
import '../../utils/snackbar.dart';

/// 把后端的状态英文码映射成前端展示用的中文文案
String statusLabel(String status) {
  switch (status) {
    case 'pending':
      return '未开始';
    case 'in_progress':
      return '进行中';
    case 'draft':
      return '草稿';
    case 'submitted':
      return '已提交';
    case 'reviewed':
      return '已审核';
    case 'cancelled':
      return '已取消';
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
    // 首帧后拉取任务 + 全局定位
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AssignmentProvider>().loadAssignments();
      context.read<LocationProvider>().ensureLocation(); // ⭐ 全局定位
    });
  }

  Future<void> _refresh() async {
    await context.read<AssignmentProvider>().loadAssignments();
    await context.read<LocationProvider>().ensureLocation();
  }

  /// 使用 LocationProvider + utils 统一计算距离
  String? _formatDistance(
    LocationProvider loc,
    double? storeLat,
    double? storeLng,
  ) {
    return formatStoreDistance(loc.position, storeLat, storeLng);
  }

  /// 导航：保持原来的 Apple Maps / Google Maps 逻辑
  Future<void> _launchNavigation(Assignment a) async {
    final lat = a.storeLatitude;
    final lng = a.storeLongitude;
    if (lat == null || lng == null) return;

    final label = a.storeName ?? a.clientName ?? '目的地';
    final encodedLabel = Uri.encodeComponent(label);
    Uri uri;

    if (Platform.isIOS) {
      uri = Uri.parse('http://maps.apple.com/?daddr=$lat,$lng&q=$encodedLabel');
    } else {
      uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng',
      );
    }

    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      showErrorSnackBar(context, '无法打开地图应用');
    }
  }

  Future<void> _handleCancelAssignment(Assignment assignment) async {
    final provider = context.read<AssignmentProvider>();

    try {
      // 第一步：预览
      final preview = await provider.cancelAssignment(
        assignmentId: assignment.id,
        confirm: false,
      );

      if (!preview.confirmRequired) {
        if (!mounted) return;
        showSuccessSnackBar(context, preview.detail);
        await _refresh();
        return;
      }

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
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
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

      // 第二步：真正取消
      final result = await provider.cancelAssignment(
        assignmentId: assignment.id,
        confirm: true,
      );

      if (!mounted) return;
      showSuccessSnackBar(context, result.detail);
      await _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e, fallback: '操作失败，请稍后重试');
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e, fallback: '取消任务失败，请稍后再试');
    }
  }

  // 主按钮文案：开始 / 继续 / 查看
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

  /// 右侧按钮区域：主操作（开始/继续/查看） + 取消任务
  Widget _buildTrailing(Assignment a, {required bool loading}) {
    const trailingWidth = 120.0;

    final status = a.status;
    final canCancel =
        !(status == 'submitted' ||
            status == 'reviewed' ||
            status == 'cancelled');

    final primaryLabel = _primaryActionLabel(a);
    final primaryEnabled = _primaryActionEnabled(a);

    return SizedBox(
      width: trailingWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (!loading && primaryEnabled)
                  ? () async {
                      final needRefresh = await Navigator.pushNamed(
                        context,
                        '/survey-fill',
                        arguments: a,
                      );

                      // ⭐ 如果填写页面告诉我们需要刷新，则重新拉任务
                      if (needRefresh == true) {
                        await _refresh();
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
              ),
              child: Text(primaryLabel, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: (!loading && canCancel)
                ? () => _handleCancelAssignment(a)
                : null,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            child: const Text('取消任务'),
          ),
        ],
      ),
    );
  }

  /// 底部信息：门店 / 创建时间 / 距离 / 导航
  Widget _buildBottomMeta(Assignment a, LocationProvider loc) {
    final storeLine = a.storeAddress != null && a.storeAddress!.isNotEmpty
        ? '门店：${a.storeName ?? ''}（${a.storeAddress}）'
        : (a.storeName != null ? '门店：${a.storeName}' : null);

    final distanceText = _formatDistance(
      loc,
      a.storeLatitude,
      a.storeLongitude,
    );

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        if (storeLine != null)
          InfoChip(icon: Icons.storefront_outlined, text: storeLine),
        InfoChip(icon: Icons.schedule_outlined, text: '创建时间：${a.createdAt}'),
        if (distanceText != null)
          InfoChip(icon: Icons.place_outlined, text: '距离门店 $distanceText'),
        if (a.storeLatitude != null && a.storeLongitude != null)
          InfoChip(
            icon: Icons.navigation_outlined,
            text: '导航',
            onTap: () => _launchNavigation(a),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AssignmentProvider, LocationProvider>(
      builder: (context, provider, loc, _) {
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
                    provider.error ?? '加载任务失败，请稍后重试',
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _refresh, child: const Text('重试')),
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

        final theme = Theme.of(context);

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final a = items[index];

              final client = (a.clientName ?? '').trim();
              final project = (a.projectName ?? '').trim();
              final store = (a.storeName ?? '').trim();

              final title = store.isNotEmpty
                  ? '$client - $project - $store'
                  : '$client - $project';

              return Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 左侧竖条
                      Container(
                        width: 4,
                        height: 52,
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
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              a.questionnaireTitle ?? '',
                              style: theme.textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 6),
                            _buildBottomMeta(a, loc),
                          ],
                        ),
                      ),

                      const SizedBox(width: 12),

                      _buildTrailing(a, loading: provider.isLoading),
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
