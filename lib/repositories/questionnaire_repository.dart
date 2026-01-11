// lib/repositories/questionnaire_repository.dart
import '../models/api_models.dart';
import '../services/api_service.dart';

class QuestionnaireRepository {
  final ApiService _api;

  QuestionnaireRepository({ApiService? api}) : _api = api ?? ApiService();

  /// 问卷详情（题目 + 选项 + 跳转逻辑）
  Future<QuestionnaireDto> fetchDetail(
    int questionnaireId, {
    int? assignmentId,
    int? storeId,
    int? groupId,
  }) {
    return _api.fetchQuestionnaireDetail(
      questionnaireId,
      assignmentId: assignmentId,
      storeId: storeId,
      groupId: groupId,
    );
  }
}
