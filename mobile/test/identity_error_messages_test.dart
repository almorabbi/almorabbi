import 'dart:io' show SocketException;

import 'package:almorabbi/api/tg_client.dart';
import 'package:almorabbi/features/identity/identity_screen.dart';
import 'package:almorabbi/l10n/app_localizations.dart';
import 'package:almorabbi/models/api_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _TestSessionClient extends TgClient {
  _TestSessionClient()
    : super.forTesting(
        baseUrl: 'https://identity.test',
        httpClient: MockClient(
          (_) async => http.Response('{"ok":true,"linked":false}', 200),
        ),
      );
  @override
  Future<SessionResponse> ensureSession() async =>
      SessionResponse(sessionId: 's', token: 't');
}

void main() {
  // How google_sign_in_android 7.x reports "no Google account on the phone".
  const noCredential = GoogleSignInException(
    code: GoogleSignInExceptionCode.unknownError,
    description: 'No credential available: no accounts',
  );

  for (final locale in const [Locale('ar'), Locale('en')]) {
    final l = lookupAppLocalizations(locale);
    String msg(Object e) => identitySignInErrorMessage(l, e);

    group('$locale', () {
      test('each Google failure gets its own localized message', () {
        final messages = {
          'noCredential': msg(noCredential),
          'provider': msg(
            const GoogleSignInException(
              code: GoogleSignInExceptionCode.providerConfigurationError,
              description: 'Credential Manager not supported.',
            ),
          ),
          'client': msg(
            const GoogleSignInException(
              code: GoogleSignInExceptionCode.clientConfigurationError,
              description: 'serverClientId must be provided on Android',
            ),
          ),
          'ui': msg(
            const GoogleSignInException(
              code: GoogleSignInExceptionCode.uiUnavailable,
            ),
          ),
          'unknown': msg(
            const GoogleSignInException(
              code: GoogleSignInExceptionCode.unknownError,
              description: 'boom',
            ),
          ),
        };
        expect(messages['noCredential'], l.identityErrorNoGoogleAccount);
        expect(messages['provider'], l.identityErrorGoogleUnavailable);
        expect(messages['client'], l.identityErrorAppMisconfigured);
        expect(messages['ui'], l.identityErrorGoogleUi);
        expect(messages['unknown'], l.identityErrorGoogleGeneric);
        expect(messages.values.toSet(), hasLength(messages.length));
        for (final m in messages.values) {
          // Never the raw plugin text or the exception class.
          expect(m, isNot(contains('GoogleSignInException')));
          expect(m, isNot(contains('Credential')));
          expect(m, isNot(contains('serverClientId')));
          expect(m, isNot(contains('boom')));
        }
      });

      test('unsupported authentication reads as Google unavailable', () {
        expect(
          msg(
            UnsupportedError('Google Sign-In authentication is unavailable.'),
          ),
          l.identityErrorGoogleUnavailable,
        );
      });

      test('connectivity keeps its own message', () {
        expect(
          msg(const SocketException('offline')),
          l.identityServerUnreachable,
        );
      });
    });
  }

  test('Arabic messages are Arabic, not the English copy', () {
    final ar = lookupAppLocalizations(const Locale('ar'));
    final en = lookupAppLocalizations(const Locale('en'));
    for (final pair in [
      (ar.identityErrorNoGoogleAccount, en.identityErrorNoGoogleAccount),
      (ar.identityErrorGoogleUnavailable, en.identityErrorGoogleUnavailable),
      (ar.identityErrorAppMisconfigured, en.identityErrorAppMisconfigured),
      (ar.identityErrorGoogleUi, en.identityErrorGoogleUi),
      (ar.identityErrorGoogleGeneric, en.identityErrorGoogleGeneric),
      (ar.identitySignInWithGoogle, en.identitySignInWithGoogle),
      (ar.identityLinkSuccess, en.identityLinkSuccess),
    ]) {
      expect(pair.$1, isNot(pair.$2));
      expect(pair.$1, matches(RegExp(r'[؀-ۿ]')));
    }
    expect(ar.identitySignInWithGoogle, 'سجّل بحساب Google');
    expect(en.identitySignInWithGoogle, 'Sign in with Google');
    expect(ar.identityLinkSuccess, 'تم ربط الحساب 🤍');
    expect(en.identityLinkSuccess, 'Account linked 🤍');
  });

  testWidgets('IdentityScreen shows Sign in with Google button instead of Import my data', (
    tester,
  ) async {
    TgClient.shared = _TestSessionClient();
    addTearDown(() => TgClient.shared = null);
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: IdentityScreen(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('سجّل بحساب Google'), findsOneWidget);
    expect(find.text('استيراد بياناتي'), findsNothing);
  });
}
