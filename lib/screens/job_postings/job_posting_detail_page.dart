// lib/screens/job_postings/job_posting_detail_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/api_models.dart';
import '../../providers/job_postings_provider.dart';
import '../../providers/location_provider.dart';
import '../../services/api_service.dart';
import '../../utils/date_format.dart';
import '../../utils/currency_format.dart';
import '../../utils/location_utils.dart';
import '../../utils/map_selector.dart';
import '../../utils/snackbar.dart';
import '../../widgets/avoid_dates_chip.dart';
import '../../widgets/info_chip.dart';
import '../../widgets/task_content_section.dart';

class JobPostingDetailPage extends StatefulWidget {
  const JobPostingDetailPage({super.key});

  @override
  State<JobPostingDetailPage> createState() => _JobPostingDetailPageState();
}

class _JobPostingDetailPageState extends State<JobPostingDetailPage> {
  late JobPosting _posting;
  bool _inited = false;
  bool _actionLoading = false;
  bool _shouldRefreshOnPop = false;

  Future<bool> _onWillPop() async {
    Navigator.of(context).pop(_shouldRefreshOnPop);
    return false;
  }

  /// 选择计划日期并提交申请
  Future<void> _handleApply(
    JobPosting p, {
    DateTime? initialPlannedDate,
  }) async {
    final provider = context.read<JobPostingsProvider>();
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    if (p.projectStartDate == null || p.projectEndDate == null) {
      if (!mounted) return;
      showErrorSnackBar(context, '该任务所属项目未设置开始/结束日期，暂不可申请');
      return;
    }

    final projectStart = DateTime.parse(p.projectStartDate!);
    final projectEnd = DateTime.parse(p.projectEndDate!);
    final projectStartDate = DateTime(
      projectStart.year,
      projectStart.month,
      projectStart.day,
    );
    final projectEndDate = DateTime(
      projectEnd.year,
      projectEnd.month,
      projectEnd.day,
    );

    final first = todayDate.isAfter(projectStartDate)
        ? todayDate
        : projectStartDate;
    final last = projectEndDate;

    if (first.isAfter(last)) {
      if (!mounted) return;
      showErrorSnackBar(context, '项目周期已结束，无法申请');
      return;
    }

    Set<DateTime> expandRanges(
      List<Map<String, String>> ranges,
    ) {
      final out = <DateTime>{};
      for (final r in ranges) {
        final startRaw = r['start'];
        final endRaw = r['end'];
        if (startRaw == null || endRaw == null) continue;
        final start = DateTime.parse(startRaw);
        final end = DateTime.parse(endRaw);
        var cur = DateTime(start.year, start.month, start.day);
        final last = DateTime(end.year, end.month, end.day);
        while (!cur.isAfter(last)) {
          out.add(cur);
          cur = cur.add(const Duration(days: 1));
        }
      }
      return out;
    }

    final avoidDates = {
      ...p.avoidVisitDates
          .map((e) => DateTime.parse(e))
          .map((d) => DateTime(d.year, d.month, d.day)),
      ...expandRanges(p.avoidVisitDateRanges),
    };

    DateTime? firstSelectable(DateTime start, DateTime end, Set<DateTime> blocked) {
      var cur = DateTime(start.year, start.month, start.day);
      final last = DateTime(end.year, end.month, end.day);
      while (!cur.isAfter(last)) {
        if (!blocked.contains(cur)) return cur;
        cur = cur.add(const Duration(days: 1));
      }
      return null;
    }

    DateTime effectiveInitial;
    if (initialPlannedDate != null &&
        !initialPlannedDate.isBefore(first) &&
        !initialPlannedDate.isAfter(last) &&
        !avoidDates.contains(initialPlannedDate)) {
      effectiveInitial = initialPlannedDate;
    } else {
      final fallback = firstSelectable(first, last, avoidDates);
      if (fallback == null) {
        if (!mounted) return;
        showErrorSnackBar(context, '项目周期内无可选日期');
        return;
      }
      effectiveInitial = fallback;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: effectiveInitial,
      firstDate: first,
      lastDate: last,
      locale: const Locale('zh', 'CN'),
      selectableDayPredicate: (day) {
        final d = DateTime(day.year, day.month, day.day);
        return !avoidDates.contains(d);
      },
    );

    if (picked == null) return;
    if (picked.isBefore(todayDate)) {
      if (!mounted) return;
      showErrorSnackBar(context, '无法选择过去的日期');
      return;
    }

    setState(() {
      _actionLoading = true;
    });

    try {
      await provider.apply(p.id, plannedVisitDate: picked);
      _shouldRefreshOnPop = true;
      if (!mounted) return;
      showSuccessSnackBar(context, '申请已提交，计划走访日期：${formatDateZh(picked)}');
    } on ApiException catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e, fallback: '申请失败，请稍后重试');
    } finally {
      if (mounted) {
        setState(() {
          _actionLoading = false;
        });
      }
    }
  }

  /// 撤销已提交的申请
  Future<void> _handleCancel(JobPosting p) async {
    final provider = context.read<JobPostingsProvider>();

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

    setState(() {
      _actionLoading = true;
    });

    try {
      await provider.cancelApply(p.id);
      _shouldRefreshOnPop = true;
      if (!mounted) return;
      showSuccessSnackBar(context, '申请已撤回');
    } on ApiException catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e, fallback: '撤销失败，请稍后重试');
    } finally {
      if (mounted) {
        setState(() {
          _actionLoading = false;
        });
      }
    }
  }

  /// 使用 LocationProvider + utils 统一计算距离
  String? _formatDistance(
    LocationProvider loc,
    double? storeLat,
    double? storeLng,
  ) {
    return formatStoreDistance(loc.position, storeLat, storeLng);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_inited) return;
    _inited = true;

    _posting = ModalRoute.of(context)!.settings.arguments as JobPosting;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Consumer2<JobPostingsProvider, LocationProvider>(
        builder: (context, provider, loc, _) {
          final latest = provider.jobPostings.firstWhere(
            (jp) => jp.id == _posting.id,
            orElse: () => _posting,
          );

          final p = latest;
          final theme = Theme.of(context);

          final title = p.storeName != null && p.storeName!.isNotEmpty
              ? '${p.clientName} - ${p.projectName} - ${p.storeName}'
              : '${p.clientName} - ${p.projectName}';

          final storeLine =
              p.storeAddress != null && p.storeAddress!.isNotEmpty
                  ? '门店：${p.storeName ?? ''}（${p.storeAddress}）'
                  : (p.storeName != null ? '门店：${p.storeName}' : null);

          final distanceText = _formatDistance(
            loc,
            p.storeLatitude,
            p.storeLongitude,
          );

          final applied = p.applicationStatus == 'applied' ||
              p.applicationStatus == 'approved';
          final canModifyPlan = applied && p.status == 'open';
          final statusLabel = (p.status == 'open' || p.status == 'pending')
              ? (applied ? '已申请' : '待申请')
              : '已关闭';
          final plannedVisitText = applied && p.plannedVisitDate != null
              ? '计划走访日期：${formatDateZh(DateTime.parse(p.plannedVisitDate!))}'
              : null;

          return Scaffold(
            appBar: AppBar(
              title: const Text('任务详情'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(_shouldRefreshOnPop),
              ),
            ),
            body: SafeArea(
              child: SingleChildScrollView(
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
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    p.questionnaireTitle,
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  if (p.description.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      p.description,
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
                                        text: '申请状态：$statusLabel',
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
                                      if (p.projectStartDate != null &&
                                          p.projectEndDate != null)
                                        InfoChip(
                                          icon: Icons.date_range_outlined,
                                          text:
                                              '项目周期：${formatDateZh(parseDate(p.projectStartDate))} 至 ${formatDateZh(parseDate(p.projectEndDate))}',
                                        ),
                                      if (p.rewardAmount != null)
                                        InfoChip(
                                          icon: Icons.paid_outlined,
                                          text:
                                              '任务报酬 ${formatCurrency(p.rewardAmount, p.currency)}',
                                        ),
                                      if ((p.reimbursementAmount ?? 0) > 0)
                                        InfoChip(
                                          icon: Icons.receipt_long_outlined,
                                          text:
                                              '报销 ${formatCurrency(p.reimbursementAmount, p.currency)}',
                                        ),
                                      if (distanceText != null)
                                        InfoChip(
                                          icon: Icons.place_outlined,
                                          text: '距离门店 $distanceText',
                                        ),
                                      if (p.storeLatitude != null &&
                                          p.storeLongitude != null)
                                        InfoChip(
                                          icon: Icons.navigation_outlined,
                                          text: '导航',
                                          onTap: () {
                                            openMapSelector(
                                              context: context,
                                              lat: p.storeLatitude!,
                                              lng: p.storeLongitude!,
                                              label:
                                                  p.storeName ?? p.clientName,
                                            );
                                          },
                                        ),
                                    ],
                                  ),
                                  if (p.avoidVisitDates.isNotEmpty ||
                                      p.avoidVisitDateRanges.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    AvoidDatesChip(
                                      rawDates: p.avoidVisitDates,
                                      ranges: p.avoidVisitDateRanges,
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

                    // 任务内容图文
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
                              content: (p.taskContent != null &&
                                      p.taskContent!.trim().isNotEmpty)
                                  ? p.taskContent
                                  : p.description,
                              attachments: p.taskAttachments,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // 申请 / 撤销操作区域
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: (_actionLoading || p.status != 'open')
                                    ? null
                                    : (applied
                                        ? () => _handleApply(
                                              p,
                                              initialPlannedDate:
                                                  p.plannedVisitDate != null
                                                      ? DateTime.parse(
                                                          p.plannedVisitDate!,
                                                        )
                                                      : null,
                                            )
                                        : () => _handleApply(p)),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                ),
                                child: Text(
                                  applied ? '修改计划走访日期' : '申请任务',
                                ),
                              ),
                            ),
                            if (applied) ...[
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: _actionLoading
                                      ? null
                                      : () => _handleCancel(p),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                  ),
                                  child: const Text('撤销申请'),
                                ),
                              ),
                            ],
                            if (p.status != 'open') ...[
                              const SizedBox(height: 12),
                              Text(
                                '任务已关闭，无法申请',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: Colors.grey),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
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
