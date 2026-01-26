// lib/repositories/submission_repository.dart

import 'dart:typed_data';

import '../models/api_models.dart';
import '../services/api_service.dart';

class SubmissionRepository {
  final ApiService _api;
  SubmissionRepository({ApiService? apiService})
    : _api = apiService ?? ApiService();

  Future<List<SubmissionDto>> getSubmissions(int assignmentId) {
    return _api.getSubmissions(assignmentId);
  }

  Future<SubmissionDto> saveSubmission({
    int? submissionId,
    required int assignmentId,
    required Map<int, AnswerDraft> answers,
    bool includeUnanswered = false,
  }) {
    return _api.saveSubmission(
      submissionId: submissionId,
      assignmentId: assignmentId,
      answers: answers,
      includeUnanswered: includeUnanswered,
    );
  }

  Future<SubmissionDto> submitSubmission(int submissionId) {
    return _api.submitSubmission(submissionId);
  }

  Future<void> updatePlannedVisitDate({
    required int assignmentId,
    required DateTime plannedVisitDate,
  }) async {
    await _api.updatePlannedVisitDate(
      assignmentId: assignmentId,
      plannedVisitDate: plannedVisitDate,
    );
  }

  Future<MediaFileDto> uploadMedia({
    required int questionId,
    required String mediaType,
    required Uint8List fileBytes,
    required String filename,
    void Function(int sent, int total)? onProgress,
  }) {
    return _api.uploadMedia(
      questionId: questionId,
      mediaType: mediaType,
      fileBytes: fileBytes,
      filename: filename,
      onProgress: onProgress,
    );
  }

  Future<List<MediaFileDto>> fetchMediaFilesByIds(List<int> ids) {
    return _api.fetchMediaFilesByIds(ids);
  }

  Future<List<SubmissionCommentDto>> fetchSubmissionComments(int submissionId) {
    return _api.fetchSubmissionComments(submissionId);
  }

  Future<SubmissionCommentDto> createSubmissionComment({
    required int submissionId,
    required String message,
  }) {
    return _api.createSubmissionComment(
      submissionId: submissionId,
      message: message,
    );
  }
}
