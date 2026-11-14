import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:almorabbi/features/family_account/data/family_account_models.dart';
import 'package:almorabbi/features/family_account/data/family_account_service.dart';
import 'package:almorabbi/features/family_account/providers/family_account_providers.dart';
import 'package:almorabbi/features/family_account/screens/family_account_screen.dart';
import 'package:almorabbi/l10n/app_localizations.dart';
import 'package:almorabbi/main.dart' show appConfigProvider;
import 'package:almorabbi/theme/app_theme.dart';

class _FakeFamilyService implements FamilyAccountService {
  _FakeFamilyService(this.status);

  FamilyAccountStatus status;
  String? lastJoinedCode;
  int createInviteCalls = 0;
  int reconfirmCalls = 0;
  int leaveCalls = 0;
  final List<int> dismissedIds = [];
  final List<int> confirmedIds = [];
  final List<String> requestedChildNames = [];

  @override
  Future<FamilyAccountStatus> fetchStatus() async => status;

  @override
  Future<FamilyCreatedInvite> createInvite({
    String role = 'parent',
    String? displayName,
  }) async {
    createInviteCalls += 1;
    return const FamilyCreatedInvite(
      code: 'ABCD-2345',
      expiresAt: '2026-11-14T16:00:00Z',
      ttlMinutes: 15,
    );
  }

  @override
  Future<FamilyAccountStatus> join({
    required String code,
    String role = 'parent',
    String? displayName,
  }) async {
    lastJoinedCode = code;
    status = const FamilyAccountStatus(
      enabled: true,
      inFamily: true,
      selfMember: FamilyMemberInfo(
        role: 'mother',
        displayName: 'أم عمر',
        confirmed: true,
      ),
      partner: FamilyMemberInfo(
        role: 'father',
        displayName: 'أبو عمر',
        confirmed: true,
      ),
    );
    return status;
  }

  @override
  Future<FamilyAccountStatus> reconfirm() async {
    reconfirmCalls += 1;
    status = FamilyAccountStatus(
      enabled: status.enabled,
      inFamily: status.inFamily,
      selfMember: FamilyMemberInfo(
        role: status.selfMember?.role ?? 'parent',
        displayName: status.selfMember?.displayName,
        confirmed: true,
      ),
      partner: status.partner,
      pendingDeletionRequests: status.pendingDeletionRequests,
    );
    return status;
  }

  @override
  Future<void> leave() async {
    leaveCalls += 1;
    status = const FamilyAccountStatus(enabled: true, inFamily: false);
  }

  @override
  Future<void> requestChildDeletion(String childName) async {
    requestedChildNames.add(childName);
  }

  @override
  Future<void> confirmChildDeletion(int requestId) async {
    confirmedIds.add(requestId);
    status = FamilyAccountStatus(
      enabled: status.enabled,
      inFamily: status.inFamily,
      selfMember: status.selfMember,
      partner: status.partner,
      pendingDeletionRequests: status.pendingDeletionRequests
          .where((r) => r.id != requestId)
          .toList(),
    );
  }

  @override
  Future<void> dismissChildDeletion(int requestId) async {
    dismissedIds.add(requestId);
    status = FamilyAccountStatus(
      enabled: status.enabled,
      inFamily: status.inFamily,
      selfMember: status.selfMember,
      partner: status.partner,
      pendingDeletionRequests: status.pendingDeletionRequests
          .where((r) => r.id != requestId)
          .toList(),
    );
  }
}

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required _FakeFamilyService service,
    Locale locale = const Locale('ar'),
    ThemeData? theme,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyAccountServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp(
          locale: locale,
          theme: theme ?? AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const FamilyAccountScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('familySharingEnabledProvider gate', () {
    test('returns false when field absent or false, true when enabled', () async {
      final absentContainer = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWith((ref) async => {'minimum_build_number': 0}),
        ],
      );
      addTearDown(absentContainer.dispose);
      await absentContainer.read(appConfigProvider.future);
      expect(absentContainer.read(familySharingEnabledProvider), isFalse);

      final offContainer = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWith(
            (ref) async => {'family_sharing_enabled': false},
          ),
        ],
      );
      addTearDown(offContainer.dispose);
      await offContainer.read(appConfigProvider.future);
      expect(offContainer.read(familySharingEnabledProvider), isFalse);

      final onContainer = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWith(
            (ref) async => {'family_sharing_enabled': true},
          ),
        ],
      );
      addTearDown(onContainer.dispose);
      await onContainer.read(appConfigProvider.future);
      expect(onContainer.read(familySharingEnabledProvider), isTrue);
    });
  });

  group('FamilyAccountScreen', () {
    testWidgets('locked state renders calm locked notice', (tester) async {
      final svc = _FakeFamilyService(
        const FamilyAccountStatus(enabled: false, inFamily: false),
      );
      await pumpScreen(tester, service: svc);
      expect(
        find.text('مشاركة الأسرة غير متاحة حاليًا على هذا الخادم.'),
        findsOneWidget,
      );
    });

    testWidgets('unpaired: create invite shows code and join transitions to paired',
        (tester) async {
      final svc = _FakeFamilyService(
        const FamilyAccountStatus(enabled: true, inFamily: false),
      );
      await pumpScreen(tester, service: svc);

      await tester.tap(find.byKey(const Key('family_create_invite_btn')));
      await tester.pumpAndSettle();
      expect(svc.createInviteCalls, 1);
      expect(find.text('ABCD-2345'), findsOneWidget);
      expect(find.text('صالح لمدة 15 دقيقة لمرة واحدة فقط'), findsOneWidget);

      final input = find.byKey(const Key('family_join_code_input'));
      await tester.ensureVisible(input);
      await tester.enterText(input, 'ZXCV-BNM2');
      final joinBtn = find.byKey(const Key('family_join_btn'));
      await tester.ensureVisible(joinBtn);
      await tester.tap(joinBtn);
      await tester.pumpAndSettle();

      expect(svc.lastJoinedCode, 'ZXCVBNM2');
      expect(find.text('هاتفا الوالدَين مرتبطان'), findsOneWidget);
      expect(find.textContaining('أبو عمر'), findsOneWidget);
    });

    testWidgets('paired: reconfirm, deletion dismiss/confirm, request & leave',
        (tester) async {
      final svc = _FakeFamilyService(
        const FamilyAccountStatus(
          enabled: true,
          inFamily: true,
          selfMember: FamilyMemberInfo(
            role: 'mother',
            displayName: 'أم عمر',
            confirmed: false,
          ),
          partner: FamilyMemberInfo(
            role: 'father',
            displayName: 'أبو عمر',
            confirmed: true,
          ),
          pendingDeletionRequests: [
            FamilyDeletionRequestItem(
              id: 7,
              childName: 'عمر',
              createdAt: '2026-11-14 12:00:00',
            ),
            FamilyDeletionRequestItem(
              id: 8,
              childName: 'مريم',
              createdAt: '2026-11-14 12:05:00',
            ),
          ],
        ),
      );
      await pumpScreen(tester, service: svc);

      // Reconfirm unconfirmed member.
      expect(find.byKey(const Key('family_reconfirm_btn')), findsOneWidget);
      expect(
        find.text('طلب الوالد الشريك حذف ملف «عمر» على هاتفك أيضًا.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('family_dismiss_del_7')));
      await tester.pumpAndSettle();
      expect(svc.dismissedIds, [7]);

      await tester.tap(find.byKey(const Key('family_confirm_del_8')));
      await tester.pumpAndSettle();
      expect(svc.confirmedIds, [8]);

      await tester.tap(find.byKey(const Key('family_reconfirm_btn')));
      await tester.pumpAndSettle();
      expect(svc.reconfirmCalls, 1);

      // Request partner child deletion now that member is confirmed.
      final reqInput = find.byKey(const Key('family_request_del_input'));
      await tester.ensureVisible(reqInput);
      await tester.enterText(reqInput, 'طارق');
      final reqBtn = find.byKey(const Key('family_request_del_btn'));
      await tester.ensureVisible(reqBtn);
      await tester.tap(reqBtn);
      await tester.pumpAndSettle();
      expect(svc.requestedChildNames, ['طارق']);

      // Wait for confirmation SnackBar to dismiss before tapping bottom button.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Leave family via confirmation dialog.
      final leaveBtn = find.byKey(const Key('family_leave_btn'));
      await tester.ensureVisible(leaveBtn);
      await tester.tap(leaveBtn);
      await tester.pumpAndSettle();
      expect(find.text('مغادرة حساب الأسرة؟'), findsOneWidget);

      await tester.tap(find.text('نعم، غادر الأسرة'));
      await tester.pumpAndSettle();
      expect(svc.leaveCalls, 1);
    });

    testWidgets('renders cleanly in light & dark themes (AR & EN)',
        (tester) async {
      final svc = _FakeFamilyService(
        const FamilyAccountStatus(
          enabled: true,
          inFamily: true,
          selfMember: FamilyMemberInfo(role: 'mother', confirmed: true),
          partner: FamilyMemberInfo(role: 'father', confirmed: true),
        ),
      );

      await pumpScreen(
        tester,
        service: svc,
        locale: const Locale('ar'),
        theme: AppTheme.light(),
      );
      expect(find.text('حساب الأسرة'), findsOneWidget);

      await pumpScreen(
        tester,
        service: svc,
        locale: const Locale('en'),
        theme: AppTheme.dark(),
      );
      expect(find.text('Family account'), findsOneWidget);
      expect(find.text('Paired with partner parent'), findsOneWidget);
    });
  });
}
