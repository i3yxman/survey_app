// lib/app.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'theme/app_theme.dart';
import 'screens/login/login_page.dart';
import 'screens/home/home_page.dart';
import 'screens/assignments/assignment_detail_page.dart';
import 'screens/assignments/survey_fill_page.dart';
import 'screens/splash/splash_page.dart';   // ⭐ 新增：引入启动页
import 'providers/auth_provider.dart';
import 'providers/assignment_provider.dart';
import 'providers/job_postings_provider.dart';
import 'providers/location_provider.dart';

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

        /// ⭐ 关键：不再指定 initialRoute='/login'，
        /// 让应用从 SplashPage 启动，由 Splash 决定去登录还是首页
        home: const SplashPage(),

        routes: {
          '/login': (_) => const LoginPage(),
          '/home': (_) => const HomePage(),
          '/assignment-detail': (context) => const AssignmentDetailPage(),
          '/survey-fill': (context) => const SurveyFillPage(),
        },
      ),
    );
  }
}