// test/providers/job_postings_provider_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:survey_app/providers/job_postings_provider.dart';
import 'package:survey_app/repositories/job_posting_repository.dart';
import 'package:survey_app/models/api_models.dart';

/// 假的仓库 —— 返回固定的列表（成功场景）
class FakeJobPostingRepositorySuccess extends JobPostingRepository {
  @override
  Future<List<JobPosting>> fetchJobPostings() async {
    return [
      JobPosting(
        id: 1,
        title: '测试任务',
        description: '描述',
        status: 'open',
        clientId: 100,
        clientName: '测试客户',
        projectId: 200,
        projectName: '测试项目',
        questionnaireId: 300,
        questionnaireTitle: '测试问卷',
        createdAt: '2024-01-01T00:00:00Z',
        storeId: null,
        storeCode: null,
        storeName: null,
        storeAddress: null,
        storeCity: null,
        storeLatitude: null,
        storeLongitude: null,
      ),
    ];
  }
}

/// 假的仓库 —— 抛异常（失败场景）
class FakeJobPostingRepositoryFailure extends JobPostingRepository {
  @override
  Future<List<JobPosting>> fetchJobPostings() async {
    throw Exception('network error');
  }
}

void main() {
  group('JobPostingsProvider', () {
    test('loadJobPostings 成功时，填充列表并清空错误', () async {
      final provider = JobPostingsProvider(
        repo: FakeJobPostingRepositorySuccess(),
      );

      expect(provider.loading, false);
      expect(provider.jobPostings, isEmpty);

      final future = provider.loadJobPostings();
      expect(provider.loading, true);

      await future;

      expect(provider.loading, false);
      expect(provider.error, isNull);
      expect(provider.jobPostings, isNotEmpty);
      expect(provider.jobPostings.first.title, '测试任务');
    });

    test('loadJobPostings 失败时，error 不为空，列表为空', () async {
      final provider = JobPostingsProvider(
        repo: FakeJobPostingRepositoryFailure(),
      );

      await provider.loadJobPostings();

      expect(provider.loading, false);
      expect(provider.error, isNotNull);
      expect(provider.jobPostings, isEmpty);
    });
  });
}