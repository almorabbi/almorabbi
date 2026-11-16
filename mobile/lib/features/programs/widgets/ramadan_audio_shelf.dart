/// Bilingual shelf for Pre-Iftar Screen-Off Kids Tales (5) and Short Parenting
/// Capsules (10) in «رمضان العائلة».
///
/// - Tales open offline narrative modals OR launch [AppRoutes.screenOffPlayer]
///   streaming from `/docs/ramadan_audio/...` (zero screen budget spent!).
/// - Capsules show 3 crisp takeaways offline + optional calm `just_audio` stream
///   that degrades gracefully when offline.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:just_audio/just_audio.dart';

import '../../../config/app_config.dart';
import '../../../core/analytics.dart';
import '../../../core/app_routes.dart';
import '../../../core/haptics.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/design_tokens.dart';
import 'program_widgets.dart';

class RamadanTaleItem {
  const RamadanTaleItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.durationLabel,
    required this.audioPath,
    required this.moral,
    required this.paragraphs,
  });

  final String id;
  final String title;
  final String subtitle;
  final String durationLabel;
  final String audioPath;
  final String moral;
  final List<String> paragraphs;

  factory RamadanTaleItem.fromJson(Map<String, dynamic> j) => RamadanTaleItem(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        subtitle: j['subtitle'] as String? ?? '',
        durationLabel: j['duration_label'] as String? ?? '',
        audioPath: j['audio_path'] as String? ?? '',
        moral: j['moral'] as String? ?? '',
        paragraphs: [
          for (final p in (j['story_paragraphs'] as List? ?? const [])) '$p',
        ],
      );
}

class RamadanCapsuleItem {
  const RamadanCapsuleItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.durationLabel,
    required this.audioPath,
    required this.takeaways,
  });

  final String id;
  final String title;
  final String subtitle;
  final String durationLabel;
  final String audioPath;
  final List<String> takeaways;

  factory RamadanCapsuleItem.fromJson(Map<String, dynamic> j) =>
      RamadanCapsuleItem(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        subtitle: j['subtitle'] as String? ?? '',
        durationLabel: j['duration_label'] as String? ?? '',
        audioPath: j['audio_path'] as String? ?? '',
        takeaways: [
          for (final t in (j['takeaways'] as List? ?? const [])) '$t',
        ],
      );
}

class RamadanAudioPack {
  const RamadanAudioPack({required this.tales, required this.capsules});

  final List<RamadanTaleItem> tales;
  final List<RamadanCapsuleItem> capsules;

  static final Map<String, RamadanAudioPack> _cache = {};

  static Future<RamadanAudioPack> load(String languageCode) async {
    final lang = languageCode.startsWith('en') ? 'en' : 'ar';
    final cached = _cache[lang];
    if (cached != null) return cached;
    final raw = await rootBundle.loadString(
      'assets/content/programs/ramadan_audio.$lang.json',
    );
    final doc = jsonDecode(raw) as Map<String, dynamic>;
    final pack = RamadanAudioPack(
      tales: [
        for (final t in (doc['tales'] as List? ?? const []))
          if (t is Map) RamadanTaleItem.fromJson(Map<String, dynamic>.from(t)),
      ],
      capsules: [
        for (final c in (doc['capsules'] as List? ?? const []))
          if (c is Map)
            RamadanCapsuleItem.fromJson(Map<String, dynamic>.from(c)),
      ],
    );
    _cache[lang] = pack;
    return pack;
  }
}

class RamadanAudioShelf extends StatefulWidget {
  const RamadanAudioShelf({super.key});

  @override
  State<RamadanAudioShelf> createState() => _RamadanAudioShelfState();
}

class _RamadanAudioShelfState extends State<RamadanAudioShelf> {
  RamadanAudioPack? _pack;
  String? _loadedLang;
  int _tab = 0; // 0 = tales, 1 = capsules
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _playerSub;
  String? _playingId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final lang = Localizations.localeOf(context).languageCode;
    if (_loadedLang != lang) {
      _loadedLang = lang;
      unawaited(_loadPack(lang));
    }
  }

  @override
  void dispose() {
    unawaited(_playerSub?.cancel());
    unawaited(_player?.dispose());
    super.dispose();
  }

  Future<void> _loadPack(String lang) async {
    try {
      final pack = await RamadanAudioPack.load(lang);
      if (mounted) setState(() => _pack = pack);
    } catch (_) {
      // Missing optional pack hides cleanly rather than showing an error.
    }
  }

  String _fullUrl(String relPath) {
    final cleanBase = AppConfig.apiBaseUrl.endsWith('/')
        ? AppConfig.apiBaseUrl.substring(0, AppConfig.apiBaseUrl.length - 1)
        : AppConfig.apiBaseUrl;
    final cleanPath = relPath.startsWith('/') ? relPath.substring(1) : relPath;
    return '$cleanBase/$cleanPath';
  }

  Future<void> _toggleCapsuleAudio(
    RamadanCapsuleItem cap,
    AppLocalizations l10n,
  ) async {
    if (_playingId == cap.id) {
      try {
        await _player?.stop();
      } catch (_) {}
      if (mounted) setState(() => _playingId = null);
      return;
    }
    try {
      final player = _player ??= AudioPlayer();
      _playerSub ??= player.playerStateStream.listen((st) {
        if (st.processingState == ProcessingState.completed && mounted) {
          setState(() => _playingId = null);
        }
      });
      await player.setUrl(_fullUrl(cap.audioPath));
      if (!mounted) return;
      setState(() => _playingId = cap.id);
      unawaited(Analytics.programAction('ramadan', 'audio_capsule_${cap.id}'));
      await player.play();
    } catch (_) {
      if (!mounted) return;
      setState(() => _playingId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.ramadanFawazirAudioOffline)),
      );
    }
  }

  void _openStoryModal(RamadanTaleItem tale, AppLocalizations l10n) {
    Haptics.selection();
    unawaited(Analytics.programAction('ramadan', 'read_tale_${tale.id}'));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (_, ctrl) => ListView(
            controller: ctrl,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            children: [
              ContentText(
                tale.title,
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: ctx.colors.ink,
                ),
              ),
              const SizedBox(height: 12),
              for (final para in tale.paragraphs) ...[
                ContentText(para),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ctx.colors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.ramadanAudioMoralLabel,
                      style: TextStyle(
                        color: ctx.colors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ContentText(
                      tale.moral,
                      style: TextStyle(
                        color: ctx.colors.ink,
                        fontWeight: FontWeight.w700,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pack = _pack;
    if (pack == null || (pack.tales.isEmpty && pack.capsules.isEmpty)) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final c = context.colors;

    return ProgramSection(
      key: const ValueKey('ramadan_audio_shelf'),
      title: l10n.ramadanAudioTitle,
      emoji: '🎙️',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                key: const ValueKey('ramadan_audio_tab_tales'),
                label: Text(l10n.ramadanAudioTalesTab),
                selected: _tab == 0,
                onSelected: (_) => setState(() => _tab = 0),
              ),
              ChoiceChip(
                key: const ValueKey('ramadan_audio_tab_capsules'),
                label: Text(
                  l10n.ramadanAudioCapsulesTab(pack.capsules.length),
                ),
                selected: _tab == 1,
                onSelected: (_) => setState(() => _tab = 1),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_tab == 0)
            for (final tale in pack.tales)
              Container(
                key: ValueKey('ramadan_tale_${tale.id}'),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: BorderRadius.circular(Dt.rCard - 6),
                  border: Border.all(color: c.track),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ContentText(
                            tale.title,
                            style: TextStyle(
                              color: c.ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        CountBadge(tale.durationLabel),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ContentText(
                      tale.subtitle,
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          key: ValueKey('ramadan_tale_screen_off_${tale.id}'),
                          icon: const Icon(Icons.dark_mode_outlined, size: 18),
                          label: Text(l10n.ramadanAudioScreenOffBtn),
                          onPressed: () {
                            unawaited(
                              Analytics.programAction(
                                'ramadan',
                                'screen_off_${tale.id}',
                              ),
                            );
                            Navigator.of(context).push(
                              AppRoutes.screenOffPlayer(
                                title: tale.title,
                                source: _fullUrl(tale.audioPath),
                              ),
                            );
                          },
                        ),
                        OutlinedButton.icon(
                          key: ValueKey('ramadan_tale_read_${tale.id}'),
                          icon: const Icon(Icons.menu_book_outlined, size: 18),
                          label: Text(l10n.ramadanAudioReadStoryBtn),
                          onPressed: () => _openStoryModal(tale, l10n),
                        ),
                      ],
                    ),
                  ],
                ),
              )
          else
            for (final cap in pack.capsules)
              Container(
                key: ValueKey('ramadan_capsule_${cap.id}'),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: BorderRadius.circular(Dt.rCard - 6),
                  border: Border.all(
                    color: _playingId == cap.id ? c.primary : c.track,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ContentText(
                            cap.title,
                            style: TextStyle(
                              color: c.ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        CountBadge(cap.durationLabel),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ContentText(
                      cap.subtitle,
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ProgramBullets(cap.takeaways),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: OutlinedButton.icon(
                        key: ValueKey('ramadan_capsule_play_${cap.id}'),
                        icon: Icon(
                          _playingId == cap.id
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 18,
                        ),
                        label: Text(
                          _playingId == cap.id
                              ? l10n.ramadanFawazirPauseBtn
                              : l10n.ramadanAudioListenCapsuleBtn,
                        ),
                        onPressed: () => _toggleCapsuleAudio(cap, l10n),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
