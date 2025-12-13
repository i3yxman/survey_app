// lib/services/api_service.dart

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';

import '../config/env.dart';
import '../models/api_models.dart';

/// ApiService 抛出的统一异常
class ApiException implements Exception {
  final int? statusCode;
  final dynamic body; // Map/List/String
  final String userMessage; // 给用户看的“人话”

  ApiException({required this.userMessage, this.statusCode, this.body});

  String get message => userMessage; // ✅ 新增：兼容旧代码里 e.message

  @override
  String toString() => userMessage;

  static String extractUserMessage(dynamic data) {
    try {
      // 0) 空
      if (data == null) return "操作失败，请稍后再试";

      // 1) 后端返回 {message: "..."}（你自定义时可用）
      if (data is Map && data["message"] is String) {
        return (data["message"] as String).trim();
      }

      // 2) DRF 默认 {detail: "..."}
      if (data is Map && data["detail"] != null) {
        final d = data["detail"];
        if (d is String) return d.trim();
        if (d is Map && d["message"] is String) {
          return (d["message"] as String).trim();
        }
      }

      // 3) DRF 字段校验错误 {field: ["..."]} 或 {field: "..."}
      if (data is Map) {
        for (final entry in data.entries) {
          final v = entry.value;
          if (v is List && v.isNotEmpty) return v.first.toString().trim();
          if (v is String && v.trim().isNotEmpty) return v.trim();
        }
      }

      // 4) 如果是字符串 JSON，尝试 decode
      if (data is String) {
        final s = data.trim();
        if (s.isEmpty) return "操作失败，请稍后再试";
        try {
          final decoded = json.decode(s);
          return extractUserMessage(decoded);
        } catch (_) {
          // 非 JSON 字符串
          return s;
        }
      }
    } catch (_) {}

    return "操作失败，请稍后再试";
  }
}

/// 后端接口统一客户端（单例）
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  // 构造函数：同时初始化 http.Client 和 Dio
  ApiService._internal() : _client = http.Client(), _dio = Dio();

  // ================================
  // 字段定义
  // ================================
  String? _authToken; // DRF TokenAuthentication: "Token <key>"

  http.Client _client;

  // Dio：非 late、非可空，构造函数里直接 new
  final Dio _dio;

  dynamic _tryDecode(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    try {
      return jsonDecode(t);
    } catch (_) {
      return t;
    }
  }

  Never _throwHttpResponseError(
    http.Response resp, {
    String fallback = "请求失败",
  }) {
    final data = _tryDecode(resp.body);
    final msg = ApiException.extractUserMessage(data);

    throw ApiException(
      userMessage: (msg.isNotEmpty ? msg : fallback),
      statusCode: resp.statusCode,
      body: data,
    );
  }

  Never _throwDioError(DioException e, {String fallback = "请求失败"}) {
    final status = e.response?.statusCode;
    final data = e.response?.data;

    // dio 的 data 可能已经是 Map/List，也可能是 String
    final normalized = (data is String) ? _tryDecode(data) : data;
    final msg = ApiException.extractUserMessage(normalized);

    throw ApiException(
      userMessage: (msg.isNotEmpty ? msg : fallback),
      statusCode: status,
      body: normalized,
    );
  }

  /// 用于把服务端 500 / 网络异常转成用户能懂的一句话
  Never _throwUnknown(Object e, {String fallback = "网络异常，请稍后重试"}) {
    throw ApiException(userMessage: fallback, body: e.toString());
  }

  /// 测试环境可以注入 MockClient
  @visibleForTesting
  set httpClient(http.Client client) {
    _client = client;
  }

  /// 手动设置 Token（登录成功后会调用；测试时也可以用）
  void setAuthToken(String token) {
    var t = token.trim();

    // ✅ 兼容后端直接返回 "Token xxx"
    t = t.replaceFirst(RegExp(r'^Token\s+', caseSensitive: false), '');

    _authToken = t;

    if (t.isEmpty) {
      _dio.options.headers.remove('Authorization');
      return;
    }

    _dio.options.headers['Authorization'] = 'Token $t';
  }

  Map<String, String> _authHeaders({bool json = false}) {
    final h = <String, String>{};
    if (_authToken != null && _authToken!.isNotEmpty) {
      h['Authorization'] = 'Token $_authToken';
    }
    if (json) h['Content-Type'] = 'application/json';
    return h;
  }

  /// ✅ 是否已有 token
  bool get hasToken => _authToken != null && _authToken!.isNotEmpty;

  /// ✅ 清空 token（退出/过期）
  void clearAuthToken() {
    _authToken = null;
    _dio.options.headers.remove('Authorization');
  }

  /// 登录接口（POST /api/accounts/login/）
  Future<LoginResult> login(String identifier, String password) async {
    final url = Uri.parse('${Env.apiBaseUrl}/api/accounts/login/');

    final resp = await _client.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'identifier': identifier, 'password': password}),
    );

    if (resp.statusCode != 200) {
      _throwHttpResponseError(resp, fallback: "登录失败");
    }

    final data = jsonDecode(resp.body);
    final result = LoginResult.fromJson(data);

    // ✅ 后端返回 token：保存并用于后续所有请求
    if (result.token.isEmpty) {
      throw ApiException(userMessage: "登录失败：未返回 token");
    }
    setAuthToken(result.token);

    return result;
  }

  /// 修改密码
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final url = Uri.parse('${Env.apiBaseUrl}/api/accounts/change-password/');

    final resp = await _client.post(
      url,
      headers: _authHeaders(json: true),
      body: jsonEncode({
        'old_password': oldPassword,
        'new_password': newPassword,
      }),
    );

    if (resp.statusCode != 200) {
      _throwHttpResponseError(resp, fallback: "修改密码失败");
    }
  }

  /// 忘记密码：提交账号标识（用户名 / 手机），让后端返回下一步提示
  Future<String> requestPasswordReset({required String identifier}) async {
    final url = Uri.parse('${Env.apiBaseUrl}/api/accounts/forgot-password/');

    final resp = await _client.post(
      url,
      headers: {
        // 忘记密码通常不需要登录，可以不带 Authorization
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        // 👈 和后端 ForgotPasswordSerializer.identifier 对齐
        'identifier': identifier,
      }),
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      _throwHttpResponseError(resp, fallback: "请求失败");
    }

    // 成功时返回后端给的 detail 文案（比如“系统已记录你的请求，请联系管理员 XXX”）
    try {
      final data = jsonDecode(resp.body);
      if (data is Map<String, dynamic> && data['detail'] is String) {
        return data['detail'] as String;
      }
    } catch (_) {}

    return '操作成功';
  }

  /// 获取当前登录用户信息（GET /api/accounts/me/）
  Future<Map<String, dynamic>> me() async {
    final url = Uri.parse('${Env.apiBaseUrl}/api/accounts/me/');

    final resp = await _client.get(url, headers: _authHeaders());

    if (resp.statusCode != 200) {
      _throwHttpResponseError(resp, fallback: "获取用户信息失败");
    }

    final data = jsonDecode(resp.body);
    if (data is! Map<String, dynamic>) {
      throw ApiException(userMessage: "获取用户信息失败：返回格式错误");
    }
    return data;
  }

  /// 获取“我的任务”
  Future<List<Assignment>> getMyAssignments() async {
    final url = Uri.parse('${Env.apiBaseUrl}/api/assignments/my-assignments/');
    final headers = _authHeaders();

    final resp = await _client.get(url, headers: headers);

    if (resp.statusCode != 200) {
      _throwHttpResponseError(resp, fallback: "获取任务列表失败");
    }

    final list = jsonDecode(resp.body) as List<dynamic>;
    return list.map((e) => Assignment.fromJson(e)).toList();
  }

  /// 获取 JobPosting 列表（任务大厅）
  Future<List<JobPosting>> getJobPostings() async {
    final url = Uri.parse('${Env.apiBaseUrl}/api/assignments/job-postings/');
    final headers = _authHeaders();

    final resp = await _client.get(url, headers: headers);

    if (resp.statusCode != 200) {
      _throwHttpResponseError(resp, fallback: "获取任务大厅失败");
    }

    final list = jsonDecode(resp.body) as List<dynamic>;
    return list.map((e) => JobPosting.fromJson(e)).toList();
  }

  /// 申请一个任务
  Future<Map<String, dynamic>> applyJobPosting(int postingId) async {
    final url = Uri.parse(
      '${Env.apiBaseUrl}/api/assignments/job-postings/$postingId/apply/',
    );

    try {
      final resp = await _client.post(url, headers: _authHeaders());

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        _throwHttpResponseError(resp, fallback: "任务申请失败");
      }

      if (resp.body.isEmpty) return {};
      final data = jsonDecode(resp.body);
      if (data is Map<String, dynamic>) return data;
      return {};
    } catch (e) {
      _throwUnknown(e, fallback: "任务申请失败，请稍后重试");
    }
  }

  /// 撤销申请（未分配前）
  Future<Map<String, dynamic>> cancelJobPostingApply(int postingId) async {
    final url = Uri.parse(
      '${Env.apiBaseUrl}/api/assignments/job-postings/$postingId/cancel/',
    );

    try {
      final resp = await _client.post(url, headers: _authHeaders());

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        _throwHttpResponseError(resp, fallback: "撤销申请失败");
      }

      return jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      if (e is ApiException) rethrow;
      _throwUnknown(e, fallback: "撤销申请失败，请稍后重试");
    }
  }

  /// 上传媒体文件到后端（带进度）
  Future<MediaFileDto> uploadMedia({
    required int questionId,
    required String mediaType,
    required Uint8List fileBytes,
    required String filename,
    void Function(int sent, int total)? onProgress,
  }) async {
    final url = '${Env.apiBaseUrl}/api/assignments/upload-media/';

    final formData = FormData.fromMap({
      'media_type': mediaType,
      'question': questionId.toString(),
      'file': MultipartFile.fromBytes(fileBytes, filename: filename),
    });

    try {
      final resp = await _dio.post(
        url,
        data: formData,
        options: Options(headers: _authHeaders()),
        onSendProgress: (sent, total) {
          onProgress?.call(sent, total);
        },
      );

      final status = resp.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        // 这里不用拼字符串，走统一提取
        final msg = ApiException.extractUserMessage(resp.data);
        throw ApiException(
          userMessage: msg.isNotEmpty ? msg : "上传媒体失败",
          statusCode: status,
          body: resp.data,
        );
      }

      dynamic data = resp.data;
      if (data is String) data = _tryDecode(data);
      return MediaFileDto.fromJson(data as Map<String, dynamic>);
    } on DioException catch (e) {
      _throwDioError(e, fallback: "上传媒体失败");
    } catch (e) {
      _throwUnknown(e, fallback: "上传媒体失败，请稍后重试");
    }
  }

  /// 批量获取媒体文件详情：根据 id 列表
  Future<List<MediaFileDto>> fetchMediaFilesByIds(List<int> ids) async {
    if (ids.isEmpty) return [];

    final url = Uri.parse(
      '${Env.apiBaseUrl}/api/assignments/media-files/?ids=${ids.join(",")}',
    );

    try {
      final resp = await _client.get(url, headers: _authHeaders());

      if (resp.statusCode != 200) {
        _throwHttpResponseError(resp, fallback: "获取媒体信息失败");
      }

      final list = jsonDecode(resp.body) as List<dynamic>;
      return list
          .map((e) => MediaFileDto.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (e is ApiException) rethrow;
      _throwUnknown(e, fallback: "获取媒体信息失败，请稍后重试");
    }
  }

  /// ================== 提交对话（审核沟通）相关接口 ==================

  /// 获取某个 submission 的对话列表（审核沟通 + 系统消息）
  Future<List<SubmissionCommentDto>> fetchSubmissionComments(
    int submissionId,
  ) async {
    final url = Uri.parse(
      '${Env.apiBaseUrl}/api/assignments/submissions/$submissionId/comments/',
    );

    try {
      final resp = await _client.get(url, headers: _authHeaders());

      if (resp.statusCode != 200) {
        _throwHttpResponseError(resp, fallback: "加载沟通记录失败");
      }

      final data = jsonDecode(resp.body);
      if (data is! List) {
        throw ApiException(userMessage: "加载沟通记录失败：返回格式错误");
      }

      return data
          .map((e) => SubmissionCommentDto.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (e is ApiException) rethrow;
      _throwUnknown(e, fallback: "加载沟通记录失败，请稍后重试");
    }
  }

  /// 给某个 submission 发表一条评论（评估员或审核员都用这个接口）
  Future<SubmissionCommentDto> createSubmissionComment({
    required int submissionId,
    required String message,
  }) async {
    final url = Uri.parse(
      '${Env.apiBaseUrl}/api/assignments/submissions/$submissionId/comments/',
    );

    try {
      final resp = await _client.post(
        url,
        headers: _authHeaders(json: true),
        body: jsonEncode({'message': message}),
      );

      if (resp.statusCode != 201) {
        _throwHttpResponseError(resp, fallback: "发送失败");
      }

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return SubmissionCommentDto.fromJson(data);
    } catch (e) {
      if (e is ApiException) rethrow;
      _throwUnknown(e, fallback: "发送失败，请稍后重试");
    }
  }

  /// 取消任务（两阶段）
  Future<CancelAssignmentResponse> cancelAssignment({
    required int assignmentId,
    bool confirm = false,
  }) async {
    final url = Uri.parse(
      '${Env.apiBaseUrl}/api/assignments/my-assignments/$assignmentId/cancel/?confirm=${confirm ? "true" : "false"}',
    );

    final resp = await _client.post(url, headers: _authHeaders());

    if (resp.statusCode != 200) {
      _throwHttpResponseError(resp, fallback: "取消任务失败");
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return CancelAssignmentResponse.fromJson(data);
  }

  /// 获取某个任务的提交记录
  Future<List<SubmissionDto>> getSubmissions(int assignmentId) async {
    final url = Uri.parse(
      '${Env.apiBaseUrl}/api/assignments/submissions/?assignment=$assignmentId',
    );

    final resp = await _client.get(url, headers: _authHeaders());

    if (resp.statusCode != 200) {
      _throwHttpResponseError(resp, fallback: "获取提交记录失败");
    }

    final list = jsonDecode(resp.body) as List<dynamic>;
    return list.map((e) => SubmissionDto.fromJson(e)).toList();
  }

  /// 获取问卷详情（题目 + 选项 + 跳转逻辑）
  Future<QuestionnaireDto> fetchQuestionnaireDetail(int questionnaireId) async {
    final url = Uri.parse(
      '${Env.apiBaseUrl}/api/survey/questionnaires/$questionnaireId/',
    );

    final resp = await _client.get(url, headers: _authHeaders());

    if (resp.statusCode != 200) {
      _throwHttpResponseError(resp, fallback: "获取问卷失败");
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return QuestionnaireDto.fromJson(data);
  }

  /// 保存提交（草稿 / 提交）
  Future<SubmissionDto> saveSubmission({
    int? submissionId,
    required int assignmentId,
    required String status, // 'draft' / 'submitted'
    required Map<int, AnswerDraft> answers,
    bool includeUnanswered = false,
  }) async {
    final url = submissionId == null
        ? Uri.parse('${Env.apiBaseUrl}/api/assignments/submissions/')
        : Uri.parse(
            '${Env.apiBaseUrl}/api/assignments/submissions/$submissionId/',
          );

    // 把 AnswerDraft 映射成后端需要的 AnswerInputSerializer 结构
    final answerList = <Map<String, dynamic>>[];

    answers.forEach((questionId, draft) {
      final hasData =
          (draft.textValue != null && draft.textValue!.trim().isNotEmpty) ||
          draft.numberValue != null ||
          draft.selectedOptionIds.isNotEmpty ||
          draft.mediaFileIds.isNotEmpty;

      if (!includeUnanswered && !hasData) {
        return;
      }

      final m = <String, dynamic>{'question': questionId};

      if (draft.textValue != null) {
        m['text_value'] = draft.textValue;
      }
      if (draft.numberValue != null) {
        m['number_value'] = draft.numberValue;
      }
      if (draft.selectedOptionIds.isNotEmpty) {
        m['selected_option_ids'] = draft.selectedOptionIds;
      }
      if (draft.mediaFileIds.isNotEmpty) {
        m['media_file_ids'] = draft.mediaFileIds;
      }

      answerList.add(m);
    });

    final body = jsonEncode({
      'assignment': assignmentId,
      'status': status,
      'answers': answerList,
    });

    final headers = _authHeaders(json: true);

    final resp = submissionId == null
        ? await _client.post(url, headers: headers, body: body)
        : await _client.put(url, headers: headers, body: body);

    if (resp.statusCode != 200 && resp.statusCode != 201) {
      _throwHttpResponseError(resp, fallback: "保存失败");
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return SubmissionDto.fromJson(data);
  }
}
