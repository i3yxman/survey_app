// lib/services/api_service.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
  ApiService._internal() : _client = http.Client();

  String? _authBasic; // Basic Auth token
  http.Client _client;

  /// 测试环境可以注入 MockClient
  @visibleForTesting
  set httpClient(http.Client client) {
    _client = client;
  }

  /// 手动设置 Basic Auth（测试时也可以用）
  void setAuthBasic(String basic) {
    _authBasic = basic;
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
          // 后端目前返回：{"non_field_errors":["用户名或密码错误"]}
          final nfe = data['non_field_errors'];
          if (nfe is List && nfe.isNotEmpty) {
            msg = nfe.first.toString();
          } else if (data['detail'] is String) {
            msg = data['detail'] as String;
          }
        }
      } catch (_) {
        // 如果解析失败，就用默认 msg
      }

      throw ApiException(msg);
    }

    // 登录成功后，后端不返回 token，而是继续使用 Basic Auth
    final basicAuth =
        'Basic ${base64Encode(utf8.encode('$username:$password'))}';
    _authBasic = basicAuth;

    return LoginResult.fromJson(jsonDecode(resp.body));
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
          // DRF 常见格式：{"detail": "..."}
          message = data['detail'] as String;
        } else if (data['non_field_errors'] is List &&
            (data['non_field_errors'] as List).isNotEmpty) {
          // 另一种常见格式：{"non_field_errors": ["...", "..."]}
          message = (data['non_field_errors'] as List)
              .map((e) => e.toString())
              .join('\n');
        }
      }
    } catch (_) {
      // 如果解析失败，就保持默认文案
    }

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

  /// 上传媒体文件到后端
  Future<MediaFileDto> uploadMedia({
    required int questionId,
    required String mediaType,
    required Uint8List fileBytes,
    required String filename,
  }) async {
    final url =
        Uri.parse('${Env.apiBaseUrl}/api/assignments/upload-media/');

    final req = http.MultipartRequest('POST', url);

    req.headers['Authorization'] = _authBasic ?? '';

    req.fields['media_type'] = mediaType;
    req.fields['question'] = questionId.toString();

    req.files.add(
      http.MultipartFile.fromBytes(
        'file',
        fileBytes,
        filename: filename,
      ),
    );

    final resp = await _client.send(req);
    final respBody = await resp.stream.bytesToString();

    if (resp.statusCode != 201) {
      throw ApiException('上传媒体失败: ${resp.statusCode} $respBody');
    }

    return MediaFileDto.fromJson(jsonDecode(respBody));
  }

  /// -------------------------
  ///     取消任务（两阶段）
  /// -------------------------
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
}