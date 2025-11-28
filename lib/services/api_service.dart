// lib/services/api_service.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:dio/dio.dart';

import '../config/env.dart';
import '../models/api_models.dart';

/// ApiService 抛出的统一异常
class ApiException implements Exception {
  final String message;
  ApiException(this.message);

  @override
  String toString() => 'ApiException: $message';
}

/// 后端接口统一客户端（单例）
class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  // 构造函数：同时初始化 http.Client 和 Dio
  ApiService._internal()
      : _client = http.Client(),
        _dio = Dio();

  // ================================
  // 字段定义
  // ================================
  String? _authBasic; // Basic Auth token

  http.Client _client;

  // Dio：非 late、非可空，构造函数里直接 new
  final Dio _dio;

  /// 测试环境可以注入 MockClient
  @visibleForTesting
  set httpClient(http.Client client) {
    _client = client;
  }

  /// 手动设置 Basic Auth（测试时也可以用）
  void setAuthBasic(String basic) {
    _authBasic = basic;
    _dio.options.headers['Authorization'] = basic;
  }

  /// 登录接口（POST /api/accounts/login/）
  Future<LoginResult> login(String username, String password) async {
    final url = Uri.parse('${Env.apiBaseUrl}/api/accounts/login/');

    final resp = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    if (resp.statusCode != 200) {
      // 默认提示
      String msg = '登录失败：${resp.statusCode}';

      // 尝试解析后端返回的 JSON，把 non_field_errors / detail 提取出来
      try {
        final data = jsonDecode(resp.body);
        if (data is Map<String, dynamic>) {
          final nfe = data['non_field_errors'];
          if (nfe is List && nfe.isNotEmpty) {
            msg = nfe.first.toString();
          } else if (data['detail'] is String) {
            msg = data['detail'] as String;
          }
        }
      } catch (_) {}

      throw ApiException(msg);
    }

    // 登录成功后，后端不返回 token，而是继续使用 Basic Auth
    final basicAuth =
        'Basic ${base64Encode(utf8.encode('$username:$password'))}';
    _authBasic = basicAuth;
    _dio.options.headers['Authorization'] = basicAuth;

    return LoginResult.fromJson(jsonDecode(resp.body));
  }

  /// 修改密码
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    final url = Uri.parse('${Env.apiBaseUrl}/api/accounts/change-password/');

    final resp = await _client.post(
      url,
      headers: {
        'Authorization': _authBasic ?? '',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'old_password': oldPassword,
        'new_password': newPassword,
      }),
    );

    if (resp.statusCode != 200) {
      String msg = '修改密码失败：${resp.statusCode}';

      try {
        final data = jsonDecode(resp.body);
        if (data is Map<String, dynamic>) {
          // 情况1：ValidationError('原密码不正确') => non_field_errors
          if (data['non_field_errors'] is List &&
              (data['non_field_errors'] as List).isNotEmpty) {
            msg = (data['non_field_errors'] as List).first.toString();
          }
          // 情况2：ValidationError({'old_password': ['原密码不正确']})
          else if (data['old_password'] is List &&
              (data['old_password'] as List).isNotEmpty) {
            msg = (data['old_password'] as List).first.toString();
          }
          // 情况3：新密码不符合规则（长度不够等）
          else if (data['new_password'] is List &&
              (data['new_password'] as List).isNotEmpty) {
            msg = (data['new_password'] as List).first.toString();
          }
          // 情况4：通用 detail
          else if (data['detail'] is String) {
            msg = data['detail'] as String;
          }
        }
      } catch (_) {}

      throw ApiException(msg);
    }
  }

  /// 忘记密码：提交账号标识（用户名 / 手机），让后端返回下一步提示
  Future<String> requestPasswordReset({
    required String identifier,
  }) async {
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
      String msg = '请求失败：${resp.statusCode}';

      try {
        final data = jsonDecode(resp.body);
        if (data is Map<String, dynamic>) {
          // 1）优先用 detail
          if (data['detail'] is String) {
            msg = data['detail'] as String;
          } else {
            // 2）再从字段错误里抓一条人话
            for (final value in data.values) {
              if (value is List && value.isNotEmpty) {
                msg = value.first.toString();
                break;
              } else if (value is String) {
                msg = value;
                break;
              }
            }
          }
        }
      } catch (_) {}

      throw ApiException(msg);
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

  /// 获取“我的任务”
  Future<List<Assignment>> getMyAssignments() async {
    final url = Uri.parse('${Env.apiBaseUrl}/api/assignments/my-assignments/');

    final resp = await _client.get(
      url,
      headers: {
        'Authorization': _authBasic ?? '',
      },
    );

    if (resp.statusCode != 200) {
      throw ApiException('getMyAssignments 失败: ${resp.statusCode}');
    }

    final list = jsonDecode(resp.body) as List<dynamic>;
    return list.map((e) => Assignment.fromJson(e)).toList();
  }

  /// 获取 JobPosting 列表（任务大厅）
  Future<List<JobPosting>> getJobPostings() async {
    final url =
        Uri.parse('${Env.apiBaseUrl}/api/assignments/job-postings/');

    final resp = await _client.get(
      url,
      headers: {
        'Authorization': _authBasic ?? '',
      },
    );

    if (resp.statusCode != 200) {
      throw ApiException('getJobPostings 失败: ${resp.statusCode}');
    }

    final list = jsonDecode(resp.body) as List<dynamic>;
    return list.map((e) => JobPosting.fromJson(e)).toList();
  }

  /// 申请一个任务
  Future<Map<String, dynamic>> applyJobPosting(int postingId) async {
    final url = Uri.parse(
      '${Env.apiBaseUrl}/api/assignments/job-postings/$postingId/apply/',
    );

    final resp = await http.post(
      url,
      headers: {
        'Authorization': _authBasic ?? '',
        'Content-Type': 'application/json',
      },
    );

    // 成功：2xx
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      if (resp.body.isEmpty) return {};
      return jsonDecode(resp.body) as Map<String, dynamic>;
    }

    // 失败：尽量从后端 JSON 里抽出人话
    String message = '任务申请失败';

    try {
      final data = jsonDecode(resp.body);

      if (data is Map<String, dynamic>) {
        if (data['detail'] is String) {
          message = data['detail'] as String;
        } else if (data['non_field_errors'] is List &&
            (data['non_field_errors'] as List).isNotEmpty) {
          message = (data['non_field_errors'] as List)
              .map((e) => e.toString())
              .join('\n');
        }
      }
    } catch (_) {}

    throw ApiException(message);
  }

  /// 撤销申请（未分配前）
  Future<Map<String, dynamic>> cancelJobPostingApply(int postingId) async {
    final url = Uri.parse(
        '${Env.apiBaseUrl}/api/assignments/job-postings/$postingId/cancel/');

    final resp = await _client.post(
      url,
      headers: {
        'Authorization': _authBasic ?? '',
        'Content-Type': 'application/json',
      },
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException(
        'POST /job-postings/$postingId/cancel/ 失败: ${resp.statusCode} ${resp.body}',
      );
    }

    return jsonDecode(resp.body) as Map<String, dynamic>;
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
      'file': MultipartFile.fromBytes(
        fileBytes,
        filename: filename,
      ),
    });

    try {
      final resp = await _dio.post(
        url,
        data: formData,
        options: Options(
          headers: {
            // 双保险：这里也带上 Authorization
            'Authorization': _authBasic ?? '',
          },
        ),
        onSendProgress: (sent, total) {
          if (onProgress != null) {
            onProgress(sent, total);
          }
        },
      );

      final status = resp.statusCode ?? 0;
      if (status != 200 && status != 201) {
        throw ApiException('上传媒体失败: $status ${resp.data}');
      }

      dynamic data = resp.data;
      if (data is String) {
        data = jsonDecode(data);
      }

      return MediaFileDto.fromJson(data as Map<String, dynamic>);
    } on DioException catch (e, stack) {

      final status = e.response?.statusCode;
      final body = e.response?.data;
      throw ApiException('上传媒体失败: $status $body');
    } catch (e, stack) {
      throw ApiException('上传媒体失败: $e');
    }
  }

  /// 批量获取媒体文件详情：根据 id 列表
  Future<List<MediaFileDto>> fetchMediaFilesByIds(List<int> ids) async {
    if (ids.isEmpty) return [];

    final url = Uri.parse(
      '${Env.apiBaseUrl}/api/assignments/media-files/?ids=${ids.join(",")}',
    );

    final resp = await _client.get(
      url,
      headers: {
        'Authorization': _authBasic ?? '',
      },
    );

    if (resp.statusCode != 200) {
      throw ApiException('获取媒体信息失败: ${resp.statusCode} ${resp.body}');
    }

    final list = jsonDecode(resp.body) as List<dynamic>;
    return list
        .map((e) => MediaFileDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// ================== 提交对话（审核沟通）相关接口 ==================

  /// 获取某个 submission 的对话列表（审核沟通 + 系统消息）
  Future<List<SubmissionCommentDto>> fetchSubmissionComments(int submissionId) async {
    final url = Uri.parse(
      '${Env.apiBaseUrl}/api/assignments/submissions/$submissionId/comments/',
    );

    final resp = await _client.get(
      url,
      headers: {
        'Authorization': _authBasic ?? '',
        'Content-Type': 'application/json',
      },
    );

    if (resp.statusCode != 200) {
      throw ApiException(
        '获取提交对话失败: ${resp.statusCode} ${resp.body}',
      );
    }

    final data = jsonDecode(resp.body);
    if (data is! List) {
      throw ApiException('获取提交对话失败：返回格式错误');
    }

    return data
        .map((e) => SubmissionCommentDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 给某个 submission 发表一条评论（评估员或审核员都用这个接口）
  Future<SubmissionCommentDto> createSubmissionComment({
    required int submissionId,
    required String message,
  }) async {
    final url = Uri.parse(
      '${Env.apiBaseUrl}/api/assignments/submissions/$submissionId/comments/',
    );

    final resp = await _client.post(
      url,
      headers: {
        'Authorization': _authBasic ?? '',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'message': message,
      }),
    );

    if (resp.statusCode != 201) {
      throw ApiException(
        '发表评论失败: ${resp.statusCode} ${resp.body}',
      );
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return SubmissionCommentDto.fromJson(data);
  }

  /// 取消任务（两阶段）
  Future<CancelAssignmentResponse> cancelAssignment({
    required int assignmentId,
    bool confirm = false,
  }) async {
    final url = Uri.parse(
      '${Env.apiBaseUrl}/api/assignments/my-assignments/$assignmentId/cancel/?confirm=${confirm ? "true" : "false"}',
    );

    final resp = await _client.post(
      url,
      headers: {
        'Authorization': _authBasic ?? '',
      },
    );

    if (resp.statusCode != 200) {
      throw ApiException('取消任务失败: ${resp.statusCode}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return CancelAssignmentResponse.fromJson(data);
  }

  /// 获取某个任务的提交记录
  Future<List<SubmissionDto>> getSubmissions(int assignmentId) async {
    final url = Uri.parse(
        '${Env.apiBaseUrl}/api/assignments/submissions/?assignment=$assignmentId');

    final resp = await _client.get(
      url,
      headers: {
        'Authorization': _authBasic ?? '',
      },
    );

    if (resp.statusCode != 200) {
      throw ApiException('getSubmissions 失败: ${resp.statusCode}');
    }

    final list = jsonDecode(resp.body) as List<dynamic>;
    return list.map((e) => SubmissionDto.fromJson(e)).toList();
  }

  /// 获取问卷详情（题目 + 选项 + 跳转逻辑）
  Future<QuestionnaireDto> fetchQuestionnaireDetail(
      int questionnaireId) async {
    final url = Uri.parse(
      '${Env.apiBaseUrl}/api/survey/questionnaires/$questionnaireId/',
    );

    final resp = await _client.get(
      url,
      headers: {
        'Authorization': _authBasic ?? '',
      },
    );

    if (resp.statusCode != 200) {
      throw ApiException('获取问卷失败: ${resp.statusCode}');
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
        ? Uri.parse(
            '${Env.apiBaseUrl}/api/assignments/submissions/',
          )
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

      final m = <String, dynamic>{
        'question': questionId,
      };

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

    final headers = <String, String>{
      'Authorization': _authBasic ?? '',
      'Content-Type': 'application/json',
    };

    final resp = submissionId == null
        ? await _client.post(url, headers: headers, body: body)
        : await _client.put(url, headers: headers, body: body);

    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw ApiException('保存提交失败: ${resp.statusCode} ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return SubmissionDto.fromJson(data);
  }
}