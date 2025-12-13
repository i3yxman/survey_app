// lib/repositories/submission_repository.dart

import 'package:flutter/services.dart';

import '../models/api_models.dart';
import '../services/api_service.dart';

/// SubmissionRepository —— 提交记录 / 媒体上传 / 审核沟通
class SubmissionRepository {
  final ApiService _api;

  SubmissionRepository({ApiService? api}) : _api = api ?? ApiService();

  /// 上传媒体文件（带进度）
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

  /// 批量获取媒体文件详情：根据 id 列表
  Future<List<MediaFileDto>> fetchMediaFilesByIds(List<int> ids) {
    return _api.fetchMediaFilesByIds(ids);
  }

  /// 获取某个任务的提交记录
  Future<List<SubmissionDto>> getSubmissions(int assignmentId) {
    return _api.getSubmissions(assignmentId);
  }

  /// 保存提交（草稿 / 提交 / 重新提交）
  Future<SubmissionDto> saveSubmission({
    int? submissionId,
    required int assignmentId,
    required String status,
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

  /// 获取某个 submission 的对话列表
  Future<List<SubmissionCommentDto>> fetchSubmissionComments(int submissionId) {
    return _api.fetchSubmissionComments(submissionId);
  }

  /// 发表一条评论
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
