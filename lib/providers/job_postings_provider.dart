// lib/providers/job_postings_provider.dart

import 'package:flutter/foundation.dart';

import '../models/api_models.dart';
import '../repositories/job_posting_repository.dart';
import '../utils/error_message.dart';

/// “任务大厅” Provider
class JobPostingsProvider extends ChangeNotifier {
  final JobPostingRepository _repo;

  JobPostingsProvider({JobPostingRepository? repo})
    : _repo = repo ?? JobPostingRepository();

  bool _isLoading = false;
  String? _error;
  List<JobPosting> _jobPostings = [];

  // 兼容老代码 & 测试
  bool get isLoading => _isLoading;
  bool get loading => _isLoading; // tests 里用到 provider.loading
  String? get error => _error;
  List<JobPosting> get jobPostings => _jobPostings;

  /// 对外统一用 refresh
  Future<void> refresh() async {
    await loadJobPostings();
  }

  /// 真正加载“任务大厅”列表
  Future<void> loadJobPostings() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final list = await _repo.fetchJobPostings();
      _jobPostings = list;
    } catch (e) {
      _jobPostings = [];
      _error = userMessageFrom(e, fallback: '加载任务大厅失败，请稍后重试');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 申请任务
  Future<void> apply(int postingId) async {
    try {
      await _repo.apply(postingId);
      // 成功后重新拉一遍列表，保持 UI 最新
      await loadJobPostings();
    } catch (e) {
      // 存一份“人话”在 provider.error，方便调试 / 显示
      _error = userMessageFrom(e, fallback: '申请任务失败，请稍后重试');
      notifyListeners();
      rethrow;
    }
  }

  /// 撤销申请
  Future<void> cancelApply(int postingId) async {
    try {
      await _repo.cancelApply(postingId);
      await loadJobPostings();
    } catch (e) {
      _error = userMessageFrom(e, fallback: '撤销申请失败，请稍后重试');
      notifyListeners();
      rethrow;
    }
  }
}
