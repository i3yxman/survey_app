// lib/screens/account/notification_settings_page.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  Map<String, bool> _notify = {
    'task_published': true,
    'assignment_assigned': true,
    'assignment_unassigned': true,
    'review_approved': true,
    'review_request_changes': true,
    'review_cancelled': true,
  };

  String _notifySignature(Map<String, dynamic>? settings) {
    if (settings == null) return '';
    final keys = settings.keys.toList()..sort();
    return keys.map((k) => '$k:${settings[k]}').join('|');
  }

  String _userSignature(dynamic user) {
    return _notifySignature(user.notificationSettings);
  }

  String _lastUserSignature = '';

  void _syncFromUser(dynamic user) {
    final settings = user.notificationSettings ?? {};
    setState(() {
      _notify = {
        'task_published': settings['task_published'] ?? true,
        'assignment_assigned': settings['assignment_assigned'] ?? true,
        'assignment_unassigned': settings['assignment_unassigned'] ?? true,
        'review_approved': settings['review_approved'] ?? true,
        'review_request_changes': settings['review_request_changes'] ?? true,
        'review_cancelled': settings['review_cancelled'] ?? true,
      };
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = context.read<AuthProvider>();
      await auth.refreshProfile();
      final user = auth.currentUser;
      if (user == null) return;
      _lastUserSignature = _userSignature(user);
      _syncFromUser(user);
    });
  }

  Future<void> _save(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    await auth.updateProfile({
      'notification_settings': _notify,
    });
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.currentUser;
    final theme = Theme.of(context);
    if (user != null) {
      final signature = _userSignature(user);
      if (signature != _lastUserSignature) {
        _lastUserSignature = signature;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _syncFromUser(user);
        });
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('通知偏好')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.notifications_active_outlined),
                    title: const Text('消息提醒'),
                    subtitle: const Text('选择你希望接收的通知类型'),
                  ),
                  _buildNotifyTile('task_published', '新任务发布'),
                  _buildNotifyTile('assignment_assigned', '任务已分配'),
                  _buildNotifyTile('assignment_unassigned', '任务取消分配'),
                  _buildNotifyTile('review_request_changes', '报告退回修改'),
                  _buildNotifyTile('review_approved', '报告审核通过'),
                  _buildNotifyTile('review_cancelled', '报告审核未通过'),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: auth.loading ? null : () => _save(context),
                child: Text(auth.loading ? '保存中...' : '保存设置'),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '需要系统通知权限时，请在系统设置里开启。',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotifyTile(String key, String label) {
    return SwitchListTile(
      value: _notify[key] ?? true,
      onChanged: (v) => setState(() => _notify[key] = v),
      title: Text(label),
    );
  }
}
