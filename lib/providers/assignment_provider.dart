// lib/providers/assignment_provider.dart

import 'package:flutter/foundation.dart';

import '../models/api_models.dart';
import '../repositories/assignment_repository.dart';
import '../utils/error_message.dart';

/// “我的任务” Provider
class AssignmentProvider extends ChangeNotifier {
  final AssignmentRepository _repo;

  AssignmentProvider({AssignmentRepository? repo})
    : _repo = repo ?? AssignmentRepository();

  bool _isLoading = false;
  String? _error;
  List<Assignment> _assignments = [];

  // 兼容老代码 & 测试用
  bool get isLoading => _isLoading;
  bool get loading => _isLoading; // tests 里用到 provider.loading
  String? get error => _error;
  List<Assignment> get assignments => _assignments;

  /// 对外统一用 refresh（页面、测试都可以调用）
  Future<void> refresh() async {
    await loadAssignments();
  }

  /// 真正加载任务列表的逻辑
  Future<void> loadAssignments() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final list = await _repo.fetchMyAssignments();
      _assignments = list;
    } catch (e) {
      _assignments = [];
      _error = userMessageFrom(e, fallback: '加载任务失败，请稍后重试');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 两阶段取消任务（UI 那边直接调 provider.cancelAssignment）
  Future<CancelAssignmentResponse> cancelAssignment({
    required int assignmentId,
    bool confirm = false,
  }) {
    return _repo.cancelAssignment(assignmentId: assignmentId, confirm: confirm);
  }

  /// 获取某个任务的提交记录
  Future<List<SubmissionDto>> getSubmissions(int assignmentId) {
    return _repo.getSubmissions(assignmentId);
  }
}
