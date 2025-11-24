// test/providers/assignment_provider_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:survey_app/providers/assignment_provider.dart';
import 'package:survey_app/repositories/assignment_repository.dart';
import 'package:survey_app/models/api_models.dart';

/// 一个“成功”的假仓库：返回 1 条任务
class FakeAssignmentRepositorySuccess extends AssignmentRepository {
  @override
  Future<List<Assignment>> fetchMyAssignments() async {
    return [
      Assignment(
        id: 1,
        clientName: 'Client A',
        projectId: 10,
        projectName: 'Project X',
        questionnaireId: 20,
        questionnaireTitle: 'Questionnaire Q1',
        status: 'pending',
        createdAt: '2024-01-01T00:00:00Z',
      ),
    ];
  }
}

/// 一个“失败”的假仓库：抛出异常
class FakeAssignmentRepositoryFailure extends AssignmentRepository {
  @override
  Future<List<Assignment>> fetchMyAssignments() {
    throw Exception('network error');
  }
}

void main() {
  group('AssignmentProvider', () {
    test('loadAssignments 成功时，填充列表并清空错误', () async {
      final provider = AssignmentProvider(
        repo: FakeAssignmentRepositorySuccess(),
      );

      // 初始状态
      expect(provider.loading, false);
      expect(provider.assignments, isEmpty);
      expect(provider.error, isNull);

      await provider.loadAssignments();

      // 结束后状态
      expect(provider.loading, false);
      expect(provider.error, isNull);
      expect(provider.assignments.length, 1);
      expect(provider.assignments.first.clientName, 'Client A');
    });

    test('loadAssignments 失败时，error 不为空，列表为空', () async {
      final provider = AssignmentProvider(
        repo: FakeAssignmentRepositoryFailure(),
      );

      await provider.loadAssignments();

      expect(provider.loading, false);
      expect(provider.assignments, isEmpty);
      expect(provider.error, isNotNull);
    });
  });
}