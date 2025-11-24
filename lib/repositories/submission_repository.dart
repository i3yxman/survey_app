// lib/repositories/submission_repository.dart

import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../models/api_models.dart';

/// SubmissionRepository —— 提交记录 / 媒体上传
class SubmissionRepository {
  final ApiService _api = ApiService();

  /// 上传媒体文件
  Future<MediaFileDto> uploadMedia({
    required int questionId,
    required String mediaType,
    required Uint8List fileBytes,
    required String filename,
  }) {
    return _api.uploadMedia(
      questionId: questionId,
      mediaType: mediaType,
      fileBytes: fileBytes,
      filename: filename,
    );
  }
}