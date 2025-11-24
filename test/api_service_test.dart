// test/api_service_test.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:survey_app/config/env.dart';
import 'package:survey_app/models/api_models.dart';
import 'package:survey_app/services/api_service.dart';

// ⭐ 新增：统一用 UTF-8 编码 JSON 响应，避免 Latin1 无法编码中文
http.Response utf8JsonResponse(Object bodyObject, int statusCode) {
  final bodyString = jsonEncode(bodyObject);
  return http.Response.bytes(
    utf8.encode(bodyString),
    statusCode,
    headers: {'Content-Type': 'application/json; charset=utf-8'},
  );
}

void main() {
  group('ApiService Tests', () {
    late ApiService api;

    setUp(() {
      api = ApiService();
    });

    test('login() should parse LoginResult on success', () async {
      api.httpClient = MockClient((request) async {
        expect(
          request.url.toString(),
          '${Env.apiBaseUrl}/api/accounts/login/',
        );
        expect(request.method, 'POST');

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['username'], 'testuser');
        expect(body['password'], 'testpass');

        return utf8JsonResponse({
          'id': 1,
          'username': 'testuser',
          'role': 'staff',
        }, 200);
      });

      final result = await api.login('testuser', 'testpass');

      expect(result, isA<LoginResult>());
      expect(result.id, 1);
      expect(result.username, 'testuser');
      expect(result.role, 'staff');
    });

    test('login() should throw ApiException with non_field_errors message', () async {
      api.httpClient = MockClient((request) async {
        return utf8JsonResponse({
          'non_field_errors': ['用户名或密码错误'],
        }, 400);
      });

      expect(
        () => api.login('baduser', 'badpass'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            '用户名或密码错误',
          ),
        ),
      );
    });

    test('login() should throw generic message when body is not JSON', () async {
      api.httpClient = MockClient((request) async {
        // 这里没中文，用普通 Response 就行
        return http.Response('Server Error', 500);
      });

      expect(
        () => api.login('u', 'p'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('登录失败'),
          ),
        ),
      );
    });

    test('getJobPostings() should return list on success', () async {
      api.setAuthBasic('Basic xxx');

      api.httpClient = MockClient((request) async {
        expect(
          request.url.toString(),
          '${Env.apiBaseUrl}/api/assignments/job-postings/',
        );
        expect(request.method, 'GET');
        expect(request.headers['Authorization'], 'Basic xxx');

        return utf8JsonResponse([
          {
            'id': 1,
            'title': '任务 A',
            'description': 'Desc',
            'status': 'open',
            'client': 10,
            'client_name': 'ClientX',
            'project': 20,
            'project_name': 'Proj',
            'questionnaire': 30,
            'questionnaire_title': 'Q1',
            'created_at': '2024-01-01T00:00:00Z',
          }
        ], 200);
      });

      final list = await api.getJobPostings();
      expect(list.length, 1);
      expect(list.first.id, 1);
      expect(list.first.title, '任务 A');
    });

    test('applyJobPosting() should return map on success', () async {
      api.setAuthBasic('Basic xxx');

      api.httpClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          '${Env.apiBaseUrl}/api/assignments/job-postings/123/apply/',
        );
        expect(request.headers['Authorization'], 'Basic xxx');

        return utf8JsonResponse({'detail': '申请成功'}, 200);
      });

      final res = await api.applyJobPosting(123);
      expect(res['detail'], '申请成功');
    });

    test('cancelJobPostingApply() should return map on success', () async {
      api.setAuthBasic('Basic xxx');

      api.httpClient = MockClient((request) async {
        expect(request.method, 'POST');
        expect(
          request.url.toString(),
          '${Env.apiBaseUrl}/api/assignments/job-postings/123/cancel/',
        );
        expect(request.headers['Authorization'], 'Basic xxx');

        return utf8JsonResponse({'detail': '申请已撤回'}, 200);
      });

      final res = await api.cancelJobPostingApply(123);
      expect(res['detail'], '申请已撤回');
    });
  });
}