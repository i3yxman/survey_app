// lib/repositories/submission_repository.dart
import 'dart:typed_data';

import '../models/api_models.dart';
import '../services/api_service.dart';

class SubmissionRepository {
  final ApiService _api;

  SubmissionRepository({ApiService? api}) : _api = api ?? ApiService();

  /// 获取某个任务对应的提交记录
  Future<List<SubmissionDto>> getSubmissions(int assignmentId) {
    return _api.getSubmissions(assignmentId);
  }

  /// 保存提交（草稿/提交/重新提交）
  Future<SubmissionDto> saveSubmission({
    int? submissionId,
    required int assignmentId,
    required String status, // 'draft' / 'submitted' / 'resubmitted'
    required Map<int, AnswerDraft> answers,
    bool includeUnanswered = false,
  }) {
    return _api.saveSubmission(
      submissionId: submissionId,
      assignmentId: assignmentId,
      status: status,
      answers: answers,
      includeUnanswered: includeUnanswered,
    );
  }

  /// 上传媒体（带进度）
  Future<MediaFileDto> uploadMedia({
    required int questionId,
    required String mediaType, // 'image' / 'video'
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

  /// 根据 id 列表批量拉媒体详情
  Future<List<MediaFileDto>> fetchMediaFilesByIds(List<int> ids) {
    return _api.fetchMediaFilesByIds(ids);
  }

  /// 审核沟通：拉某个 submission 的 comments
  Future<List<SubmissionCommentDto>> fetchSubmissionComments(int submissionId) {
    return _api.fetchSubmissionComments(submissionId);
  }

  /// 审核沟通：发一条 comment
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
