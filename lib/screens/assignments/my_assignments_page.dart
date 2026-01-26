// lib/screens/assignments/my_assignments_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/map_selector.dart';

import '../../models/api_models.dart';
import '../../providers/assignment_provider.dart';
import '../../providers/location_provider.dart';
import '../../widgets/info_chip.dart';
import '../../widgets/app_button_styles.dart';
import '../../utils/location_utils.dart';
import '../../utils/date_format.dart';
import '../../utils/currency_format.dart';
import '../../main.dart';
import '../../widgets/avoid_dates_chip.dart';
import '../../utils/status_format.dart';

/// 统一状态文案（优先使用当前提交状态）
String statusLabel(Assignment a) {
  final current = a.currentSubmissionStatus;
  if (current != null && current.isNotEmpty) {
    return formatStatusLabel(current);
  }
  return formatStatusLabel(a.status);
}

class MyAssignmentsPage extends StatefulWidget {
  const MyAssignmentsPage({super.key});

  @override
  State<MyAssignmentsPage> createState() => _MyAssignmentsPageState();
}

class _MyAssignmentsPageState extends State<MyAssignmentsPage> with RouteAware {
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    context.read<AssignmentProvider>().loadAssignments();
    context.read<LocationProvider>().ensureLocation();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  Future<void> _openDetail(Assignment a) async {
    final needRefresh = await Navigator.pushNamed(
      context,
      '/assignment-detail',
      arguments: a,
    );

    if (needRefresh == true) {
      await _refresh();
    }
  }

  /// 右侧按钮区域：查看详情 + 状态/计划日期
  Widget _buildTrailing(Assignment a, {required bool loading}) {
    const trailingWidth = 136.0;

    final plannedVisit = a.plannedVisitDate;
    final plannedVisitText =
        plannedVisit != null ? '计划走访日期：${formatDateZh(plannedVisit)}' : null;
    final statusText = statusLabel(a);

    return SizedBox(
      width: trailingWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: loading ? null : () => _openDetail(a),
              style: AppButtonStyles.compactElevated(context),
              child: const Text('查看详情', overflow: TextOverflow.ellipsis),
            ),
          ),
          if (plannedVisitText != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: InfoChip(
                icon: Icons.event_outlined,
                text: plannedVisitText,
              ),
            ),
          const SizedBox(height: 6),
          InfoChip(
            icon: Icons.info_outline,
            text: statusText,
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
        if (a.projectStartDate != null && a.projectEndDate != null)
          InfoChip(
            icon: Icons.date_range_outlined,
            text:
                '项目周期：${formatDateZh(a.projectStartDate)} 至 ${formatDateZh(a.projectEndDate)}',
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
          InfoChip(icon: Icons.place_outlined, text: '距离门店 $distanceText'),
        if (a.storeLatitude != null && a.storeLongitude != null)
          InfoChip(
            icon: Icons.navigation_outlined,
            text: '导航',
            onTap: () {
              openMapSelector(
                context: context,
                lat: a.storeLatitude!,
                lng: a.storeLongitude!,
                label: a.storeName ?? a.clientName ?? '目的地',
              );
            },
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
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                provider.error ?? '加载任务失败，请稍后重试',
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Center(
                child: ElevatedButton(
                  onPressed: _refresh,
                  child: const Text('重试'),
                ),
              ),
            ],
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
              final desc = (a.postingDescription ?? '').trim().isNotEmpty
                  ? a.postingDescription!
                  : (a.taskContent ?? '').trim();

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
                            if (desc.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                desc,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                            const SizedBox(height: 6),
                            _buildBottomMeta(a, loc),
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
