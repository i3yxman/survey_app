import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/api_models.dart';
import '../screens/assignments/video_player_page.dart';

class TaskContentSection extends StatelessWidget {
  final String? content;
  final List<TaskAttachment> attachments;
  final String emptyText;

  const TaskContentSection({
    super.key,
    required this.content,
    required this.attachments,
    this.emptyText = '暂无任务内容',
  });

  Future<void> _openUrl(BuildContext context, String url) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开附件链接')),
      );
    }
  }

  Widget _buildAttachmentItem(BuildContext context, TaskAttachment att) {
    final theme = Theme.of(context);
    final mediaType = att.mediaType;
    final url = att.url;

    if (mediaType == 'image' && url.isNotEmpty) {
      return GestureDetector(
        onTap: () => _openUrl(context, url),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(
            url,
            width: 120,
            height: 90,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 120,
              height: 90,
              color: theme.colorScheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: const Text('图片加载失败'),
            ),
          ),
        ),
      );
    }

    IconData icon = Icons.insert_drive_file_outlined;
    if (mediaType == 'video') icon = Icons.videocam_outlined;
    if (mediaType == 'audio') icon = Icons.audiotrack_outlined;

    return InkWell(
      onTap: () {
        if (mediaType == 'video' && url.isNotEmpty) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => VideoPlayerPage(videoUrl: url)),
          );
          return;
        }
        _openUrl(context, url);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                att.name?.isNotEmpty == true ? att.name! : '附件',
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmed = (content ?? '').trim();
    final hasContent = trimmed.isNotEmpty;
    final hasAttachments = attachments.isNotEmpty;

    if (!hasContent && !hasAttachments) {
      return Text(
        emptyText,
        style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasContent) ...[
          MarkdownBody(
            data: trimmed,
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              p: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ),
        ],
        if (hasAttachments) ...[
          if (hasContent) const SizedBox(height: 12),
          Text(
            '附件',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: attachments
                .map((att) => _buildAttachmentItem(context, att))
                .toList(),
          ),
        ],
      ],
    );
  }
}
