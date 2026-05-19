import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;
  SettingsService._internal();

  static const String _keyDarkMode = 'dark_mode';
  static const String _keyLanguage = 'language';
  static const String _keyPdfQuality = 'pdf_quality';
  static const String _keyAppLock = 'app_lock';

  late SharedPreferences _prefs;
  bool _isInitialized = false;

  final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);
  final ValueNotifier<Locale> localeNotifier = ValueNotifier(const Locale('en'));

  Future<void> init() async {
    if (_isInitialized) return;
    _prefs = await SharedPreferences.getInstance();
    _isInitialized = true;
    themeNotifier.value = _getThemeModeFromInt(darkMode);
    localeNotifier.value = Locale(language);
  }

  ThemeMode _getThemeModeFromInt(int val) {
    switch (val) {
      case 1: return ThemeMode.light;
      case 2: return ThemeMode.dark;
      default: return ThemeMode.system;
    }
  }

  // Dark Mode: 0 = System, 1 = Light, 2 = Dark
  int get darkMode => _prefs.getInt(_keyDarkMode) ?? 0;
  Future<void> setDarkMode(int value) async {
    await _prefs.setInt(_keyDarkMode, value);
    themeNotifier.value = _getThemeModeFromInt(value);
  }

  String get language => _prefs.getString(_keyLanguage) ?? 'en';
  Future<void> setLanguage(String value) async {
    await _prefs.setString(_keyLanguage, value);
    localeNotifier.value = Locale(value);
  }

  // PDF Quality: 0 = Low, 1 = Medium, 2 = High
  int get pdfQuality => _prefs.getInt(_keyPdfQuality) ?? 2;
  Future<void> setPdfQuality(int value) => _prefs.setInt(_keyPdfQuality, value);

  bool get appLock => _prefs.getBool(_keyAppLock) ?? false;
  Future<void> setAppLock(bool value) => _prefs.setBool(_keyAppLock, value);
}
