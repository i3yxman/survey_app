// lib/repositories/job_posting_repository.dart

import '../models/api_models.dart';
import '../services/api_service.dart';

class JobPostingRepository {
  final ApiService _api;

  JobPostingRepository({ApiService? apiService})
    : _api = apiService ?? ApiService();

  /// 获取任务大厅列表
  Future<List<JobPosting>> fetchJobPostings() async {
    return _api.getJobPostings();
  }

  /// 申请任务
  Future<void> apply(int postingId) async {
    await _api.applyJobPosting(postingId);
  }

  /// 撤销申请
  Future<void> cancelApply(int postingId) async {
    await _api.cancelJobPostingApply(postingId);
  }
}
