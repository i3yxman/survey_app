// test/api_service_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:survey_app/services/api_service.dart';

void main() {
  group('ApiService Helpers', () {
    test('extractUserMessage handles detail/message/list', () {
      expect(
        ApiException.extractUserMessage({'detail': '登录失败'}),
        '登录失败',
      );
      expect(
        ApiException.extractUserMessage({'message': '出错了'}),
        '出错了',
      );
      expect(
        ApiException.extractUserMessage({'non_field_errors': ['用户名或密码错误']}),
        '用户名或密码错误',
      );
    });

    test('setAuthToken strips Token prefix and toggles hasToken', () {
      final api = ApiService();
      api.setAuthToken('Token abc123');
      expect(api.hasToken, isTrue);
      api.clearAuthToken();
      expect(api.hasToken, isFalse);
    });
  });
}
