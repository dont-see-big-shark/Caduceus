/// Caduceus — a native client for Hermes Agent.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bench_screen.dart';
import 'agent_shell.dart';
import 'design/theme.dart';
import 'design/tokens.dart';
import 'l10n/app_localizations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 48 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 40;
  WidgetsBinding.instance.addObserver(const _MemoryObserver());
  setupMacosChannel();
  runApp(const CaduceusApp());
}

class _MemoryObserver with WidgetsBindingObserver {
  const _MemoryObserver();

  @override
  void didHaveMemoryPressure() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }
}

/// The macOS menu-bar item and the App menu's Settings… both arrive here.
const macosChannel = MethodChannel('caduceus/macos');

/// One increment per request, so the active tab opens Settings.
final settingsRequest = ValueNotifier<int>(0);

/// The last macOS menu-bar shortcut, replayed to the active workspace:
/// `newSession` / `reconnect` / `refreshSessions`.
final shortcutRequest = ValueNotifier<String?>(null);

/// Handles the native menu bar's commands.
void setupMacosChannel() {
  macosChannel.setMethodCallHandler((call) async {
    if (call.method == 'openSettings') {
      settingsRequest.value++;
    } else if (call.method == 'shortcut' && call.arguments is String) {
      shortcutRequest.value = call.arguments as String;
    }
  });
}

/// Selected locale: null means system default.
final localeNotifier = ValueNotifier<Locale?>(null);

const _localeKey = 'caduceus.locale';

Future<void> loadLocale() async {
  final prefs = await SharedPreferences.getInstance();
  final stored = prefs.getString(_localeKey);
  if (stored == null || stored == 'system') {
    localeNotifier.value = null;
  } else if (stored == 'zh_TW') {
    localeNotifier.value = const Locale('zh', 'TW');
  } else {
    localeNotifier.value = Locale(stored);
  }
}

Future<void> setLocale(Locale? locale) async {
  localeNotifier.value = locale;
  final prefs = await SharedPreferences.getInstance();
  if (locale == null) {
    await prefs.setString(_localeKey, 'system');
  } else if (locale.countryCode == 'TW' || locale.scriptCode == 'Hant') {
    await prefs.setString(_localeKey, 'zh_TW');
  } else {
    await prefs.setString(_localeKey, locale.languageCode);
  }
}

/// Light / dark / follow-the-system, persisted.
///
/// Hard-coding dark was wrong on a Mac: the OS already has an answer, and a
/// client that ignores it looks foreign next to every other window. Kept in a
/// top-level notifier so the toggle can live in the workspace chrome without
/// threading a callback through every screen.
final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

const _themeKey = 'caduceus.themeMode';

Future<void> loadThemeMode() async {
  final prefs = await SharedPreferences.getInstance();
  final stored = prefs.getString(_themeKey);
  themeMode.value =
      ThemeMode.values.where((m) => m.name == stored).firstOrNull ??
      ThemeMode.system;
}

Future<void> setThemeMode(ThemeMode mode) async {
  themeMode.value = mode;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_themeKey, mode.name);
}

const _effectsKey = 'caduceus.reduceEffects';

/// Whether to drop to the degraded material — solid panels, no blur, no
/// aurora.
///
/// The design describes this as automatic on low-end hardware. Flutter cannot
/// honestly tell you what a device can afford — there is no GPU tier to read,
/// and guessing from the model name is how apps end up degrading a phone that
/// was perfectly capable. So it is a setting, and the person holding the
/// device decides.
///
/// It existed as a fully implemented, fully tested code path that **nothing
/// could turn on**: `Materials.degraded` was written only by a unit test. A
/// fallback nobody can reach is not a fallback.
Future<void> loadReduceEffects() async {
  final prefs = await SharedPreferences.getInstance();
  Materials.degraded.value = prefs.getBool(_effectsKey) ?? false;
}

Future<void> setReduceEffects(bool value) async {
  Materials.degraded.value = value;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_effectsKey, value);
}

class CaduceusApp extends StatefulWidget {
  const CaduceusApp({super.key});

  @override
  State<CaduceusApp> createState() => _CaduceusAppState();
}

class _CaduceusAppState extends State<CaduceusApp> {
  @override
  void initState() {
    super.initState();
    loadLocale();
    loadThemeMode();
    loadReduceEffects();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale?>(
      valueListenable: localeNotifier,
      builder: (context, currentLocale, _) => ValueListenableBuilder<ThemeMode>(
        valueListenable: themeMode,
        builder: (context, mode, _) => MaterialApp(
          title: 'Caduceus',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: caduceusTheme(Brightness.light),
          darkTheme: caduceusTheme(Brightness.dark),
          locale: currentLocale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          // The page is the design's flat background (`--bg`): near-black in
          // dark mode, the same step-deeper paper the light theme always used
          // under its sheets. The old animated aurora was removed — it
          // repainted the whole surface every frame and stole the frame
          // budget from scrolling and streaming.
          builder: (context, child) => ColoredBox(
            color: Theme.of(context).brightness == Brightness.dark
                ? Palette.voidBlack
                : const Color(0xFFE4E7EF),
            child: child ?? const SizedBox(),
          ),
          home: kBench ? const BenchScreen() : const AgentShell(),
        ),
      ),
    );
  }
}

/// Render benchmark instead of the app. Profile mode only.
const kBench = bool.fromEnvironment('BENCH');
