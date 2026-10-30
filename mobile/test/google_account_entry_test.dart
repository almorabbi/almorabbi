// «حساب Google» is switched off (identity_entry.dart): no menu may still lead
// to a sign-in that fails on Play builds.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:almorabbi/features/hub/data/hub_catalog.dart';
import 'package:almorabbi/features/identity/identity_entry.dart';

void main() {
  test('the hub has no account tile while the entry is off', () {
    final ids = [for (final g in kHubGroups) for (final i in g.items) i.id];
    expect(ids.contains('identity'), kGoogleAccountEntryEnabled);
  });

  test('every route to the identity screen is behind the switch', () {
    // Each file that pushes AppRoutes.identity must also read the switch.
    for (final path in [
      'lib/features/program/screens/settings_screen.dart',
      'lib/features/hub/widgets/help_sheet.dart',
      'lib/features/hub/data/hub_catalog.dart',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src.contains('AppRoutes.identity'), isTrue, reason: path);
      expect(src.contains('kGoogleAccountEntryEnabled'), isTrue, reason: path);
    }
    final others = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains('AppRoutes.identity'))
        .map((f) => f.path.replaceAll('\\', '/'))
        .where((p) => !p.endsWith('settings_screen.dart') &&
            !p.endsWith('help_sheet.dart') &&
            !p.endsWith('hub_catalog.dart'))
        .toList();
    expect(others, isEmpty, reason: 'a new entry to the account screen');
  });
}
