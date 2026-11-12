import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'local_server.dart';
import 'screens/startup.dart';
import 'state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WorkGuidelineApp());
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class WorkGuidelineApp extends StatefulWidget {
  const WorkGuidelineApp({super.key});

  @override
  State<WorkGuidelineApp> createState() => _WorkGuidelineAppState();
}

class _WorkGuidelineAppState extends State<WorkGuidelineApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // 창을 닫을 때 PC 단독 모드 서버(DB 포함)를 정상 종료한다
    _lifecycle = AppLifecycleListener(onExitRequested: () async {
      if (AppState.I.settings.mode == 'local') {
        await LocalServer.shutdown(AppState.I.settings);
      }
      return AppExitResponse.exit;
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF1F4E79));
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: '업무표준 관리',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        fontFamily: 'Malgun Gothic',
        visualDensity: VisualDensity.compact,
        inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
      ),
      home: const StartupScreen(),
    );
  }
}
