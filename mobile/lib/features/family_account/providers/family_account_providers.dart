/// Riverpod providers for «حساب الأسرة» (2.0 M3).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../main.dart' show appConfigProvider;
import '../../../state/chat_notifier.dart' show tgClientProvider;
import '../data/family_account_models.dart';
import '../data/family_account_service.dart';

/// Server-driven visibility gate (`/api/app-config` -> `family_sharing_enabled`).
final familySharingEnabledProvider = Provider<bool>((ref) {
  final cfg = ref.watch(appConfigProvider).valueOrNull;
  return cfg?['family_sharing_enabled'] == true;
});

final familyAccountServiceProvider = Provider<FamilyAccountService>(
  (ref) => FamilyAccountService(ref.watch(tgClientProvider)),
);

final familyAccountStatusProvider =
    FutureProvider.autoDispose<FamilyAccountStatus>(
  (ref) => ref.watch(familyAccountServiceProvider).fetchStatus(),
);
