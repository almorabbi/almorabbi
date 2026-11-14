/// «حساب الأسرة» — dual-parent pairing, sync status & mutual deletion (2.0 M3).
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/failures.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/ui/brand_glyph.dart';
import '../../program/providers/settings_providers.dart';
import '../data/family_account_models.dart';
import '../providers/family_account_providers.dart';

class FamilyAccountScreen extends ConsumerStatefulWidget {
  const FamilyAccountScreen({super.key});

  @override
  ConsumerState<FamilyAccountScreen> createState() =>
      _FamilyAccountScreenState();
}

class _FamilyAccountScreenState extends ConsumerState<FamilyAccountScreen> {
  final _displayNameCtrl = TextEditingController();
  final _joinCodeCtrl = TextEditingController();
  final _deleteChildCtrl = TextEditingController();

  String _role = 'parent';
  bool _busy = false;
  FamilyCreatedInvite? _createdInvite;

  @override
  void dispose() {
    _displayNameCtrl.dispose();
    _joinCodeCtrl.dispose();
    _deleteChildCtrl.dispose();
    super.dispose();
  }

  String _errorMessage(Object error, AppLocalizations l10n) =>
      describeFailure(l10n, error);

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String _roleLabel(String role, AppLocalizations l10n) => switch (role) {
        'mother' => l10n.familyAccountRoleMother,
        'father' => l10n.familyAccountRoleFather,
        _ => l10n.familyAccountRoleParent,
      };

  Future<void> _createInvite() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final invite = await ref
          .read(familyAccountServiceProvider)
          .createInvite(role: _role, displayName: _displayNameCtrl.text);
      if (!mounted) return;
      setState(() => _createdInvite = invite);
      ref.invalidate(familyAccountStatusProvider);
    } catch (e) {
      _showSnack(_errorMessage(e, l10n));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _joinFamily() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final normalized = _joinCodeCtrl.text
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (normalized.length != 8) {
      _showSnack(l10n.familyAccountInvalidCode);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(familyAccountServiceProvider).join(
            code: normalized,
            role: _role,
            displayName: _displayNameCtrl.text,
          );
      if (!mounted) return;
      _joinCodeCtrl.clear();
      setState(() => _createdInvite = null);
      ref.invalidate(familyAccountStatusProvider);
      ref.invalidate(childrenListProvider);
    } catch (e) {
      _showSnack(_errorMessage(e, l10n));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reconfirm() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(familyAccountServiceProvider).reconfirm();
      if (!mounted) return;
      ref.invalidate(familyAccountStatusProvider);
      ref.invalidate(childrenListProvider);
    } catch (e) {
      _showSnack(_errorMessage(e, l10n));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestChildDeletion() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final name = _deleteChildCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(familyAccountServiceProvider).requestChildDeletion(name);
      if (!mounted) return;
      _deleteChildCtrl.clear();
      _showSnack(l10n.familyAccountRequestDeletionSent);
      ref.invalidate(familyAccountStatusProvider);
    } catch (e) {
      _showSnack(_errorMessage(e, l10n));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _respondToDeletion(int requestId, {required bool confirm}) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final svc = ref.read(familyAccountServiceProvider);
      if (confirm) {
        await svc.confirmChildDeletion(requestId);
        ref.invalidate(childrenListProvider);
      } else {
        await svc.dismissChildDeletion(requestId);
      }
      if (!mounted) return;
      ref.invalidate(familyAccountStatusProvider);
    } catch (e) {
      _showSnack(_errorMessage(e, l10n));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmLeave() async {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.familyAccountLeaveConfirmTitle),
        content: Text(l10n.familyAccountLeaveConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: c.dangerFg),
            child: Text(l10n.familyAccountLeaveConfirmCta),
          ),
        ],
      ),
    );
    if (confirmed != true || _busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(familyAccountServiceProvider).leave();
      if (!mounted) return;
      setState(() => _createdInvite = null);
      ref.invalidate(familyAccountStatusProvider);
      _showSnack(l10n.familyAccountLeftSuccess);
    } catch (e) {
      _showSnack(_errorMessage(e, l10n));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final asyncStatus = ref.watch(familyAccountStatusProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.familyAccountTitle)),
      body: SafeArea(
        child: asyncStatus.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off_outlined, size: 42, color: c.inkSoft),
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage(err, l10n),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.ink, fontSize: 15),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () =>
                        ref.invalidate(familyAccountStatusProvider),
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.retry),
                  ),
                ],
              ),
            ),
          ),
          data: (status) {
            if (!status.enabled) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: c.warningBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.track),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline, size: 32, color: c.warningFg),
                        const SizedBox(height: 12),
                        Text(
                          l10n.familyAccountLocked,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.warningFg, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            if (!status.inFamily) {
              return _buildUnpairedBody(context, l10n);
            }
            return _buildPairedBody(context, l10n, status);
          },
        ),
      ),
    );
  }

  Widget _buildUnpairedBody(BuildContext context, AppLocalizations l10n) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.track),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrandGlyph(BrandIcon.envelope, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.familyAccountUnpairedIntro,
                  style: TextStyle(color: c.ink, fontSize: 14, height: 1.45),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildRoleAndNameSection(context, l10n),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('family_create_invite_btn'),
          onPressed: _busy ? null : _createInvite,
          icon: const Icon(Icons.qr_code_2),
          label: Text(l10n.familyAccountCreateInviteCta),
          style: FilledButton.styleFrom(
            backgroundColor: c.primary,
            foregroundColor: c.onPrimary,
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        if (_createdInvite != null) ...[
          const SizedBox(height: 16),
          _InviteCodeCard(
            invite: _createdInvite!,
            l10n: l10n,
            onCopy: () async {
              await Clipboard.setData(
                ClipboardData(text: _createdInvite!.code),
              );
              _showSnack(l10n.familyAccountCopied);
            },
          ),
        ],
        const SizedBox(height: 24),
        Text(
          l10n.familyAccountJoinSectionTitle,
          style: TextStyle(
            color: c.ink,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('family_join_code_input'),
          controller: _joinCodeCtrl,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(
            hintText: l10n.familyAccountJoinCodeHint,
            filled: true,
            fillColor: c.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: c.track),
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('family_join_btn'),
          onPressed: _busy ? null : _joinFamily,
          icon: const Icon(Icons.group_add_outlined),
          label: Text(l10n.familyAccountJoinCta),
          style: OutlinedButton.styleFrom(
            foregroundColor: c.primary,
            side: BorderSide(color: c.primary),
            minimumSize: const Size.fromHeight(48),
          ),
        ),
        ],
      ),
    );
  }

  Widget _buildRoleAndNameSection(
    BuildContext context,
    AppLocalizations l10n,
  ) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.track),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.familyAccountRoleLabel,
            style: TextStyle(
              color: c.ink,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final r in const ['mother', 'father', 'parent'])
                ChoiceChip(
                  label: Text(_roleLabel(r, l10n)),
                  selected: _role == r,
                  onSelected: _busy
                      ? null
                      : (_) => setState(() => _role = r),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _displayNameCtrl,
            maxLength: 40,
            decoration: InputDecoration(
              labelText: l10n.familyAccountDisplayNameLabel,
              hintText: l10n.familyAccountDisplayNameHint,
              filled: true,
              fillColor: c.surfaceAlt,
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: c.track),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPairedBody(
    BuildContext context,
    AppLocalizations l10n,
    FamilyAccountStatus status,
  ) {
    final c = context.colors;
    final selfMember = status.selfMember;
    final partner = status.partner;
    final needsReconfirm = selfMember != null && !selfMember.confirmed;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        if (needsReconfirm) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.warningBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.warningFg.withValues(alpha: 0.45)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: c.warningFg),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.familyAccountUnconfirmedBanner,
                        style: TextStyle(color: c.warningFg, fontSize: 13.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                FilledButton(
                  key: const Key('family_reconfirm_btn'),
                  onPressed: _busy ? null : _reconfirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: c.warningFg,
                    foregroundColor: c.surface,
                  ),
                  child: Text(l10n.familyAccountReconfirmCta),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (status.pendingDeletionRequests.isNotEmpty) ...[
          Text(
            l10n.familyAccountDeletionRequestsTitle,
            style: TextStyle(
              color: c.ink,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          for (final req in status.pendingDeletionRequests) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.dangerBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.dangerFg.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.familyAccountDeletionRequestPrompt(req.childName),
                    style: TextStyle(
                      color: c.dangerFg,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        key: Key('family_confirm_del_${req.id}'),
                        onPressed: _busy
                            ? null
                            : () => _respondToDeletion(req.id, confirm: true),
                        style: FilledButton.styleFrom(
                          backgroundColor: c.dangerFg,
                          foregroundColor: c.surface,
                        ),
                        child: Text(l10n.familyAccountConfirmDeletionCta),
                      ),
                      OutlinedButton(
                        key: Key('family_dismiss_del_${req.id}'),
                        onPressed: _busy
                            ? null
                            : () => _respondToDeletion(req.id, confirm: false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: c.ink,
                          side: BorderSide(color: c.track),
                        ),
                        child: Text(l10n.familyAccountDismissDeletionCta),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
        ],
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.track),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const BrandGlyph(BrandIcon.door, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      partner != null
                          ? l10n.familyAccountPairedHeader
                          : l10n.familyAccountWaitingPartnerTitle,
                      style: TextStyle(
                        color: c.ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (selfMember != null)
                _MemberTile(
                  badge: l10n.familyAccountSelfLabel,
                  member: selfMember,
                  roleText: _roleLabel(selfMember.role, l10n),
                  l10n: l10n,
                ),
              if (partner != null) ...[
                const SizedBox(height: 8),
                _MemberTile(
                  badge: l10n.familyAccountPartnerLabel,
                  member: partner,
                  roleText: _roleLabel(partner.role, l10n),
                  l10n: l10n,
                ),
              ] else ...[
                const SizedBox(height: 12),
                Text(
                  l10n.familyAccountWaitingPartnerBody,
                  style: TextStyle(color: c.inkSoft, fontSize: 13.5),
                ),
                if (status.activeInvite?.hasActive == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.familyAccountActiveInviteNote,
                    style: TextStyle(color: c.textSecondary, fontSize: 12.5),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('family_create_invite_btn'),
                  onPressed: _busy ? null : _createInvite,
                  icon: const Icon(Icons.qr_code_2),
                  label: Text(l10n.familyAccountCreateInviteCta),
                  style: FilledButton.styleFrom(
                    backgroundColor: c.primary,
                    foregroundColor: c.onPrimary,
                  ),
                ),
                if (_createdInvite != null) ...[
                  const SizedBox(height: 12),
                  _InviteCodeCard(
                    invite: _createdInvite!,
                    l10n: l10n,
                    onCopy: () async {
                      await Clipboard.setData(
                        ClipboardData(text: _createdInvite!.code),
                      );
                      _showSnack(l10n.familyAccountCopied);
                    },
                  ),
                ],
              ],
            ],
          ),
        ),
        if (partner != null && !needsReconfirm) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.track),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.familyAccountRequestDeletionTitle,
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.familyAccountRequestDeletionDesc,
                  style: TextStyle(color: c.inkSoft, fontSize: 13),
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('family_request_del_input'),
                  controller: _deleteChildCtrl,
                  decoration: InputDecoration(
                    hintText: l10n.familyAccountRequestDeletionHint,
                    filled: true,
                    fillColor: c.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: c.track),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  key: const Key('family_request_del_btn'),
                  onPressed: _busy ? null : _requestChildDeletion,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.primary,
                    side: BorderSide(color: c.primary),
                  ),
                  child: Text(l10n.familyAccountRequestDeletionCta),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        TextButton.icon(
          key: const Key('family_leave_btn'),
          onPressed: _busy ? null : _confirmLeave,
          icon: Icon(Icons.logout, color: c.dangerFg),
          label: Text(
            l10n.familyAccountLeaveCta,
            style: TextStyle(color: c.dangerFg, fontWeight: FontWeight.w600),
          ),
        ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.badge,
    required this.member,
    required this.roleText,
    required this.l10n,
  });

  final String badge;
  final FamilyMemberInfo member;
  final String roleText;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = (member.displayName?.trim().isNotEmpty == true)
        ? '${member.displayName!.trim()} · $roleText'
        : roleText;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            member.confirmed
                ? Icons.verified_outlined
                : Icons.warning_amber_rounded,
            size: 20,
            color: member.confirmed ? c.successText : c.warningFg,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  badge,
                  style: TextStyle(color: c.textSecondary, fontSize: 12),
                ),
                Text(
                  name,
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Text(
            member.confirmed
                ? l10n.familyAccountConfirmedBadge
                : l10n.familyAccountUnconfirmedBadge,
            style: TextStyle(
              color: member.confirmed ? c.successText : c.warningFg,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteCodeCard extends StatelessWidget {
  const _InviteCodeCard({
    required this.invite,
    required this.l10n,
    required this.onCopy,
  });

  final FamilyCreatedInvite invite;
  final AppLocalizations l10n;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.primary.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.familyAccountInviteTitle,
            style: TextStyle(color: c.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 6),
          SelectableText(
            invite.code,
            style: TextStyle(
              color: c.ink,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.familyAccountInviteTtlNote,
            style: TextStyle(color: c.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onCopy,
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: Text(l10n.familyAccountCopyCode),
          ),
        ],
      ),
    );
  }
}
