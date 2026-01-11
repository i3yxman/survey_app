// lib/screens/assignments/assignment_detail_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/api_models.dart';
import '../../providers/assignment_provider.dart';
import '../../providers/location_provider.dart';
import '../../services/api_service.dart';
import '../../utils/date_format.dart';
import '../../utils/currency_format.dart';
import '../../utils/location_utils.dart';
import '../../utils/map_selector.dart';
import '../../utils/snackbar.dart';
import '../../widgets/info_chip.dart';
import '../../widgets/avoid_dates_chip.dart';
import '../../widgets/task_content_section.dart';
import 'my_assignments_page.dart' show statusLabel;

class AssignmentDetailPage extends StatefulWidget {
  const AssignmentDetailPage({super.key});

  @override
  State<AssignmentDetailPage> createState() => _AssignmentDetailPageState();
}

class _AssignmentDetailPageState extends State<AssignmentDetailPage> {
  late Assignment _assignment;
  bool _inited = false;
  bool _actionLoading = false;
  bool _shouldRefreshOnPop = false;

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

  bool _canCancel(Assignment a) {
    final status = a.status;
    return !(status == 'submitted' ||
        status == 'reviewed' ||
        status == 'cancelled');
  }

  /// 打开地图导航（和列表里的逻辑一致）
  void _launchNav(Assignment a) {
    final lat = a.storeLatitude;
    final lng = a.storeLongitude;
    if (lat == null || lng == null) return;

    final name = a.storeName ?? a.clientName ?? '目的地';
    openMapSelector(context: context, lat: lat, lng: lng, label: name);
  }

  String? _formatDistance(
    LocationProvider loc,
    double? storeLat,
    double? storeLng,
  ) {
    return formatStoreDistance(loc.position, storeLat, storeLng);
  }

  Future<void> _openFill(Assignment a) async {
    final needRefresh = await Navigator.pushNamed(
      context,
      '/survey-fill',
      arguments: a,
    );

    if (needRefresh == true && mounted) {
      _shouldRefreshOnPop = true;
      await context.read<AssignmentProvider>().loadAssignments();
    }
  }

  Future<void> _handleCancelAssignment(Assignment assignment) async {
    final provider = context.read<AssignmentProvider>();

    try {
      setState(() {
        _actionLoading = true;
      });

      // 第一步：预览
      final preview = await provider.cancelAssignment(
        assignmentId: assignment.id,
        confirm: false,
      );

      if (!preview.confirmRequired) {
        if (!mounted) return;
        showSuccessSnackBar(context, preview.detail);
        _shouldRefreshOnPop = true;
        await provider.loadAssignments();
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
      _shouldRefreshOnPop = true;
      await provider.loadAssignments();
    } on ApiException catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e, fallback: '操作失败，请稍后重试');
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e, fallback: '取消任务失败，请稍后再试');
    } finally {
      if (mounted) {
        setState(() {
          _actionLoading = false;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;

    _assignment = ModalRoute.of(context)!.settings.arguments as Assignment;
  }

  Future<bool> _onWillPop() async {
    Navigator.of(context).pop(_shouldRefreshOnPop);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Consumer2<AssignmentProvider, LocationProvider>(
        builder: (context, provider, loc, _) {
          final latest = provider.assignments.firstWhere(
            (it) => it.id == _assignment.id,
            orElse: () => _assignment,
          );

          final a = latest;
          final theme = Theme.of(context);

          final title = a.storeName != null && a.storeName!.isNotEmpty
              ? '${a.clientName} - ${a.projectName} - ${a.storeName}'
              : '${a.clientName} - ${a.projectName}';

          final storeLine = a.storeAddress != null && a.storeAddress!.isNotEmpty
              ? '门店：${a.storeName ?? ''}（${a.storeAddress}）'
              : (a.storeName != null ? '门店：${a.storeName}' : null);

          final primaryLabel = _primaryActionLabel(a);
          final primaryEnabled = _primaryActionEnabled(a);
          final distanceText = _formatDistance(
            loc,
            a.storeLatitude,
            a.storeLongitude,
          );

          final plannedVisit = a.plannedVisitDate;
          final plannedVisitText = plannedVisit != null
              ? '计划走访日期：${formatDateZh(plannedVisit)}'
              : null;
          final desc = (a.taskContent ?? '').trim().isNotEmpty
              ? a.taskContent!
              : (a.postingDescription ?? '').trim();

          return Scaffold(
            appBar: AppBar(
              title: const Text('任务详情'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(_shouldRefreshOnPop),
              ),
            ),
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
                                  if (desc.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      desc,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      InfoChip(
                                        icon: Icons.info_outline,
                                        text: '状态：${statusLabel(a)}',
                                      ),
                                      if (plannedVisitText != null)
                                        InfoChip(
                                          icon: Icons.event_outlined,
                                          text: plannedVisitText,
                                        ),
                                      if (storeLine != null)
                                        InfoChip(
                                          icon: Icons.storefront_outlined,
                                          text: storeLine,
                                        ),
                                      if (a.projectDateRange != null)
                                        InfoChip(
                                          icon: Icons.date_range_outlined,
                                          text: '项目周期：${a.projectDateRange}',
                                        ),
                                      if (a.rewardAmount != null)
                                        InfoChip(
                                          icon: Icons.paid_outlined,
                                          text: '任务报酬 ${formatCurrency(a.rewardAmount, a.currency)}',
                                        ),
                                      if ((a.reimbursementAmount ?? 0) > 0)
                                        InfoChip(
                                          icon: Icons.receipt_long_outlined,
                                          text: '报销 ${formatCurrency(a.reimbursementAmount, a.currency)}',
                                        ),
                                      if (distanceText != null)
                                        InfoChip(
                                          icon: Icons.place_outlined,
                                          text: '距离门店 $distanceText',
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
                                  if (a.avoidVisitDates.isNotEmpty ||
                                      a.avoidVisitDateRanges.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    AvoidDatesChip(
                                      rawDates: a.avoidVisitDates,
                                      ranges: a.avoidVisitDateRanges,
                                      foldThreshold: 6,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '具体任务内容',
                              style: theme.textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            TaskContentSection(
                              content: desc,
                              attachments: a.taskAttachments,
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
                        child: Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: (primaryEnabled && !_actionLoading)
                                    ? () => _openFill(a)
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
                            if (_canCancel(a)) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: TextButton(
                                  onPressed: _actionLoading
                                      ? null
                                      : () => _handleCancelAssignment(a),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                  ),
                                  child: const Text('取消任务'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
