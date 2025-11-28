// lib/screens/assignments/submission_comments_page.dart

import 'package:flutter/material.dart';

import '../../models/api_models.dart';
import '../../services/api_service.dart';

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
  final _api = ApiService();
  final TextEditingController _inputController = TextEditingController();

  bool _loading = true;
  bool _sending = false;
  String? _error;
  List<SubmissionCommentDto> _comments = [];

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
      final list = await _api.fetchSubmissionComments(widget.submissionId);
      setState(() {
        _comments = list;
      });
    } catch (e) {
      setState(() {
        _error = '加载对话失败：$e';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _sendComment() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _sending = true;
    });

    try {
      final dto = await _api.createSubmissionComment(
        submissionId: widget.submissionId,
        message: text,
      );

      setState(() {
        _comments = List<SubmissionCommentDto>.from(_comments)..add(dto);
        _inputController.clear();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败：$e')),
      );
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
      appBar: AppBar(
        title: Text(widget.title ?? '审核沟通'),
      ),
      body: Column(
        children: [
          if (widget.status != null) ...[
            Container(
              width: double.infinity,
              color: theme.colorScheme.surfaceVariant,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '当前状态：${widget.status}',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],

          Expanded(
            child: _buildBody(),
          ),

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
              ElevatedButton(
                onPressed: _loadComments,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_comments.isEmpty) {
      return const Center(
        child: Text('暂时还没有对话'),
      );
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
              crossAxisAlignment:
                  isReviewer ? CrossAxisAlignment.start : CrossAxisAlignment.end,
              children: [
                Text(
                  c.authorName.isNotEmpty ? c.authorName : (isReviewer ? '审核员' : '评估员'),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  c.message,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatTime(c.createdAt),
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.black38,
                  ),
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
            style: const TextStyle(
              fontSize: 11,
              color: Colors.black87,
            ),
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
                minLines: 1,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: '输入要对审核员说的话…',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                    onPressed: _sendComment,
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
    if (now.year == dt.year &&
        now.month == dt.month &&
        now.day == dt.day) {
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