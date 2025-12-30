// lib/screens/job_postings/job_postings_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/api_models.dart';
import '../../providers/job_postings_provider.dart';
import '../../providers/location_provider.dart';
import '../../services/api_service.dart';
import '../../widgets/info_chip.dart';
import '../../widgets/avoid_dates_chip.dart';
import '../../utils/location_utils.dart';
import '../../utils/snackbar.dart';
import '../../utils/date_format.dart';
import '../../main.dart';
import '../../utils/map_selector.dart';

class JobPostingsPage extends StatefulWidget {
  const JobPostingsPage({super.key});

  @override
  State<JobPostingsPage> createState() => _JobPostingsPageState();
}

class _JobPostingsPageState extends State<JobPostingsPage> with RouteAware {
  static const _kPrefCityMode = 'job_postings_city_mode'; // 'auto' | 'manual'
  static const _kPrefManualCity = 'job_postings_manual_city';

  String _cityMode = 'auto';
  String? _manualCity;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadCityPref();
      await context.read<LocationProvider>().ensureLocation();
      await context.read<JobPostingsProvider>().loadJobPostings();
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) routeObserver.subscribe(this, route);
  }

  @override
  void didPopNext() async {
    await _loadCityPref();
    await context.read<LocationProvider>().ensureLocation();
    await context.read<JobPostingsProvider>().loadJobPostings();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    await _loadCityPref();
    await context.read<LocationProvider>().ensureLocation();
    await context.read<JobPostingsProvider>().loadJobPostings();
    if (mounted) setState(() {});
  }

  Future<void> _loadCityPref() async {
    final sp = await SharedPreferences.getInstance();
    final mode = sp.getString(_kPrefCityMode) ?? 'auto';
    final manual = sp.getString(_kPrefManualCity);
    _cityMode = (mode == 'manual' && (manual == null || manual.trim().isEmpty))
        ? 'auto'
        : mode;
    _manualCity = (manual != null && manual.trim().isNotEmpty)
        ? manual.trim()
        : null;
  }

  Future<void> _saveCityPref({required String mode, String? manualCity}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kPrefCityMode, mode);
    if (manualCity == null || manualCity.trim().isEmpty) {
      await sp.remove(_kPrefManualCity);
    } else {
      await sp.setString(_kPrefManualCity, manualCity.trim());
    }
    _cityMode = mode;
    _manualCity = (manualCity == null || manualCity.trim().isEmpty)
        ? null
        : manualCity.trim();
  }

  /// 从地址里粗略提取 “xx市”
  String? _guessCityFromAddress(String? addr) {
    if (addr == null) return null;
    final s = addr.trim();
    if (s.isEmpty) return null;

    // 常见：上海市/北京市/深圳市/杭州市...
    final m = RegExp(r'([^省区县]{2,6}市)').firstMatch(s);
    if (m != null) return m.group(1);

    // 直辖市/特别情况：北京/上海/天津/重庆（有些地址不带“市”）
    for (final c in ['北京', '上海', '天津', '重庆']) {
      if (s.contains(c)) return '$c市';
    }
    return null;
  }

  /// 当前应该用哪个城市过滤（auto/manual）
  String? _effectiveCity(LocationProvider loc) {
    if (_cityMode == 'manual') return _manualCity;
    final c = (loc.city ?? '').trim();
    return c.isEmpty ? null : c;
  }

  /// 使用 LocationProvider + utils 统一计算距离
  String? _formatDistance(
    LocationProvider loc,
    double? storeLat,
    double? storeLng,
  ) {
    return formatStoreDistance(loc.position, storeLat, storeLng);
  }

  Future<void> _handleApply(JobPosting p) async {
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

    final avoidDates = p.avoidVisitDates
        .map((e) => DateTime.parse(e))
        .map((d) => DateTime(d.year, d.month, d.day))
        .toSet();

    final picked = await showDatePicker(
      context: context,
      initialDate: first,
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

    try {
      await provider.apply(p.id, plannedVisitDate: picked);
      if (!mounted) return;
      showSuccessSnackBar(context, '申请已提交，计划走访日期：${formatDateZh(picked)}');
      await _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e, fallback: '申请失败，请稍后重试');
    }
  }

  Future<void> _handleCancelApply(JobPosting p) async {
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

    try {
      await provider.cancelApply(p.id);
      if (!mounted) return;
      showSuccessSnackBar(context, '申请已撤回');
      await _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e, fallback: '撤销失败，请稍后重试');
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e, fallback: '撤销失败，请稍后再试');
    }
  }

  Widget _buildTrailing(JobPosting p, {required bool loading}) {
    final isPostingOpen = p.status == 'open';
    final appStatus = p.applicationStatus;
    final theme = Theme.of(context);

    const double trailingWidth = 120;

    if (!isPostingOpen) {
      return SizedBox(
        width: trailingWidth,
        child: Center(
          child: Text(
            '已关闭',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
        ),
      );
    }

    if (appStatus == 'applied') {
      return SizedBox(
        width: trailingWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              '已申请',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.secondary,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (p.plannedVisitDate != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '计划走访日期：\n${formatDateZh(DateTime.parse(p.plannedVisitDate!))}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ),
            const SizedBox(height: 6),
            OutlinedButton(
              onPressed: loading ? null : () => _handleCancelApply(p),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                side: BorderSide(color: theme.colorScheme.error),
                foregroundColor: theme.colorScheme.error,
              ),
              child: const Text('撤销申请'),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: trailingWidth,
      child: Center(
        child: ElevatedButton(
          onPressed: loading ? null : () => _handleApply(p),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          ),
          child: const Text('申请任务'),
        ),
      ),
    );
  }

  Widget _cityDropdown({
    required LocationProvider loc,
    required List<JobPosting> allItems,
  }) {
    final autoCity = (loc.city ?? '').trim();

    final citySet = <String>{};
    for (final p in allItems) {
      final c = _guessCityFromAddress(p.storeAddress);
      if (c != null && c.trim().isNotEmpty) citySet.add(c.trim());
    }
    final cities = citySet.toList()..sort();

    String value;
    if (_cityMode == 'manual' && _manualCity != null) {
      value = 'manual:${_manualCity!}';
    } else {
      value = 'auto';
    }

    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem<String>(
        value: 'auto',
        child: Row(
          children: [
            const Icon(Icons.my_location, size: 18),
            const SizedBox(width: 8),
            Text(autoCity.isEmpty ? '自动定位（未知）' : '自动定位（$autoCity）'),
          ],
        ),
      ),
      if (cities.isNotEmpty)
        const DropdownMenuItem<String>(
          enabled: false,
          value: '__divider__',
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Text('手动选择', style: TextStyle(color: Colors.grey)),
          ),
        ),
      ...cities.map((c) {
        return DropdownMenuItem<String>(value: 'manual:$c', child: Text(c));
      }),
    ];

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        items: items,
        onChanged: (v) async {
          if (v == null || v == '__divider__') return;

          if (v == 'auto') {
            await _saveCityPref(mode: 'auto', manualCity: null);
            await _refresh();
            return;
          }

          if (v.startsWith('manual:')) {
            final c = v.substring('manual:'.length).trim();
            await _saveCityPref(mode: 'manual', manualCity: c);
            await _refresh();
            return;
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<JobPostingsProvider, LocationProvider>(
      builder: (context, provider, loc, _) {
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
                    provider.error ?? '加载任务大厅失败，请稍后重试',
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

        final allItems = provider.jobPostings;
        final effectiveCity = _effectiveCity(loc);

        final items = (effectiveCity == null || effectiveCity.trim().isEmpty)
            ? allItems
            : allItems.where((p) {
                final c = _guessCityFromAddress(p.storeAddress);
                return c == effectiveCity;
              }).toList();

        if (items.isEmpty) {
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              children: [
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _cityDropdown(loc: loc, allItems: allItems),
                  ),
                ),
                const SizedBox(height: 180),
                Center(
                  child: Text(
                    effectiveCity == null
                        ? '当前没有可申请的任务'
                        : '当前城市（$effectiveCity）没有可申请的任务',
                  ),
                ),
              ],
            ),
          );
        }

        final theme = Theme.of(context);

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.builder(
            itemCount: items.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _cityDropdown(loc: loc, allItems: allItems),
                  ),
                );
              }

              final p = items[index - 1];

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

              return Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
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

                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: theme.textTheme.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              p.questionnaireTitle,
                              style: theme.textTheme.bodyMedium,
                            ),
                            const SizedBox(height: 4),
                            if (p.description.isNotEmpty)
                              Text(
                                p.description,
                                style: theme.textTheme.bodySmall,
                              ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                if (p.avoidVisitDates.isNotEmpty ||
                                    p.avoidVisitDateRanges.isNotEmpty)
                                  AvoidDatesChip(
                                    rawDates: p.avoidVisitDates,
                                    ranges: p.avoidVisitDateRanges,
                                    foldThreshold: 6,
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
                                        '项目周期：${p.projectStartDate} 至 ${p.projectEndDate}',
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
                                        label: p.storeName ?? p.clientName,
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 12),

                      _buildTrailing(p, loading: provider.isLoading),
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
