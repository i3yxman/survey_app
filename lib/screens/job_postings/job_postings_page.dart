// lib/screens/job_postings/job_postings_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/api_models.dart';
import '../../providers/job_postings_provider.dart';
import '../../providers/location_provider.dart';
import '../../repositories/region_repository.dart';
import '../../widgets/info_chip.dart';
import '../../widgets/avoid_dates_chip.dart';
import '../../utils/location_utils.dart';
import '../../utils/date_format.dart';
import '../../utils/currency_format.dart';
import '../../main.dart';
import '../../utils/map_selector.dart';
import '../../widgets/app_button_styles.dart';

class JobPostingsPage extends StatefulWidget {
  const JobPostingsPage({super.key});

  @override
  State<JobPostingsPage> createState() => _JobPostingsPageState();
}

class _JobPostingsPageState extends State<JobPostingsPage> with RouteAware {
  static const _kPrefCityMode =
      'job_postings_city_mode'; // 'auto' | 'manual' | 'all'
  static const _kPrefManualCity = 'job_postings_manual_city';
  static const _kPrefManualProvince = 'job_postings_manual_province';
  static const _kPrefDistanceKm = 'job_postings_distance_km';
  static const _kPrefOnlyTaskCities = 'job_postings_only_task_cities';
  static const _kPrefSortBy = 'job_postings_sort_by'; // 'default' | 'distance' | 'reward'

  String _cityMode = 'auto';
  String? _manualCity;
  String? _manualProvince;
  double? _maxDistanceKm;
  bool _onlyTaskCities = false;
  String _sortBy = 'default';
  bool _distanceUnlimited = false;

  final RegionRepository _regionRepo = RegionRepository();
  List<Map<String, dynamic>> _regions = [];
  bool _regionsLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadCityPref();
      await _loadRegions();
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
    await _loadRegions();
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
    await _loadRegions();
    await context.read<LocationProvider>().ensureLocation();
    await context.read<JobPostingsProvider>().loadJobPostings();
    if (mounted) setState(() {});
  }

  Future<void> _loadCityPref() async {
    final sp = await SharedPreferences.getInstance();
    final mode = sp.getString(_kPrefCityMode) ?? 'auto';
    final manual = sp.getString(_kPrefManualCity);
    final manualProvince = sp.getString(_kPrefManualProvince);
    final distance = sp.getDouble(_kPrefDistanceKm);
    final onlyTasks = sp.getBool(_kPrefOnlyTaskCities) ?? true;
    final sortBy = sp.getString(_kPrefSortBy) ?? 'default';
    _cityMode = (mode == 'manual' && (manual == null || manual.trim().isEmpty))
        ? 'auto'
        : mode;
    _manualCity = (manual != null && manual.trim().isNotEmpty)
        ? manual.trim()
        : null;
    _manualProvince = (manualProvince != null && manualProvince.trim().isNotEmpty)
        ? manualProvince.trim()
        : null;
    if (distance == null) {
      _maxDistanceKm = 100.0;
      _distanceUnlimited = false;
    } else if (distance <= 0) {
      _maxDistanceKm = null;
      _distanceUnlimited = true;
    } else {
      _maxDistanceKm = distance;
      _distanceUnlimited = false;
    }
    _onlyTaskCities = onlyTasks;
    _sortBy = sortBy;
  }

  Future<void> _saveCityPref({
    required String mode,
    String? manualCity,
    String? manualProvince,
  }) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kPrefCityMode, mode);
    if (manualCity == null || manualCity.trim().isEmpty) {
      await sp.remove(_kPrefManualCity);
      await sp.remove(_kPrefManualProvince);
    } else {
      await sp.setString(_kPrefManualCity, manualCity.trim());
      if (manualProvince != null && manualProvince.trim().isNotEmpty) {
        await sp.setString(_kPrefManualProvince, manualProvince.trim());
      } else {
        await sp.remove(_kPrefManualProvince);
      }
    }
    _cityMode = mode;
    _manualCity = (manualCity == null || manualCity.trim().isEmpty)
        ? null
        : manualCity.trim();
    _manualProvince = (manualProvince == null || manualProvince.trim().isEmpty)
        ? null
        : manualProvince.trim();
  }

  Future<void> _saveFilterPref({
    double? maxDistanceKm,
    bool? onlyTaskCities,
  }) async {
    final sp = await SharedPreferences.getInstance();
    if (maxDistanceKm == null || maxDistanceKm <= 0) {
      await sp.setDouble(_kPrefDistanceKm, 0);
      _maxDistanceKm = null;
      _distanceUnlimited = true;
    } else {
      await sp.setDouble(_kPrefDistanceKm, maxDistanceKm);
      _maxDistanceKm = maxDistanceKm;
      _distanceUnlimited = false;
    }
    if (onlyTaskCities != null) {
      await sp.setBool(_kPrefOnlyTaskCities, onlyTaskCities);
      _onlyTaskCities = onlyTaskCities;
    }
  }

  Future<void> _saveSortPref(String sortBy) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kPrefSortBy, sortBy);
    _sortBy = sortBy;
  }

  Future<void> _loadRegions() async {
    if (_regionsLoading || _regions.isNotEmpty) return;
    _regionsLoading = true;
    try {
      final list = await _regionRepo.fetchRegions();
      if (list.isNotEmpty) _regions = list;
    } catch (_) {
      // ignore
    } finally {
      _regionsLoading = false;
    }
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
    if (_cityMode == 'all') return null;
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

  Future<void> _openDetail(JobPosting p) async {
    final needRefresh = await Navigator.pushNamed(
      context,
      '/job-posting-detail',
      arguments: p,
    );

    if (needRefresh == true) {
      await _refresh();
    }
  }

  Widget _buildTrailing(JobPosting p, {required bool loading}) {
    const double trailingWidth = 136;

    final statusLabel = (p.status == 'open' || p.status == 'pending')
        ? ((p.applicationStatus == 'applied' ||
                p.applicationStatus == 'approved')
            ? '已申请'
            : '待申请')
        : '已关闭';
    final plannedVisitText = (p.applicationStatus == 'applied' &&
            p.plannedVisitDate != null)
        ? '计划走访日期：${formatDateZh(DateTime.parse(p.plannedVisitDate!))}'
        : null;

    return SizedBox(
      width: trailingWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: loading ? null : () => _openDetail(p),
              style: AppButtonStyles.compactElevated(context),
              child: const Text('查看详情'),
            ),
          ),
          const SizedBox(height: 6),
          InfoChip(
            icon: Icons.info_outline,
            text: statusLabel,
          ),
          if (plannedVisitText != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: InfoChip(
                icon: Icons.event_outlined,
                text: plannedVisitText,
              ),
            ),
        ],
      ),
    );
  }

  String _formatLocationTitle(LocationProvider loc) {
    if (_cityMode == 'all') return '全部城市';
    if (_cityMode == 'manual') {
      if (_manualProvince != null && _manualCity != null) {
        return '$_manualProvince · $_manualCity';
      }
      return _manualCity ?? '手动选择';
    }
    final autoCity = (loc.city ?? '').trim();
    return autoCity.isEmpty ? '自动定位' : '自动定位（$autoCity）';
  }

  List<String> _taskCities(List<JobPosting> allItems) {
    final citySet = <String>{};
    for (final p in allItems) {
      final c = _guessCityFromAddress(p.storeAddress);
      if (c != null && c.trim().isNotEmpty) citySet.add(c.trim());
    }
    final list = citySet.toList()..sort();
    return list;
  }

  Future<void> _openLocationSheet({
    required LocationProvider loc,
    required List<JobPosting> allItems,
  }) async {
    final taskCities = _taskCities(allItems).toSet();
    final regionList = _regions;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        String mode = _cityMode;
        String? manualCity = _manualCity;
        String? manualProvince = _manualProvince;
        double? maxDistance = _maxDistanceKm;
        double sliderValue =
            _distanceUnlimited ? 0.0 : (_maxDistanceKm ?? 100.0);
        String sortBy = _sortBy;
        bool onlyTaskCities = _onlyTaskCities;
        String cityQuery = '';
        final distanceCtrl = TextEditingController(
          text: sliderValue <= 0 ? '' : sliderValue.toStringAsFixed(0),
        );

        List<Map<String, dynamic>> filteredRegions() {
          if (onlyTaskCities && taskCities.isNotEmpty) {
            return regionList
                .map((r) {
                  final name = r['name']?.toString() ?? '';
                  final cities = (r['cities'] as List?)
                          ?.map((e) => e.toString())
                          .where((c) => taskCities.contains(c))
                          .toList() ??
                      <String>[];
                  return {'name': name, 'cities': cities};
                })
                .where((r) => (r['cities'] as List).isNotEmpty)
                .toList();
          }
          return regionList;
        }

        void selectCity(String province, String city, void Function(VoidCallback) setSheetState) {
          setSheetState(() {
            mode = 'manual';
            manualProvince = province;
            manualCity = city;
          });
        }

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final theme = Theme.of(context);
            final regions = filteredRegions();
            final manualLabel = (manualProvince != null && manualCity != null)
                ? '$manualProvince · $manualCity'
                : (manualCity ?? '未选择');

            final filtered = cityQuery.trim().isEmpty
                ? regions
                : regions
                    .map((r) {
                      final name = r['name']?.toString() ?? '';
                      final cities = (r['cities'] as List?)
                              ?.map((e) => e.toString())
                              .where((c) =>
                                  c.contains(cityQuery.trim()) ||
                                  name.contains(cityQuery.trim()))
                              .toList() ??
                          <String>[];
                      return {'name': name, 'cities': cities};
                    })
                    .where((r) => (r['cities'] as List).isNotEmpty)
                    .toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.7,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.place_outlined),
                          const SizedBox(width: 8),
                          const Text('选择城市', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              setSheetState(() {
                                mode = 'all';
                                manualCity = null;
                                manualProvince = null;
                              });
                            },
                            child: const Text('全部城市'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: Text(
                              (loc.city ?? '').trim().isEmpty
                                  ? '自动定位'
                                  : '自动定位（${loc.city}）',
                            ),
                            selected: mode == 'auto',
                            onSelected: (_) {
                              setSheetState(() {
                                mode = 'auto';
                              });
                            },
                          ),
                          ChoiceChip(
                            label: Text('手动选择（$manualLabel）'),
                            selected: mode == 'manual',
                            onSelected: (_) {
                              setSheetState(() {
                                mode = 'manual';
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '只显示有任务的城市',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Switch(
                            value: onlyTaskCities,
                            onChanged: (v) {
                              setSheetState(() => onlyTaskCities = v);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('距离筛选'),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _distanceChip('不限', null, maxDistance, (next) {
                                setSheetState(() {
                                  maxDistance = next;
                                  sliderValue = 0.0;
                                  distanceCtrl.text = '';
                                });
                              }),
                              _distanceChip('1km', 1, maxDistance, (next) {
                                setSheetState(() {
                                  maxDistance = next;
                                  sliderValue = 1.0;
                                  distanceCtrl.text = '1';
                                });
                              }),
                              _distanceChip('3km', 3, maxDistance, (next) {
                                setSheetState(() {
                                  maxDistance = next;
                                  sliderValue = 3.0;
                                  distanceCtrl.text = '3';
                                });
                              }),
                              _distanceChip('5km', 5, maxDistance, (next) {
                                setSheetState(() {
                                  maxDistance = next;
                                  sliderValue = 5.0;
                                  distanceCtrl.text = '5';
                                });
                              }),
                              _distanceChip('10km', 10, maxDistance, (next) {
                                setSheetState(() {
                                  maxDistance = next;
                                  sliderValue = 10.0;
                                  distanceCtrl.text = '10';
                                });
                              }),
                              _distanceChip('20km', 20, maxDistance, (next) {
                                setSheetState(() {
                                  maxDistance = next;
                                  sliderValue = 20.0;
                                  distanceCtrl.text = '20';
                                });
                              }),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        sliderValue <= 0
                            ? '自定义距离：不限'
                            : '自定义距离：${sliderValue.toStringAsFixed(0)} km',
                        style: theme.textTheme.bodySmall,
                      ),
                      Slider(
                        value: sliderValue,
                        min: 0,
                        max: 300,
                        divisions: 300,
                        label: sliderValue <= 0
                            ? '不限'
                            : '${sliderValue.toStringAsFixed(0)} km',
                        onChanged: (v) {
                          setSheetState(() {
                            sliderValue = v;
                            if (v <= 0) {
                              maxDistance = null;
                              distanceCtrl.text = '';
                            } else {
                              maxDistance = v;
                              distanceCtrl.text = v.toStringAsFixed(0);
                            }
                          });
                        },
                      ),
                      TextField(
                        controller: distanceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '输入自定义距离（km）',
                          prefixIcon: Icon(Icons.tune),
                        ),
                        onChanged: (v) {
                          final parsed = double.tryParse(v);
                          setSheetState(() {
                            if (parsed == null || parsed <= 0) {
                              sliderValue = 0;
                              maxDistance = null;
                            } else {
                              sliderValue = parsed.clamp(0, 300);
                              maxDistance = sliderValue;
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Text('排序'),
                          const Spacer(),
                          Wrap(
                            spacing: 6,
                            children: [
                              ChoiceChip(
                                label: const Text('默认'),
                                selected: sortBy == 'default',
                                onSelected: (_) {
                                  setSheetState(() => sortBy = 'default');
                                },
                              ),
                              ChoiceChip(
                                label: const Text('距离最近'),
                                selected: sortBy == 'distance',
                                onSelected: (_) {
                                  setSheetState(() => sortBy = 'distance');
                                },
                              ),
                              ChoiceChip(
                                label: const Text('报酬最高'),
                                selected: sortBy == 'reward',
                                onSelected: (_) {
                                  setSheetState(() => sortBy = 'reward');
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: const InputDecoration(
                          hintText: '搜索城市或省份',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (v) {
                          setSheetState(() => cityQuery = v);
                        },
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: filtered.isEmpty
                            ? Center(
                                child: Text(
                                  regionList.isEmpty
                                      ? '城市数据加载中...'
                                      : (onlyTaskCities
                                          ? '当前没有可申请任务的城市'
                                          : '暂无匹配城市'),
                                ),
                              )
                            : ListView.builder(
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final region = filtered[index];
                                  final name = region['name']?.toString() ?? '';
                                  final cities = (region['cities'] as List?)
                                          ?.map((e) => e.toString())
                                          .toList() ??
                                      <String>[];
                                  if (name.isEmpty || cities.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  return Theme(
                                    data: theme.copyWith(dividerColor: Colors.transparent),
                                    child: ExpansionTile(
                                      initiallyExpanded: manualProvince == name && cityQuery.trim().isEmpty,
                                      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                      children: cities.map((city) {
                                        final selected = manualCity == city && manualProvince == name;
                                        return ListTile(
                                          title: Text(city),
                                          trailing: selected
                                              ? Icon(Icons.check, color: theme.colorScheme.primary)
                                              : null,
                                          onTap: () => selectCity(name, city, setSheetState),
                                        );
                                      }).toList(),
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('取消'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                await _saveCityPref(
                                  mode: mode,
                                  manualCity: manualCity,
                                  manualProvince: manualProvince,
                                );
                                await _saveFilterPref(
                                  maxDistanceKm: maxDistance,
                                  onlyTaskCities: onlyTaskCities,
                                );
                                await _saveSortPref(sortBy);
                                if (mounted) setState(() {});
                                if (context.mounted) Navigator.pop(context);
                                await _refresh();
                              },
                              child: const Text('应用'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _distanceChip(
    String label,
    double? value,
    double? selected,
    void Function(double? next) onSelect,
  ) {
    final isSelected = (value == null && selected == null) ||
        (value != null && selected != null && value == selected);
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        if (value == null) {
          onSelect(null);
        } else {
          onSelect(value);
        }
      },
    );
  }

  Widget _cityDropdown({
    required LocationProvider loc,
    required List<JobPosting> allItems,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => _openLocationSheet(loc: loc, allItems: allItems),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.place_outlined, size: 18),
            const SizedBox(width: 6),
            Text(_formatLocationTitle(loc)),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
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
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                provider.error ?? '加载任务大厅失败，请稍后重试',
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

        final allItems = provider.jobPostings;
        final effectiveCity = _effectiveCity(loc);

        final items = (effectiveCity == null || effectiveCity.trim().isEmpty)
            ? allItems
            : allItems.where((p) {
                final c = _guessCityFromAddress(p.storeAddress);
                return c == effectiveCity;
              }).toList();

        final filteredByDistance = (_maxDistanceKm == null)
            ? items
            : items.where((p) {
                final d = calcDistanceKm(
                  loc.position,
                  p.storeLatitude,
                  p.storeLongitude,
                );
                if (d == null) return true;
                return d <= _maxDistanceKm!;
              }).toList();

        final sortedItems = List<JobPosting>.from(filteredByDistance);
        if (_sortBy == 'distance') {
          sortedItems.sort((a, b) {
            final da = calcDistanceKm(
              loc.position,
              a.storeLatitude,
              a.storeLongitude,
            );
            final db = calcDistanceKm(
              loc.position,
              b.storeLatitude,
              b.storeLongitude,
            );
            if (da == null && db == null) return 0;
            if (da == null) return 1;
            if (db == null) return -1;
            return da.compareTo(db);
          });
        } else if (_sortBy == 'reward') {
          sortedItems.sort((a, b) {
            final ra = a.rewardAmount ?? 0;
            final rb = b.rewardAmount ?? 0;
            return rb.compareTo(ra);
          });
        }

        if (filteredByDistance.isEmpty) {
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
            itemCount: sortedItems.length + 1,
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

              final p = sortedItems[index - 1];

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
                                        label: p.storeName ?? p.clientName,
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
