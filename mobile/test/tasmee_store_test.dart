// «تسميع مع الوالد» (docs/TASMEE_WITH_PARENT.md) — what the parent marked,
// what stays open for review, and when it is due.
import 'dart:convert';
import 'dart:io';

import 'package:almorabbi/features/journey/data/tasmee_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

TasmeeSession _s(
  String at,
  List<TasmeeMark> marks, {
  int from = 1,
  int to = 4,
}) => TasmeeSession(at: DateTime.parse(at), from: from, to: to, marks: marks);

const _omit = TasmeeMark(ayah: 2, word: 1, type: SlipType.omit);
const _swap = TasmeeMark(ayah: 4, word: 0, type: SlipType.swap);

void main() {
  group('open slips', () {
    test('a later clean session that covers the verse clears the word', () {
      final s = [
        _s('2026-11-01T19:00', [_omit, _swap]),
        _s('2026-11-02T19:00', []),
      ];
      expect(openSlips(s), isEmpty);
    });

    test('a clean session that did not cover the verse leaves it open', () {
      final s = [
        _s('2026-11-01T19:00', [_omit, _swap]),
        _s('2026-11-02T19:00', [], from: 1, to: 3), // verse 4 not recited
      ];
      expect(openSlips(s), {'4:0': SlipType.swap});
    });

    test('the latest mark on a word wins', () {
      final s = [
        _s('2026-11-01T19:00', [_omit]),
        _s('2026-11-02T19:00', [
          const TasmeeMark(ayah: 2, word: 1, type: SlipType.hesitate),
        ]),
      ];
      expect(openSlips(s), {'2:1': SlipType.hesitate});
    });

    test('order is by time, not by list order', () {
      final s = [
        _s('2026-11-02T19:00', []),
        _s('2026-11-01T19:00', [_omit]),
      ];
      expect(openSlips(s), isEmpty);
    });
  });

  group('review day', () {
    test('nothing open, nothing due', () {
      expect(reviewDue([_s('2026-11-01T19:00', [])]), isNull);
      expect(reviewDue(const []), isNull);
    });

    test('one day, then three, then seven while slips keep coming', () {
      final a = _s('2026-11-01T19:00', [_omit]);
      final b = _s('2026-11-02T19:00', [_omit]);
      final c = _s('2026-11-05T19:00', [_omit]);
      final d = _s('2026-11-12T19:00', [_omit]);
      expect(reviewDue([a]), DateTime(2026, 11, 2));
      expect(reviewDue([a, b]), DateTime(2026, 11, 5));
      expect(reviewDue([a, b, c]), DateTime(2026, 11, 12));
      expect(reviewDue([a, b, c, d]), DateTime(2026, 11, 19));
    });

    test('a clean session starts the count again for what is still open', () {
      final s = [
        _s('2026-11-01T19:00', [_omit, _swap]),
        _s('2026-11-02T19:00', [_omit], from: 1, to: 2), // verse 4 not recited
        _s('2026-11-05T19:00', [], from: 1, to: 3), // clears 2:1, not 4:0
      ];
      expect(openSlips(s), {'4:0': SlipType.swap});
      expect(reviewDue(s), DateTime(2026, 11, 6));
    });

    test('due on the day itself, by date not by hour', () {
      final s = [
        _s('2026-11-01T23:30', [_omit]),
      ];
      expect(isDue(s, DateTime(2026, 11, 1, 23, 59)), isFalse);
      expect(isDue(s, DateTime(2026, 11, 2, 0, 1)), isTrue);
    });
  });

  group('store', () {
    test(
      'keeps sessions per child and surah, newest last, at most 20',
      () async {
        SharedPreferences.setMockInitialValues({});
        final store = TasmeeStore(await SharedPreferences.getInstance());
        for (var i = 0; i < 23; i++) {
          await store.add(
            7,
            112,
            _s('2026-11-01T10:${i.toString().padLeft(2, '0')}', [_omit]),
          );
        }
        await store.add(8, 1, _s('2026-11-01T09:00', []));
        final mine = store.loadForChild(7);
        expect(mine.keys, [112]);
        expect(mine[112]!.length, TasmeeStore.maxSessions);
        expect(mine[112]!.first.at, DateTime.parse('2026-11-01T10:03'));
        expect(mine[112]!.last.marks.single.type, SlipType.omit);
        expect(store.loadForChild(8)[1]!.single.marks, isEmpty);
      },
    );

    test(
      'a damaged blob reads as nothing, and bad entries are skipped',
      () async {
        SharedPreferences.setMockInitialValues({TasmeeStore.key: '{not json'});
        expect(
          TasmeeStore(await SharedPreferences.getInstance()).loadForChild(7),
          isEmpty,
        );
        SharedPreferences.setMockInitialValues({
          TasmeeStore.key: jsonEncode({
            '7': {
              '112': [
                {'at': 'x', 'from': 1, 'to': 4, 'marks': []},
                {
                  'at': '2026-11-01T10:00',
                  'from': 1,
                  'to': 4,
                  'marks': [
                    {'ayah': 2, 'word': 1, 'type': 'omit'},
                    {'ayah': 2, 'type': 'bogus'},
                  ],
                },
              ],
            },
          }),
        });
        final got = TasmeeStore(
          await SharedPreferences.getInstance(),
        ).loadForChild(7)[112]!;
        expect(got.single.marks.single.type, SlipType.omit);
      },
    );
  });

  test('every verse of the mushaf splits into words, never a bare mark', () {
    final quran =
        jsonDecode(File('assets/data/quran.json').readAsStringSync())
            as Map<String, dynamic>;
    final letter = RegExp(r'[ء-يٱ]');
    var verses = 0;
    for (final surah in quran.values) {
      for (final v in surah as List) {
        verses++;
        for (final w in ayahWords('${v['text']}')) {
          expect(
            letter.hasMatch(w),
            isTrue,
            reason: '${v['chapter']}:${v['verse']} «$w»',
          );
        }
      }
    }
    expect(verses, 6236);
  });
}
