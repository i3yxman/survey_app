// lib/app.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart'; // ✅ 新增

import 'theme/app_theme.dart';
import 'screens/login/login_page.dart';
import 'screens/home/home_page.dart';
import 'screens/assignments/assignment_detail_page.dart';
import 'screens/assignments/survey_fill_page.dart';
import 'screens/job_postings/job_posting_detail_page.dart';
import 'screens/splash/splash_page.dart';
import 'screens/login/forgot_password_page.dart';
import 'screens/account/change_password_page.dart';
import 'providers/auth_provider.dart';
import 'providers/assignment_provider.dart';
import 'providers/job_postings_provider.dart';
import 'providers/location_provider.dart';
import 'main.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => AssignmentProvider()),
        ChangeNotifierProvider(create: (_) => JobPostingsProvider()),
        ChangeNotifierProvider(create: (_) => LocationProvider()),
      ],
      child: MaterialApp(
        title: '调研 App',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,

        // ✅ 中文本地化
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],

        navigatorObservers: [routeObserver],
        home: const SplashPage(),

        routes: {
          '/login': (_) => const LoginPage(),
          '/home': (_) => const HomePage(),
          '/assignment-detail': (_) => const AssignmentDetailPage(),
          '/job-posting-detail': (_) => const JobPostingDetailPage(),
          '/survey-fill': (_) => const SurveyFillPage(),
          '/forgot-password': (_) => const ForgotPasswordPage(),
          '/change-password': (_) => const ChangePasswordPage(),
        },
      ),
    );
  }
}
