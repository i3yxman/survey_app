// lib/repositories/questionnaire_repository.dart

import '../models/api_models.dart';
import '../services/api_service.dart';

/// QuestionnaireRepository —— 问卷相关接口
class QuestionnaireRepository {
  final ApiService _api;

  QuestionnaireRepository({ApiService? api}) : _api = api ?? ApiService();

  Future<QuestionnaireDto> fetchDetail(int questionnaireId) {
    return _api.fetchQuestionnaireDetail(questionnaireId);
  }
}
