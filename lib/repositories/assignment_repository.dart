// lib/repositories/assignment_repository.dart

import '../services/api_service.dart';
import '../models/api_models.dart';

/// AssignmentRepository —— “我的任务”所有业务
class AssignmentRepository {
  final ApiService _api = ApiService();

  /// 获取我的任务列表
  Future<List<Assignment>> fetchMyAssignments() {
    return _api.getMyAssignments();
  }

  /// 两阶段取消任务
  ///
  /// confirm = false → 预览提示
  /// confirm = true  → 真正取消
  Future<CancelAssignmentResponse> cancelAssignment({
    required int assignmentId,
    bool confirm = false,
  }) {
    return _api.cancelAssignment(
      assignmentId: assignmentId,
      confirm: confirm,
    );
  }

  /// 获取任务对应的提交记录
  Future<List<SubmissionDto>> getSubmissions(int assignmentId) {
    return _api.getSubmissions(assignmentId);
  }
}