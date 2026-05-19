import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'features/auth/screens/splash_screen.dart';
import 'data/services/settings_service.dart';
import 'data/services/storage_service.dart';
import 'core/theme/app_theme.dart';
import 'shared/utils/app_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

void main() async {
  WidgetsBinding widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  // Initialize Settings Service
  final settings = SettingsService();
  await settings.init();

  // Run Recycle Bin Cleanup in background
  StorageService().runRecycleBinCleanup();

  runApp(const DocActionApp());
}

class DocActionApp extends StatelessWidget {
  const DocActionApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService();

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: settings.themeNotifier,
      builder: (context, themeMode, _) {
        return ValueListenableBuilder<Locale>(
          valueListenable: settings.localeNotifier,
          builder: (context, locale, _) {
            // Initialize ScreenUtil for responsive UI and adaptive text
            return ScreenUtilInit(
              designSize: const Size(375, 812), // iPhone X design size as baseline
              minTextAdapt: true,
              splitScreenMode: true,
              builder: (context, child) {
                return MaterialApp(
                  title: 'DocAction',
                  debugShowCheckedModeBanner: false,
                  themeMode: themeMode,
                  locale: locale,
                  localizationsDelegates: const [
                    AppLocalizations.delegate,
                    FlutterQuillLocalizations.delegate,
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  supportedLocales: const [Locale('en'), Locale('hi')],
                  theme: AppTheme.lightTheme,
                  darkTheme: AppTheme.darkTheme,
                  home: const SplashScreen(),
                  // Ensure text scaling works well on desktop/large screens
                  builder: (context, widget) {
                    return MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.noScaling,
                      ),
                      child: widget!,
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}
