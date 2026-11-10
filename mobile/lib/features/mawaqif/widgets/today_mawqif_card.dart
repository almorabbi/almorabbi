/// «موقف بقرار» on Today (docs/MAWAQIF.md): the next step for the active
/// child's band that the parent has not been through yet.
///
/// Hides itself while loading, on any failure, on a server without the
/// endpoint (404 → no steps), for a band without steps, and once every step
/// of the band was gone through. No number, no streak, no "missed".
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/analytics.dart';
import '../../../l10n/app_localizations.dart';
import '../../../state/chat_notifier.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/design_tokens.dart';
import '../../child_memory/data/placeholder_names.dart';
import '../../onboarding/providers/onboarding_providers.dart';
import '../data/mawqif.dart';
import '../screens/mawqif_screen.dart';

class TodayMawqifCard extends ConsumerStatefulWidget {
  const TodayMawqifCard({
    super.key,
    required this.childId,
    required this.childName,
    required this.ageGroup,
  });

  final int childId;
  final String childName;
  final String ageGroup;

  @override
  ConsumerState<TodayMawqifCard> createState() => _TodayMawqifCardState();
}

class _TodayMawqifCardState extends ConsumerState<TodayMawqifCard> {
  Mawqif? _next;
  MawaqifStore? _store;
  bool _shownLogged = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(TodayMawqifCard old) {
    super.didUpdateWidget(old);
    if (old.childId != widget.childId || old.ageGroup != widget.ageGroup) {
      _next = null;
      _shownLogged = false;
      _load();
    }
  }

  Future<void> _load() async {
    final childId = widget.childId;
    try {
      final prefs = await ref.read(sharedPreferencesProvider.future);
      final raw = await ref.read(tgClientProvider).getMawaqif(widget.ageGroup);
      if (!mounted || childId != widget.childId) return;
      final store = MawaqifStore(prefs);
      final items = [for (final j in raw) ?Mawqif.fromJson(j)];
      final next = nextMawqif(items, store.doneFor(childId));
      setState(() {
        _store = store;
        _next = next;
      });
      if (next != null && !_shownLogged) {
        _shownLogged = true;
        unawaited(Analytics.mawqifShown(widget.ageGroup));
      }
    } catch (_) {
      // Quiet: a card that cannot load is simply not shown.
    }
  }

  Future<void> _open(Mawqif m) async {
    final l10n = AppLocalizations.of(context);
    unawaited(Analytics.mawqifOpened(m.id));
    final store = _store;
    final childId = widget.childId;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MawqifScreen(
          mawqif: m,
          childId: childId,
          childName: isDefaultChildName(widget.childName)
              ? l10n.noorYourChild
              : widget.childName,
          onFinished: () {
            if (store != null) unawaited(store.markDone(childId, m.id));
          },
        ),
      ),
    );
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final m = _next;
    if (m == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dt.rCard),
          side: BorderSide(color: c.track),
        ),
        child: InkWell(
          key: const ValueKey('today-mawqif'),
          borderRadius: BorderRadius.circular(Dt.rCard),
          onTap: () => _open(m),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Icon(Icons.alt_route_rounded, color: c.accentDeep, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.mawqifCardLabel,
                        style: TextStyle(
                          color: c.accentDeep,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        m.title,
                        style: TextStyle(
                          color: c.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  l10n.mawqifCardStart,
                  style: TextStyle(
                    color: c.primary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
