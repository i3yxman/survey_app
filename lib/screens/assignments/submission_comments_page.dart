// lib/screens/assignments/submission_comments_page.dart

import 'package:flutter/material.dart';

import '../../models/api_models.dart';
import '../../utils/error_message.dart';
import '../../utils/snackbar.dart';
import '../../repositories/submission_repository.dart';

class SubmissionCommentsPage extends StatefulWidget {
  final int submissionId;
  final String? title;
  final String? status;

  const SubmissionCommentsPage({
    super.key,
    required this.submissionId,
    this.title,
    this.status,
  });

  @override
  State<SubmissionCommentsPage> createState() => _SubmissionCommentsPageState();
}

class _SubmissionCommentsPageState extends State<SubmissionCommentsPage> {
  final _repo = SubmissionRepository();
  final TextEditingController _inputController = TextEditingController();

  bool _loading = true;
  bool _sending = false;
  String? _error;
  List<SubmissionCommentDto> _comments = [];

  bool get _canSend {
    // 只有 needs_revision 才允许评估员发言（你也可以按需把 draft 放开）
    return widget.status == 'needs_revision';
  }

  String get _readOnlyHint {
    switch (widget.status) {
      case 'submitted':
        return '当前状态已提交，暂不支持发送消息';
      case 'resubmitted':
        return '当前状态已重新提交，暂不支持发送消息';
      case 'approved':
        return '当前状态已通过，暂不支持发送消息';
      case 'cancelled':
        return '当前状态已作废，暂不支持发送消息';
      default:
        return '当前状态不支持发送消息';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _loadComments() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list = await _repo.fetchSubmissionComments(widget.submissionId);
      if (!mounted) return;
      setState(() {
        _comments = list;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userMessageFrom(e, fallback: '加载对话失败，请稍后再试');
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _sendComment() async {
    if (!_canSend) {
      showErrorSnackBar(context, _readOnlyHint);
      return;
    }

    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _sending = true;
    });

    try {
      final dto = await _repo.createSubmissionComment(
        submissionId: widget.submissionId,
        message: text,
      );

      setState(() {
        _comments = List<SubmissionCommentDto>.from(_comments)..add(dto);
        _inputController.clear();
      });
      // 这里发送成功我就不额外弹“发送成功”了，聊天框本身会看到新消息
    } catch (e) {
      if (!mounted) return;
      // ✅ 统一走工具方法：支持 ApiException / 其他异常
      showErrorSnackBar(context, e, fallback: '发送失败，请稍后再试');
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? '审核沟通')),
      body: Column(
        children: [
          if (widget.status != null) ...[
            Container(
              width: double.infinity,
              color: theme.colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '当前状态：${widget.status}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],

          Expanded(child: _buildBody()),

          const Divider(height: 1),

          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              ElevatedButton(onPressed: _loadComments, child: const Text('重试')),
            ],
          ),
        ),
      );
    }

    if (_comments.isEmpty) {
      return const Center(child: Text('暂时还没有对话'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _comments.length,
      itemBuilder: (context, index) {
        final c = _comments[index];
        final isSystem = c.type == 'system';
        final isReviewer = c.role == 'reviewer';

        if (isSystem) {
          return _buildSystemMessage(c);
        }

        // 简单区分左右：审核员左侧，评估员右侧
        return Align(
          alignment: isReviewer ? Alignment.centerLeft : Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: isReviewer ? Colors.grey.shade200 : Colors.blue.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: isReviewer
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.end,
              children: [
                Text(
                  c.authorName.isNotEmpty
                      ? c.authorName
                      : (isReviewer ? '审核员' : '评估员'),
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
                const SizedBox(height: 4),
                Text(c.message, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  _formatTime(c.createdAt),
                  style: const TextStyle(fontSize: 10, color: Colors.black38),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSystemMessage(SubmissionCommentDto c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            c.message,
            style: const TextStyle(fontSize: 11, color: Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                enabled: _canSend && !_sending,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: _canSend ? '输入要对审核员说的话…' : _readOnlyHint,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _sending
                ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    onPressed: (_canSend && !_sending) ? _sendComment : null,
                    icon: const Icon(Icons.send),
                  ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    // 简单格式：HH:mm 或 MM-dd HH:mm
    final now = DateTime.now();
    if (now.year == dt.year && now.month == dt.month && now.day == dt.day) {
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } else {
      final mm = dt.month.toString().padLeft(2, '0');
      final dd = dt.day.toString().padLeft(2, '0');
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$mm-$dd $h:$m';
    }
  }
}
