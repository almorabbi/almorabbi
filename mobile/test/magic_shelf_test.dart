// «رف الحكايات»: one shelf per series, the next unread book faces out, a
// finished book wears its star, a tap lifts the book into its cover with the
// way in, and reduced motion holds the magic still.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:almorabbi/features/program/data/story_models.dart';
import 'package:almorabbi/features/stories/shelf/magic_shelf.dart';
import 'package:almorabbi/l10n/app_localizations.dart';

Story _book(String id, {String? series, String age = '3-6 سنوات'}) => Story(
      id: id,
      title: 'قصة $id',
      description: 'وصف $id',
      coverImage: '',
      themeColor: '0xFF0D9488',
      ageGroup: age,
      pages: const [],
      series: series,
    );

final _stories = [
  _book('yunus', series: kAnbiyaSeries),
  _book('naml', series: kAnbiyaSeries),
  _book('ghar', series: kSiraSeries),
  _book('kitten'),
  _book('layla'),
];

Future<List<String>> _pump(WidgetTester tester,
    {Set<String> finished = const {}, bool still = false}) async {
  final opened = <String>[];
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    child: MaterialApp(
      locale: const Locale('ar'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: still),
          child: Scaffold(
            body: MagicShelf(
              stories: _stories,
              finished: finished,
              onOpenBook: (s) {
                opened.add(s.id);
                Navigator.of(context).push(BookPullout.route(
                  story: s,
                  onRead: () => opened.add('read:${s.id}'),
                ));
              },
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  return opened;
}

Set<String> _idsOn(WidgetTester tester, ShelfKind kind) => {
      for (final b in tester.widgetList<ShelfBook>(find.descendant(
        of: find.byKey(ValueKey('shelf-${kind.name}')),
        matching: find.byType(ShelfBook),
      )))
        b.story.id,
    };

void main() {
  testWidgets('one shelf per series, in order, every book once', (tester) async {
    await _pump(tester);
    final l10n = await AppLocalizations.delegate.load(const Locale('ar'));
    expect(_idsOn(tester, ShelfKind.prophets), {'yunus', 'naml'});
    expect(_idsOn(tester, ShelfKind.seerah), {'ghar'});
    expect(_idsOn(tester, ShelfKind.tales), {'kitten', 'layla'});
    expect(find.text(l10n.storyShelfSeerah), findsOneWidget);
    double top(ShelfKind k) => tester.getTopLeft(find.byKey(ValueKey('shelf-${k.name}'))).dy;
    expect(top(ShelfKind.prophets), lessThan(top(ShelfKind.seerah)));
    expect(top(ShelfKind.seerah), lessThan(top(ShelfKind.tales)));
  });

  testWidgets('the next unread book faces out; a finished one wears a star', (tester) async {
    await _pump(tester, finished: {'yunus'});
    final books = {for (final b in tester.widgetList<ShelfBook>(find.byType(ShelfBook))) b.story.id: b};
    expect(books['naml']!.facingOut, isTrue);
    expect(books['yunus']!.facingOut, isFalse);
    expect(books['yunus']!.finished, isTrue);
    expect(find.descendant(of: find.byKey(const ValueKey('book-yunus')), matching: find.byIcon(Icons.star_rounded)),
        findsOneWidget);
  });

  testWidgets('a tap lifts the book into its cover, and «نقرؤها معًا» opens it', (tester) async {
    final opened = await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('book-kitten')));
    // The motes and the glow never settle: step the 520 ms lift by hand.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(opened, ['kitten']);
    expect(find.text('وصف kitten'), findsOneWidget);
    // Under a Material: no debug underline on the lifted book's words.
    expect(find.ancestor(of: find.text('وصف kitten'), matching: find.byType(Material)), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('pullout-read')));
    await tester.pump();
    expect(opened, ['kitten', 'read:kitten']);
  });

  testWidgets('reduced motion: no drifting motes', (tester) async {
    await _pump(tester, still: true);
    expect(find.byType(ShelfMotes), findsNothing);
    await _pump(tester);
    expect(find.byType(ShelfMotes), findsOneWidget);
  });
}
