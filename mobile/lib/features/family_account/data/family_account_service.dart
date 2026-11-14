/// Repository wrapper over [TgClient] for «حساب الأسرة» endpoints.
library;

import '../../../api/tg_client.dart';
import 'family_account_models.dart';

class FamilyAccountService {
  const FamilyAccountService(this._client);

  final TgClient _client;

  Future<FamilyAccountStatus> fetchStatus() async =>
      FamilyAccountStatus.fromJson(await _client.fetchMyFamily());

  Future<FamilyCreatedInvite> createInvite({
    String role = 'parent',
    String? displayName,
  }) async =>
      FamilyCreatedInvite.fromJson(
        await _client.createFamilyInvite(role: role, displayName: displayName),
      );

  Future<FamilyAccountStatus> join({
    required String code,
    String role = 'parent',
    String? displayName,
  }) async =>
      FamilyAccountStatus.fromJson(
        await _client.joinFamily(
          code: code,
          role: role,
          displayName: displayName,
        ),
      );

  Future<FamilyAccountStatus> reconfirm() async =>
      FamilyAccountStatus.fromJson(await _client.reconfirmFamilyMember());

  Future<void> leave() async {
    await _client.leaveFamily();
  }

  Future<void> requestChildDeletion(String childName) async {
    await _client.requestPartnerChildDeletion(childName);
  }

  Future<void> confirmChildDeletion(int requestId) async {
    await _client.confirmPartnerChildDeletion(requestId);
  }

  Future<void> dismissChildDeletion(int requestId) async {
    await _client.dismissPartnerChildDeletion(requestId);
  }
}
