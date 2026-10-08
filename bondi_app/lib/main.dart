import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';

import 'screens/journey_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const BondiApp());
}

class BondiApp extends StatelessWidget {
  const BondiApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Subite',
    debugShowCheckedModeBanner: false,
    scrollBehavior: const _MobileScrollBehavior(),
    theme: AppTheme.lightTheme,
    home: const JourneyScreen(),
  );
}

class _MobileScrollBehavior extends MaterialScrollBehavior {
  const _MobileScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}
