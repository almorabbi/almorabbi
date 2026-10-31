/// A preview build of the story shelf alone («رف الحكايات»), every bundled
/// story, its paintings read from the server's static files — to see the shelf
/// on an emulator without onboarding a child or writing to the backend.
///
///   flutter build apk --debug -t tool/shelf_demo.dart \
///     --dart-define=API_BASE_URL=https://tg-api.alsaba.cloud
///
/// Not the app: no Firebase, no accounts, no analytics. Never shipped.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:almorabbi/features/program/data/story_models.dart';
import 'package:almorabbi/features/program/screens/story_bookshelf_screen.dart';
import 'package:almorabbi/l10n/app_localizations.dart';
import 'package:almorabbi/l10n/l10n_global.dart';
import 'package:almorabbi/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: _Demo()));
}

class _Demo extends StatefulWidget {
  const _Demo();

  @override
  State<_Demo> createState() => _DemoState();
}

class _DemoState extends State<_Demo> {
  Locale _locale = const Locale('ar');

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    locale: _locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) {
      AppL10n.current = AppLocalizations.of(context);
      return child!;
    },
    home: _Picker(
      language: _locale.languageCode,
      onLanguage: (l) => setState(() => _locale = Locale(l)),
    ),
  );
}

class _Picker extends StatelessWidget {
  const _Picker({required this.language, required this.onLanguage});

  final String language;
  final ValueChanged<String> onLanguage;

  Future<List<Story>> _load() async {
    final file = language == 'en'
        ? 'assets/data/stories_en.json'
        : 'assets/data/stories.json';
    final list = jsonDecode(await rootBundle.loadString(file)) as List;
    return [for (final j in list) Story.fromJson(j as Map<String, dynamic>)];
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: FutureBuilder<List<Story>>(
      key: ValueKey(language),
      future: _load(),
      builder: (context, snap) => snap.hasData
          ? StoryShelf(stories: snap.data!)
          : const SizedBox.shrink(),
    ),
  );
}
