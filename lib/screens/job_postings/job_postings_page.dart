// lib/screens/job_postings/job_postings_page.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/api_models.dart';
import '../../providers/job_postings_provider.dart';
import '../../providers/location_provider.dart'; // ⭐ 新增
import '../../services/api_service.dart';
import '../../widgets/info_chip.dart';
import '../../utils/location_utils.dart';
import '../../utils/snackbar.dart';
import '../../main.dart';

class JobPostingsPage extends StatefulWidget {
  const JobPostingsPage({super.key});

  @override
  State<JobPostingsPage> createState() => _JobPostingsPageState();
}

class _JobPostingsPageState extends State<JobPostingsPage> with RouteAware {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<JobPostingsProvider>().loadJobPostings();
      context.read<LocationProvider>().ensureLocation(); // ⭐ 全局定位
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    context.read<JobPostingsProvider>().loadJobPostings();
    context.read<LocationProvider>().ensureLocation();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    await context.read<JobPostingsProvider>().loadJobPostings();
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

  Future<void> _launchNavigation({
    required double lat,
    required double lng,
    String? label,
  }) async {
    final encodedLabel = Uri.encodeComponent(label ?? '目的地');
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

  Future<void> _handleApply(JobPosting p) async {
    final provider = context.read<JobPostingsProvider>();

    try {
      await provider.apply(p.id);

      if (!mounted) return;
      showSuccessSnackBar(context, '申请已提交，请等待审核');
      await _refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e, fallback: '申请失败，请稍后重试');
    } catch (e) {
      if (!mounted) return;
      showErrorSnackBar(context, e, fallback: '申请失败，请稍后再试');
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
          children: [
            Text(
              '已申请',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.secondary,
                fontWeight: FontWeight.w500,
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

        final theme = Theme.of(context);

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

                      // 中间内容
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
                                InfoChip(
                                  icon: Icons.schedule_outlined,
                                  text: '发布时间：${p.createdAt}',
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
                                      _launchNavigation(
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
