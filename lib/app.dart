// lib/app.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/login/login_page.dart';
import 'screens/home/home_page.dart';
import 'providers/auth_provider.dart';
import 'providers/assignment_provider.dart';
import 'providers/job_postings_provider.dart';
import 'theme/app_theme.dart';  // ⭐ 加这一行

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => AssignmentProvider()),
        ChangeNotifierProvider(create: (_) => JobPostingsProvider()),
      ],
      child: MaterialApp(
        title: '调研 App',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),   // ⭐ 使用你自己的全局主题
        initialRoute: '/login',
        routes: {
          '/login': (_) => const LoginPage(),
          '/home': (_) => const HomePage(),
        },
      ),
    );
  }
}