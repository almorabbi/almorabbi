/// Immutable models for «حساب الأسرة» dual-parent sharing (2.0 M3).
library;

class FamilyMemberInfo {
  const FamilyMemberInfo({
    required this.role,
    this.displayName,
    required this.confirmed,
    this.joinedAt,
  });

  final String role;
  final String? displayName;
  final bool confirmed;
  final String? joinedAt;

  factory FamilyMemberInfo.fromJson(Map<String, dynamic> json) {
    return FamilyMemberInfo(
      role: json['role']?.toString() ?? 'parent',
      displayName: json['display_name']?.toString(),
      confirmed: json['confirmed'] == true,
      joinedAt: json['joined_at']?.toString(),
    );
  }
}

class FamilyActiveInvite {
  const FamilyActiveInvite({
    required this.hasActive,
    required this.expiresAt,
  });

  final bool hasActive;
  final String expiresAt;

  factory FamilyActiveInvite.fromJson(Map<String, dynamic> json) {
    return FamilyActiveInvite(
      hasActive: json['has_active'] == true,
      expiresAt: json['expires_at']?.toString() ?? '',
    );
  }
}

class FamilyCreatedInvite {
  const FamilyCreatedInvite({
    required this.code,
    required this.expiresAt,
    required this.ttlMinutes,
  });

  final String code;
  final String expiresAt;
  final int ttlMinutes;

  factory FamilyCreatedInvite.fromJson(Map<String, dynamic> json) {
    return FamilyCreatedInvite(
      code: json['code']?.toString() ?? '',
      expiresAt: json['expires_at']?.toString() ?? '',
      ttlMinutes: (json['ttl_minutes'] as num?)?.toInt() ?? 15,
    );
  }
}

class FamilyDeletionRequestItem {
  const FamilyDeletionRequestItem({
    required this.id,
    required this.childName,
    required this.createdAt,
  });

  final int id;
  final String childName;
  final String createdAt;

  factory FamilyDeletionRequestItem.fromJson(Map<String, dynamic> json) {
    return FamilyDeletionRequestItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      childName: json['child_name']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
    );
  }
}

class FamilyAccountStatus {
  const FamilyAccountStatus({
    required this.enabled,
    required this.inFamily,
    this.selfMember,
    this.partner,
    this.activeInvite,
    this.pendingDeletionRequests = const [],
  });

  final bool enabled;
  final bool inFamily;
  final FamilyMemberInfo? selfMember;
  final FamilyMemberInfo? partner;
  final FamilyActiveInvite? activeInvite;
  final List<FamilyDeletionRequestItem> pendingDeletionRequests;

  factory FamilyAccountStatus.fromJson(Map<String, dynamic> json) {
    final selfJson = json['self_member'];
    final partnerJson = json['partner'];
    final inviteJson = json['active_invite'];
    final rawReqs = json['pending_deletion_requests'];
    final reqs = <FamilyDeletionRequestItem>[];
    if (rawReqs is List) {
      for (final item in rawReqs) {
        if (item is Map<String, dynamic>) {
          reqs.add(FamilyDeletionRequestItem.fromJson(item));
        } else if (item is Map) {
          reqs.add(
            FamilyDeletionRequestItem.fromJson(
              Map<String, dynamic>.from(item),
            ),
          );
        }
      }
    }
    return FamilyAccountStatus(
      enabled: json['enabled'] == true,
      inFamily: json['in_family'] == true,
      selfMember: selfJson is Map
          ? FamilyMemberInfo.fromJson(Map<String, dynamic>.from(selfJson))
          : null,
      partner: partnerJson is Map
          ? FamilyMemberInfo.fromJson(Map<String, dynamic>.from(partnerJson))
          : null,
      activeInvite: inviteJson is Map
          ? FamilyActiveInvite.fromJson(Map<String, dynamic>.from(inviteJson))
          : null,
      pendingDeletionRequests: reqs,
    );
  }
}
