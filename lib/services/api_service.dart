// lib/services/api_service.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';

import '../config/env.dart';
import '../models/api_models.dart';

/// ApiService 抛出的统一异常
class ApiException implements Exception {
  final int? statusCode;
  final dynamic body; // Map/List/String
  final String userMessage; // 给用户看的“人话”

  ApiException({required this.userMessage, this.statusCode, this.body});

  String get message => userMessage;

  @override
  String toString() => userMessage;

  static String extractUserMessage(dynamic data) {
    try {
      if (data == null) return "操作失败，请稍后再试";

      if (data is Map && data["message"] is String) {
        return (data["message"] as String).trim();
      }

      if (data is Map && data["detail"] != null) {
        final d = data["detail"];
        if (d is String) return d.trim();
        if (d is Map && d["message"] is String) {
          return (d["message"] as String).trim();
        }
      }

      if (data is Map) {
        for (final entry in data.entries) {
          final v = entry.value;
          if (v is List && v.isNotEmpty) return v.first.toString().trim();
          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
      }

      if (data is String) {
        final s = data.trim();
        if (s.isEmpty) return "操作失败，请稍后再试";
        try {
          final decoded = json.decode(s);
          return extractUserMessage(decoded);
        } catch (_) {
          return s;
        }
      }
    } catch (_) {}

    return "操作失败，请稍后再试";
  }
}

/// 后端接口统一客户端（单例）
/// ✅ 最佳实践：统一用 Dio + 拦截器注入 Authorization
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  ApiService._internal()
    : _dio = Dio(
        BaseOptions(
          baseUrl: Env.apiBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 25),
          sendTimeout: const Duration(seconds: 25),
          headers: {'Accept': 'application/json'},
        ),
      ) {
    // ✅ 拦截器：每个请求都自动加 Authorization（如果已有 token）
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // baseUrl 可能因为 env 切换改变：每次请求前确保最新
          options.baseUrl = Env.apiBaseUrl;

          if (_authToken != null && _authToken!.isNotEmpty) {
            options.headers['Authorization'] = 'Token $_authToken';
          }

          handler.next(options);
        },
        onError: (e, handler) {
          handler.next(e);
        },
      ),
    );

    // if (kDebugMode) {
    //   _dio.interceptors.add(
    //     LogInterceptor(
    //       request: false,
    //       requestHeader: false,
    //       requestBody: false,
    //       responseHeader: false,
    //       responseBody: false,
    //       error: true,
    //     ),
    //   );
    // }
  }

  String? _authToken;
  final Dio _dio;

  dynamic _normalizeData(dynamic data) {
    if (data == null) return null;
    if (data is String) {
      final s = data.trim();
      if (s.isEmpty) return null;
      try {
        return jsonDecode(s);
      } catch (_) {
        return s;
      }
    }
    return data;
  }

  Never _throwDioError(DioException e, {String fallback = "请求失败"}) {
    final status = e.response?.statusCode;
    final normalized = _normalizeData(e.response?.data);
    final msg = ApiException.extractUserMessage(normalized);

    throw ApiException(
      userMessage: (msg.isNotEmpty ? msg : fallback),
      statusCode: status,
      body: normalized ?? e.message,
    );
  }

  /// 手动设置 Token（登录成功/恢复登录会调用）
  void setAuthToken(String token) {
    var t = token.trim();
    t = t.replaceFirst(RegExp(r'^Token\s+', caseSensitive: false), '');
    _authToken = t;

    if (t.isEmpty) {
      _dio.options.headers.remove('Authorization');
      return;
    }
    _dio.options.headers['Authorization'] = 'Token $t';
  }

  bool get hasToken => _authToken != null && _authToken!.isNotEmpty;

  void clearAuthToken() {
    _authToken = null;
    _dio.options.headers.remove('Authorization');
  }

  // =========================
  // Auth
  // =========================

  Future<LoginResult> login(String identifier, String password) async {
    try {
      final resp = await _dio.post(
        '/api/accounts/login/',
        data: {'identifier': identifier, 'password': password},
        options: Options(contentType: Headers.jsonContentType),
      );

      final data = _normalizeData(resp.data);
      final result = LoginResult.fromJson(data as Map<String, dynamic>);

      if (result.token.trim().isEmpty) {
        throw ApiException(userMessage: "登录失败：未返回 token");
      }

      setAuthToken(result.token);
      return result;
    } on DioException catch (e) {
      _throwDioError(e, fallback: "登录失败");
    } catch (e) {
      throw ApiException(userMessage: "网络异常，请稍后重试", body: e.toString());
    }
  }

  Future<Map<String, dynamic>> me() async {
    try {
      final resp = await _dio.get('/api/accounts/me/');
      final data = _normalizeData(resp.data);
      if (data is! Map<String, dynamic>) {
        throw ApiException(userMessage: "获取用户信息失败：返回格式错误");
      }
      return data;
    } on DioException catch (e) {
      _throwDioError(e, fallback: "获取用户信息失败");
    } catch (e) {
      throw ApiException(userMessage: "网络异常，请稍后重试", body: e.toString());
    }
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      await _dio.post(
        '/api/accounts/change-password/',
        data: {'old_password': oldPassword, 'new_password': newPassword},
        options: Options(contentType: Headers.jsonContentType),
      );
    } on DioException catch (e) {
      _throwDioError(e, fallback: "修改密码失败");
    } catch (e) {
      throw ApiException(userMessage: "网络异常，请稍后重试", body: e.toString());
    }
  }

  Future<String> requestPasswordReset({required String identifier}) async {
    try {
      final resp = await _dio.post(
        '/api/accounts/forgot-password/',
        data: {'identifier': identifier},
        options: Options(contentType: Headers.jsonContentType),
      );
      final data = _normalizeData(resp.data);
      if (data is Map<String, dynamic> && data['detail'] is String) {
        return data['detail'] as String;
      }
      return '操作成功';
    } on DioException catch (e) {
      _throwDioError(e, fallback: "请求失败");
    } catch (e) {
      throw ApiException(userMessage: "网络异常，请稍后重试", body: e.toString());
    }
  }

  // =========================
  // Assignments
  // =========================

  Future<List<Assignment>> getMyAssignments() async {
    try {
      final resp = await _dio.get('/api/assignments/my-assignments/');
      final data = _normalizeData(resp.data);
      if (data is! List) {
        throw ApiException(userMessage: "获取任务列表失败：返回格式错误");
      }
      return data.map((e) => Assignment.fromJson(e)).toList();
    } on DioException catch (e) {
      _throwDioError(e, fallback: "获取任务列表失败");
    } catch (e) {
      throw ApiException(userMessage: "网络异常，请稍后重试", body: e.toString());
    }
  }

  Future<List<JobPosting>> getJobPostings() async {
    try {
      final resp = await _dio.get('/api/assignments/job-postings/');
      final data = _normalizeData(resp.data);
      if (data is! List) {
        throw ApiException(userMessage: "获取任务大厅失败：返回格式错误");
      }
      return data.map((e) => JobPosting.fromJson(e)).toList();
    } on DioException catch (e) {
      _throwDioError(e, fallback: "获取任务大厅失败");
    } catch (e) {
      throw ApiException(userMessage: "网络异常，请稍后重试", body: e.toString());
    }
  }

  Future<Map<String, dynamic>> applyJobPosting(
    int postingId, {
    required DateTime plannedVisitDate,
  }) async {
    try {
      final resp = await _dio.post(
        '/api/assignments/job-postings/$postingId/apply/',
        data: {
          'planned_visit_date': plannedVisitDate.toIso8601String().substring(
            0,
            10,
          ),
        },
        options: Options(contentType: Headers.jsonContentType),
      );
      final data = _normalizeData(resp.data);
      if (data == null) return {};
      if (data is Map<String, dynamic>) return data;
      return {};
    } on DioException catch (e) {
      _throwDioError(e, fallback: "任务申请失败");
    } catch (e) {
      throw ApiException(userMessage: "任务申请失败，请稍后重试", body: e.toString());
    }
  }

  Future<Map<String, dynamic>> cancelJobPostingApply(int postingId) async {
    try {
      final resp = await _dio.post(
        '/api/assignments/job-postings/$postingId/cancel/',
      );
      final data = _normalizeData(resp.data);
      if (data is Map<String, dynamic>) return data;
      return {};
    } on DioException catch (e) {
      _throwDioError(e, fallback: "撤销申请失败");
    } catch (e) {
      throw ApiException(userMessage: "撤销申请失败，请稍后重试", body: e.toString());
    }
  }

  Future<void> registerDeviceToken({
    required String platform,
    required String token,
  }) async {
    try {
      await _dio.post(
        '/api/assignments/device-tokens/',
        data: {'platform': platform, 'token': token},
        options: Options(contentType: Headers.jsonContentType),
      );
    } on DioException catch (e) {
      _throwDioError(e, fallback: "设备 token 上报失败");
    } catch (e) {
      throw ApiException(
        userMessage: "设备 token 上报失败，请稍后重试",
        body: e.toString(),
      );
    }
  }

  Future<MediaFileDto> uploadMedia({
    required int questionId,
    required String mediaType,
    required Uint8List fileBytes,
    required String filename,
    void Function(int sent, int total)? onProgress,
  }) async {
    final formData = FormData.fromMap({
      'media_type': mediaType,
      'question': questionId.toString(),
      'file': MultipartFile.fromBytes(fileBytes, filename: filename),
    });

    try {
      final resp = await _dio.post(
        '/api/assignments/upload-media/',
        data: formData,
        onSendProgress: (sent, total) => onProgress?.call(sent, total),
      );

      final data = _normalizeData(resp.data);
      return MediaFileDto.fromJson(data as Map<String, dynamic>);
    } on DioException catch (e) {
      _throwDioError(e, fallback: "上传媒体失败");
    } catch (e) {
      throw ApiException(userMessage: "上传媒体失败，请稍后重试", body: e.toString());
    }
  }

  Future<List<MediaFileDto>> fetchMediaFilesByIds(List<int> ids) async {
    if (ids.isEmpty) return [];
    try {
      final resp = await _dio.get(
        '/api/assignments/media-files/',
        queryParameters: {'ids': ids.join(',')},
      );

      final data = _normalizeData(resp.data);
      if (data is! List) {
        throw ApiException(userMessage: "获取媒体信息失败：返回格式错误");
      }
      return data
          .map((e) => MediaFileDto.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      _throwDioError(e, fallback: "获取媒体信息失败");
    } catch (e) {
      throw ApiException(userMessage: "获取媒体信息失败，请稍后重试", body: e.toString());
    }
  }

  Future<List<SubmissionCommentDto>> fetchSubmissionComments(
    int submissionId,
  ) async {
    try {
      final resp = await _dio.get(
        '/api/assignments/submissions/$submissionId/comments/',
      );
      final data = _normalizeData(resp.data);
      if (data is! List) {
        throw ApiException(userMessage: "加载沟通记录失败：返回格式错误");
      }
      return data
          .map((e) => SubmissionCommentDto.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      _throwDioError(e, fallback: "加载沟通记录失败");
    } catch (e) {
      throw ApiException(userMessage: "加载沟通记录失败，请稍后重试", body: e.toString());
    }
  }

  Future<SubmissionCommentDto> createSubmissionComment({
    required int submissionId,
    required String message,
  }) async {
    try {
      final resp = await _dio.post(
        '/api/assignments/submissions/$submissionId/comments/',
        data: {'message': message},
        options: Options(contentType: Headers.jsonContentType),
      );
      final data = _normalizeData(resp.data);
      return SubmissionCommentDto.fromJson(data as Map<String, dynamic>);
    } on DioException catch (e) {
      _throwDioError(e, fallback: "发送失败");
    } catch (e) {
      throw ApiException(userMessage: "发送失败，请稍后重试", body: e.toString());
    }
  }

  Future<CancelAssignmentResponse> cancelAssignment({
    required int assignmentId,
    bool confirm = false,
  }) async {
    try {
      final resp = await _dio.post(
        '/api/assignments/my-assignments/$assignmentId/cancel/',
        queryParameters: {'confirm': confirm ? 'true' : 'false'},
      );
      final data = _normalizeData(resp.data);
      return CancelAssignmentResponse.fromJson(data as Map<String, dynamic>);
    } on DioException catch (e) {
      _throwDioError(e, fallback: "取消任务失败");
    } catch (e) {
      throw ApiException(userMessage: "取消任务失败，请稍后重试", body: e.toString());
    }
  }

  Future<List<SubmissionDto>> getSubmissions(int assignmentId) async {
    try {
      final resp = await _dio.get(
        '/api/assignments/submissions/',
        queryParameters: {'assignment': assignmentId},
      );
      final data = _normalizeData(resp.data);
      if (data is! List) {
        throw ApiException(userMessage: "获取提交记录失败：返回格式错误");
      }
      return data.map((e) => SubmissionDto.fromJson(e)).toList();
    } on DioException catch (e) {
      _throwDioError(e, fallback: "获取提交记录失败");
    } catch (e) {
      throw ApiException(userMessage: "获取提交记录失败，请稍后重试", body: e.toString());
    }
  }

  // =========================
  // Survey
  // =========================

  Future<QuestionnaireDto> fetchQuestionnaireDetail(int questionnaireId) async {
    try {
      final resp = await _dio.get(
        '/api/survey/questionnaires/$questionnaireId/',
      );
      final data = _normalizeData(resp.data);
      return QuestionnaireDto.fromJson(data as Map<String, dynamic>);
    } on DioException catch (e) {
      _throwDioError(e, fallback: "获取问卷失败");
    } catch (e) {
      throw ApiException(userMessage: "获取问卷失败，请稍后重试", body: e.toString());
    }
  }

  Future<SubmissionDto> saveSubmission({
    int? submissionId,
    required int assignmentId,
    required Map<int, AnswerDraft> answers,
    bool includeUnanswered = false,
  }) async {
    // 把 AnswerDraft 映射成后端需要的结构
    final answerList = <Map<String, dynamic>>[];

    answers.forEach((questionId, draft) {
      final hasData =
          (draft.textValue != null && draft.textValue!.trim().isNotEmpty) ||
          draft.numberValue != null ||
          draft.selectedOptionIds.isNotEmpty ||
          draft.mediaFileIds.isNotEmpty;

      if (!includeUnanswered && !hasData) return;

      final m = <String, dynamic>{'question': questionId};
      if (draft.textValue != null) m['text_value'] = draft.textValue;
      if (draft.numberValue != null) m['number_value'] = draft.numberValue;
      if (draft.selectedOptionIds.isNotEmpty) {
        m['selected_option_ids'] = draft.selectedOptionIds;
      }
      if (draft.mediaFileIds.isNotEmpty) {
        m['media_file_ids'] = draft.mediaFileIds;
      }

      answerList.add(m);
    });

    final payload = {'assignment': assignmentId, 'answers': answerList};

    try {
      final path = submissionId == null
          ? '/api/assignments/submissions/'
          : '/api/assignments/submissions/$submissionId/';

      final resp = submissionId == null
          ? await _dio.post(
              path,
              data: payload,
              options: Options(contentType: Headers.jsonContentType),
            )
          : await _dio.put(
              path,
              data: payload,
              options: Options(contentType: Headers.jsonContentType),
            );

      final data = _normalizeData(resp.data);
      return SubmissionDto.fromJson(data as Map<String, dynamic>);
    } on DioException catch (e) {
      _throwDioError(e, fallback: "保存失败");
    } catch (e) {
      throw ApiException(userMessage: "保存失败，请稍后重试", body: e.toString());
    }
  }

  Future<SubmissionDto> submitSubmission(int submissionId) async {
    try {
      final resp = await _dio.post(
        '/api/assignments/submissions/$submissionId/submit/',
      );
      final data = _normalizeData(resp.data);

      if (data is Map<String, dynamic>) {
        if (data['submission'] is Map<String, dynamic>) {
          return SubmissionDto.fromJson(
            data['submission'] as Map<String, dynamic>,
          );
        }
        if (data.containsKey('id') && data.containsKey('assignment')) {
          return SubmissionDto.fromJson(data);
        }
      }

      throw ApiException(userMessage: '提交成功但未返回提交记录，请刷新后查看状态');
    } on DioException catch (e) {
      _throwDioError(e, fallback: "提交失败");
    } catch (e) {
      throw ApiException(userMessage: "提交失败，请稍后重试", body: e.toString());
    }
  }
}
