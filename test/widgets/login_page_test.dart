// test/widgets/login_page_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:survey_app/screens/login/login_page.dart';
import 'package:survey_app/providers/auth_provider.dart';
import 'package:survey_app/providers/location_provider.dart';

void main() {
  group('LoginPage Widget Tests', () {
    testWidgets('初始渲染时显示标题和登录按钮', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => AuthProvider()),
              ChangeNotifierProvider(create: (_) => LocationProvider()),
            ],
            child: const LoginPage(),
          ),
        ),
      );

      expect(find.text('神秘顾客调研平台'), findsOneWidget);
      expect(find.text('登录'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
    });

    testWidgets('登录时用户名为空会提示错误', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => AuthProvider()),
              ChangeNotifierProvider(create: (_) => LocationProvider()),
            ],
            child: const LoginPage(),
          ),
        ),
      );

      // 只输入密码，用户名留空
      final passwordField = find.byType(TextField).at(1);
      await tester.enterText(passwordField, 'password123');

      // 点“登录”
      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();

      // 断言：出现“用户名或密码不能为空”之类的错误提示
      expect(find.text('账号和密码不能为空'), findsOneWidget);
    });

    testWidgets('登录时密码为空会提示错误', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => AuthProvider()),
              ChangeNotifierProvider(create: (_) => LocationProvider()),
            ],
            child: const LoginPage(),
          ),
        ),
      );

      // 只输入用户名，密码留空
      final usernameField = find.byType(TextField).first;
      await tester.enterText(usernameField, 'tester');

      // 点“登录”
      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();

      // 断言：出现“用户名或密码不能为空”之类的错误提示
      expect(find.text('账号和密码不能为空'), findsOneWidget);
    });
  });
}
