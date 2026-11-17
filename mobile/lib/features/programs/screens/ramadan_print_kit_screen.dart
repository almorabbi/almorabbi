/// Personalized on-device Printable Ramadan Kit («عدّة رمضان الورقية لأسرتك»).
///
/// Privacy invariant: children's names & age bands are read strictly locally
/// from [childrenListProvider] / [activeChildProfileProvider] and rendered only
/// on the parent's phone (or exported locally as images for home printing).
/// Never sent to `/print/*` network URLs.
///
/// Export invariant: [RamadanPrintableSheet] uses a deterministic, flex-free
/// pixel layout (`1080×1528` per A4 sheet) with zero `Material`, `GridView`,
/// `Scrollable`, `Expanded`, `Flexible`, `MediaQuery`, or `Theme` ancestors so
/// `ScreenshotController().captureFromWidget(...)` renders cleanly off-tree
/// without triggering Flutter's release `ErrorWidget`.
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/app_config.dart';
import '../../../core/haptics.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_palette.dart';
import '../../../widgets/ui/bouncy_button.dart';
import '../../onboarding/providers/onboarding_providers.dart';
import '../../program/providers/settings_providers.dart';

/// Child metadata resolved locally on-device for printable family craft sheets.
class LocalPrintChild {
  const LocalPrintChild({required this.name, required this.ageGroup});

  final String name;
  final String ageGroup;
}

/// The three printable A4 sheets included in the personalized Ramadan kit.
enum RamadanKitSheetKind {
  fanousPattern,
  lanternStreet,
  tableCardsAndJar,
}

/// Returns a gentle, age-appropriate Ramadan table/home role label for a child.
String roleForRamadanBand(String band, bool isAr, int index) {
  final arRoles = [
    'أمين التمر والماء برفق',
    'منظّم السفرة و«بسم الله»',
    'حامل الدعاء قبل الأذان',
    'سفير صندوق الصدقة والعطاء',
  ];
  final enRoles = [
    'Dates & Water Steward',
    'Table & Bismillah Guide',
    'Dua Host Before Sunset',
    'Charity & Kindness Lead',
  ];
  final list = isAr ? arRoles : enRoles;
  return switch (band) {
    '0-3' || '2-3' || '4-6' => list[0],
    '7-9' => list[index % 2 == 0 ? 1 : 2],
    '10-12' => list[2],
    _ => list[3],
  };
}

String _roleDescriptionForBand(String band, bool isAr, int index) {
  final arDescs = [
    'أحضرُ التمر وأكواب الماء للأسرة بأدب.',
    'أرتّب الأطباق وأذكّر بقول «بسم الله».',
    'أجمع دعاء الأسرة الهادئ قبل الأذان.',
    'أتابع صندوق الصدقة وأبتسم لإخوتي.',
  ];
  final enDescs = [
    'Passes dates & cups of water gently.',
    'Sets plates neatly & reminds Bismillah.',
    'Invites calm family dua before Maghrib.',
    'Tends our charity box with a warm smile.',
  ];
  final list = isAr ? arDescs : enDescs;
  return switch (band) {
    '0-3' || '2-3' || '4-6' => list[0],
    '7-9' => list[index % 2 == 0 ? 1 : 2],
    '10-12' => list[2],
    _ => list[3],
  };
}

String _localizeDigits(int value, bool isAr) {
  final raw = value.toString();
  if (!isAr) return raw;
  const western = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
  const eastern = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
  var out = raw;
  for (var i = 0; i < western.length; i++) {
    out = out.replaceAll(western[i], eastern[i]);
  }
  return out;
}

/// Builds the 3 self-contained `1080×1528` A4 sheets for the Ramadan kit.
List<RamadanPrintableSheet> buildRamadanKitSheets({
  required bool isAr,
  required bool bwInk,
  required List<LocalPrintChild> kids,
  required String kitHeadline,
  required String namesBanner,
  required String footerTitle,
  String? qrUrl,
  String? qrCodeLabel,
}) {
  final resolvedLabel = qrCodeLabel ?? (isAr ? 'PR03' : 'PR04');
  final resolvedUrl =
      qrUrl ?? 'https://tg-api.alsaba.cloud/go?ref=$resolvedLabel';
  return [
    for (final kind in RamadanKitSheetKind.values)
      RamadanPrintableSheet(
        kind: kind,
        isAr: isAr,
        bwInk: bwInk,
        kids: kids,
        kitHeadline: kitHeadline,
        namesBanner: namesBanner,
        footerTitle: footerTitle,
        qrUrl: resolvedUrl,
        qrCodeLabel: resolvedLabel,
      ),
  ];
}

class RamadanPrintKitScreen extends ConsumerStatefulWidget {
  const RamadanPrintKitScreen({super.key});

  @override
  ConsumerState<RamadanPrintKitScreen> createState() =>
      _RamadanPrintKitScreenState();
}

class _RamadanPrintKitScreenState extends ConsumerState<RamadanPrintKitScreen> {
  bool _bwInk = false;
  bool _exporting = false;
  int _selectedSheetIndex = 1;

  List<LocalPrintChild> _localChildren() {
    final list = ref.watch(childrenListProvider).valueOrNull?.children;
    if (list != null && list.isNotEmpty) {
      return [
        for (final c in list)
          if (c.name.trim().isNotEmpty)
            LocalPrintChild(name: c.name.trim(), ageGroup: c.ageGroup),
      ];
    }
    if (ref.watch(sharedPreferencesProvider).hasValue) {
      final active = ref.watch(activeChildProfileProvider);
      if (active != null && active.name.trim().isNotEmpty) {
        return [
          LocalPrintChild(
            name: active.name.trim(),
            ageGroup: active.ageGroup,
          ),
        ];
      }
    }
    return const [];
  }

  Future<void> _exportPersonalizedSheet(
    List<LocalPrintChild> kids,
    AppLocalizations l10n,
  ) async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final lang = Localizations.localeOf(context).languageCode == 'en'
          ? 'en'
          : 'ar';
      final isAr = lang == 'ar';
      final namesText = kids.isEmpty
          ? l10n.ramadanPrintKitDefaultNames
          : kids.map((k) => k.name).join(isAr ? '، ' : ', ');
      final sheets = buildRamadanKitSheets(
        isAr: isAr,
        bwInk: _bwInk,
        kids: kids,
        kitHeadline: l10n.ramadanPrintKitTitle,
        namesBanner: l10n.ramadanPrintKitForChildren(namesText),
        footerTitle: l10n.ramadanPrintKitBannerHint,
      );

      final controller = ScreenshotController();
      final dir = await Directory.systemTemp.createTemp('tg_print_kit_');
      const slugs = ['1_fanous', '2_street', '3_cards'];
      final files = <XFile>[];
      for (var i = 0; i < sheets.length; i++) {
        final bytes = await controller.captureFromWidget(
          sheets[i],
          pixelRatio: 1.5,
          targetSize: RamadanPrintableSheet.a4Size,
          delay: const Duration(milliseconds: 100),
        );
        final file = File('${dir.path}/ramadan_kit_${slugs[i]}_$lang.png');
        await file.writeAsBytes(bytes, flush: true);
        files.add(XFile(file.path, mimeType: 'image/png'));
      }

      await SharePlus.instance.share(
        ShareParams(
          files: files,
          text: l10n.ramadanPrintKitTitle,
        ),
      );
    } on MissingPluginException {
      // Calm silent fallback in headless test environments without share plugin.
    } on PlatformException catch (e) {
      debugPrint('Ramadan print kit share platform error: $e');
    } catch (e, st) {
      debugPrint('Ramadan print kit export error: $e\n$st');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _openBrowserKit(Uri uri) async {
    Haptics.selection();
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.colors;
    final lang = Localizations.localeOf(context).languageCode == 'en'
        ? 'en'
        : 'ar';
    final isAr = lang == 'ar';
    final kids = _localChildren();
    final namesText = kids.isEmpty
        ? l10n.ramadanPrintKitDefaultNames
        : kids.map((k) => k.name).join(isAr ? '، ' : ', ');
    final sheets = buildRamadanKitSheets(
      isAr: isAr,
      bwInk: _bwInk,
      kids: kids,
      kitHeadline: l10n.ramadanPrintKitTitle,
      namesBanner: l10n.ramadanPrintKitForChildren(namesText),
      footerTitle: l10n.ramadanPrintKitBannerHint,
    );
    final sheetTabLabels = isAr
        ? const ['١. باترون الفانوس', '٢. خريطة القناديل', '٣. بطاقات السفرة']
        : const ['1. 3D Fanous', '2. 30 Lanterns', '3. Table Cards'];

    final craftUri = Uri.parse(
      '${AppConfig.apiBaseUrl}/print/lantern-craft?lang=$lang&ink=${_bwInk ? "bw" : "color"}',
    );
    final fullPackUri = Uri.parse(
      '${AppConfig.apiBaseUrl}/print/ramadan?lang=$lang',
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.ramadanPrintKitTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            l10n.ramadanPrintKitSubtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: c.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  key: const ValueKey('print_kit_ink_color'),
                  label: Text(l10n.ramadanPrintKitInkColor),
                  selected: !_bwInk,
                  onSelected: (_) {
                    Haptics.selection();
                    setState(() => _bwInk = false);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  key: const ValueKey('print_kit_ink_bw'),
                  label: Text(l10n.ramadanPrintKitInkBw),
                  selected: _bwInk,
                  onSelected: (_) {
                    Haptics.selection();
                    setState(() => _bwInk = true);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < sheetTabLabels.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: ChoiceChip(
                    key: ValueKey('print_kit_sheet_$i'),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(sheetTabLabels[i]),
                    ),
                    selected: _selectedSheetIndex == i,
                    onSelected: (_) {
                      Haptics.selection();
                      setState(() => _selectedSheetIndex = i);
                    },
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Container(
            key: const ValueKey('print_kit_poster_preview'),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: c.ink.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AspectRatio(
                aspectRatio:
                    RamadanPrintableSheet.a4Size.width /
                    RamadanPrintableSheet.a4Size.height,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: sheets[_selectedSheetIndex],
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.primary.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 18, color: c.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.ramadanPrintKitPrivacyNote,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: c.ink,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          BouncyButton(
            key: const ValueKey('print_kit_share_cta'),
            label: l10n.ramadanPrintKitShareCta,
            onTap: _exporting
                ? null
                : () => _exportPersonalizedSheet(kids, l10n),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: const ValueKey('print_kit_open_craft'),
            icon: const Icon(Icons.cut_rounded),
            label: Text(l10n.ramadanPrintKitOpenCraft),
            onPressed: () => _openBrowserKit(craftUri),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('print_kit_open_full'),
            icon: const Icon(Icons.menu_book_outlined),
            label: Text(l10n.ramadanPrintKitOpenFullPack),
            onPressed: () => _openBrowserKit(fullPackUri),
          ),
        ],
      ),
    );
  }
}

/// Self-contained 1080×1528 A4 printable sheet safe for off-tree image capture.
///
/// Must never depend on [Material], [Scaffold], [Scrollable], [GridView],
/// [Expanded], [Flexible], [MediaQuery], [Theme], or [AppLocalizations].
class RamadanPrintableSheet extends StatelessWidget {
  const RamadanPrintableSheet({
    super.key,
    required this.kind,
    required this.isAr,
    required this.bwInk,
    required this.kids,
    required this.kitHeadline,
    required this.namesBanner,
    required this.footerTitle,
    required this.qrUrl,
    required this.qrCodeLabel,
  });

  static const Size a4Size = Size(1080, 1528);

  final RamadanKitSheetKind kind;
  final bool isAr;
  final bool bwInk;
  final List<LocalPrintChild> kids;
  final String kitHeadline;
  final String namesBanner;
  final String footerTitle;
  final String qrUrl;
  final String qrCodeLabel;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.light;
    final ink = palette.ink;
    final border = bwInk ? ink : palette.paperEmerald;
    final sheetFill = bwInk ? Colors.white : palette.paperIvory; // audit-ok: physical A4 paper sheet for home printing
    final pillFill = bwInk
        ? Colors.white // audit-ok: physical A4 paper sheet for home printing
        : palette.paperEmerald.withValues(alpha: 0.12);

    final sheetNumber = switch (kind) {
      RamadanKitSheetKind.fanousPattern => 1,
      RamadanKitSheetKind.lanternStreet => 2,
      RamadanKitSheetKind.tableCardsAndJar => 3,
    };
    final eyebrow = isAr
        ? '$kitHeadline · ورقة ${_localizeDigits(sheetNumber, true)} من ٣'
        : '$kitHeadline · Sheet $sheetNumber of 3';
    final sheetTitle = switch ((kind, isAr)) {
      (RamadanKitSheetKind.fanousPattern, true) =>
        'باترون الفانوس الورقي ثلاثي الأبعاد',
      (RamadanKitSheetKind.fanousPattern, false) =>
        '3D Paper-Cut Fanous Lantern Pattern',
      (RamadanKitSheetKind.lanternStreet, true) =>
        'خريطة شارع القناديل الـ ٣٠',
      (RamadanKitSheetKind.lanternStreet, false) =>
        '30-Lantern Ramadan Street Map',
      (RamadanKitSheetKind.tableCardsAndJar, true) =>
        'بطاقات سفير الإفطار وجرّة الكلمات الطيبة',
      (RamadanKitSheetKind.tableCardsAndJar, false) =>
        'Iftar Ambassador Cards & Kind-Words Jar',
    };

    return SizedBox(
      width: a4Size.width,
      height: a4Size.height,
      child: RepaintBoundary(
        child: Directionality(
          textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
          child: DefaultTextStyle(
            style: GoogleFonts.cairo(
              color: ink,
              decoration: TextDecoration.none,
              fontWeight: FontWeight.w600,
            ),
            child: Container(
              width: a4Size.width,
              height: a4Size.height,
              padding: const EdgeInsets.all(36),
              color: Colors.white, // audit-ok: physical A4 paper sheet for home printing
              child: Container(
                width: 1008,
                height: 1456,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 24,
                ),
                decoration: BoxDecoration(
                  color: sheetFill,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: border, width: 3.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    SizedBox(
                      width: 945,
                      height: 180,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            eyebrow,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.cairo(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              height: 1.25,
                              color: border,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            sheetTitle,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.cairo(
                              fontSize: 31,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                              color: ink,
                              decoration: TextDecoration.none,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            height: 76,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: pillFill,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: border, width: 1.5),
                            ),
                            child: Text(
                              namesBanner,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.cairo(
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                                height: 1.3,
                                color: ink,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: 945,
                      height: 1054,
                      child: switch (kind) {
                        RamadanKitSheetKind.fanousPattern => _FanousSheetBody(
                          isAr: isAr,
                          bwInk: bwInk,
                          kids: kids,
                          border: border,
                        ),
                        RamadanKitSheetKind.lanternStreet =>
                          _LanternStreetSheetBody(
                            isAr: isAr,
                            bwInk: bwInk,
                            kids: kids,
                            border: border,
                          ),
                        RamadanKitSheetKind.tableCardsAndJar =>
                          _TableCardsSheetBody(
                            isAr: isAr,
                            bwInk: bwInk,
                            kids: kids,
                            border: border,
                          ),
                      },
                    ),
                    const SizedBox(height: 16),
                    _PrintableFooter(
                      border: border,
                      bwInk: bwInk,
                      footerTitle: footerTitle,
                      qrUrl: qrUrl,
                      qrCodeLabel: qrCodeLabel,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FanousSheetBody extends StatelessWidget {
  const _FanousSheetBody({
    required this.isAr,
    required this.bwInk,
    required this.kids,
    required this.border,
  });

  final bool isAr;
  final bool bwInk;
  final List<LocalPrintChild> kids;
  final Color border;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.light;
    final ink = palette.ink;
    final kidsShort = kids.isEmpty
        ? (isAr ? 'أسرتنا' : 'Our Family')
        : kids.map((k) => k.name).take(3).join(isAr ? ' و' : ' & ');
    final handleLabel = isAr
        ? 'قصّ شريط المقبض العلوي — فانوس $kidsShort'
        : 'Cut Top Carrying Handle — Fanous for $kidsShort';

    final steps = isAr
        ? const [
            ('١', 'قصّ الخط الخارجي', 'امشِ بالمقص بهدوء على الإطار المتصل فقط بدون قصّ الألسنة الجانبية.'),
            ('٢', 'اطوِ وألصق الألسنة', 'اثنِ الخطوط المتقطّعة للداخل ثم ألصق لسان الصمغ ليقف الفانوس.'),
            ('٣', 'نور آمن بالبطارية فقط', 'يُمنع اللهب الحقيقي؛ ضَع شمعة LED صغيرة ببطارية داخل القاعدة.'),
          ]
        : const [
            ('1', 'Cut Solid Outlines', 'Trim calmly around the outer frame; leave side glue tabs intact.'),
            ('2', 'Fold & Glue Tabs', 'Crease every dashed line gently inward, then glue the side tab.'),
            ('3', 'Battery LED Light Only', 'Never use open flame; place a small flameless LED tea-light inside.'),
          ];

    final handleBg = bwInk
        ? Colors.white // audit-ok: physical A4 paper sheet for home printing
        : palette.paperGold.withValues(alpha: 0.28);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 945,
          height: 752,
          decoration: BoxDecoration(
            color: Colors.white, // audit-ok: physical A4 paper sheet for home printing
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: border.withValues(alpha: 0.45), width: 1.5),
          ),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
                child: CustomPaint(
                  size: const Size(942, 700),
                  painter: _Fanous3DNetPainter(
                    bwInk: bwInk,
                    ink: ink,
                    emerald: palette.paperEmerald,
                    gold: palette.paperGold,
                  ),
                ),
              ),
              Container(
                width: 942,
                height: 49,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: bwInk
                      ? Colors.white // audit-ok: physical A4 paper legend bar
                      : palette.paperIvory.withValues(alpha: 0.55),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(18),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(width: 28, height: 3, color: ink),
                    const SizedBox(width: 8),
                    Text(
                      isAr ? 'خط متّصل: قصّ' : 'Solid: Cut',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: ink,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(width: 28),
                    SizedBox(
                      width: 30,
                      height: 4,
                      child: Row(
                        children: [
                          Container(width: 8, height: 3, color: ink),
                          const SizedBox(width: 3),
                          Container(width: 8, height: 3, color: ink),
                          const SizedBox(width: 3),
                          Container(width: 8, height: 3, color: ink),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isAr ? 'خط متقطّع: اطوِ للداخل' : 'Dashed: Fold inward',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: ink,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(width: 28),
                    Container(
                      width: 16,
                      height: 14,
                      decoration: BoxDecoration(
                        color: bwInk
                            ? Colors.white // audit-ok: paper craft tab swatch
                            : const Color(0xFFF6EFE2),
                        border: Border.all(color: ink, width: 1.8),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isAr ? 'ألصق اللسان الجانبي' : 'Glue side tab',
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: ink,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: 945,
          height: 64,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: handleBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ink, width: 2.2),
          ),
          child: Text(
            handleLabel,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.cairo(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: ink,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 945,
          height: 206,
          child: Row(
            children: [
              for (var i = 0; i < steps.length; i++) ...[
                if (i > 0) const SizedBox(width: 18),
                Container(
                  width: 303,
                  height: 206,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white, // audit-ok: physical A4 paper sheet for home printing
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: border, width: 1.6),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: bwInk
                                  ? Colors.white // audit-ok: physical A4 paper sheet for home printing
                                  : palette.paperEmerald,
                              shape: BoxShape.circle,
                              border: Border.all(color: ink, width: 1.8),
                            ),
                            child: Text(
                              steps[i].$1,
                              style: GoogleFonts.cairo(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: bwInk ? ink : palette.onPrimary,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 220,
                            child: Text(
                              steps[i].$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.cairo(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: ink,
                                decoration: TextDecoration.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        steps[i].$3,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cairo(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                          color: ink,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Fanous3DNetPainter extends CustomPainter {
  const _Fanous3DNetPainter({
    required this.bwInk,
    required this.ink,
    required this.emerald,
    required this.gold,
  });

  final bool bwInk;
  final Color ink;
  final Color emerald;
  final Color gold;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final panelFill = bwInk ? Colors.white : const Color(0xFFE7F4F0); // audit-ok: paper craft panel fill
    final roofFill = bwInk ? Colors.white : const Color(0xFFFBF1DE); // audit-ok: paper craft roof fill
    final goldFill = bwInk ? Colors.white : gold; // audit-ok: paper craft motif fill
    final tabFill = bwInk ? Colors.white : const Color(0xFFF6EFE2); // audit-ok: paper craft glue tab fill

    final solidStroke = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeJoin = StrokeJoin.round;

    final innerAccentStroke = Paint()
      ..color = bwInk ? ink : emerald
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeJoin = StrokeJoin.round;

    const panelCount = 4;
    final glueW = w * 0.055;
    final panelW = (w - glueW - w * 0.08) / panelCount;
    final x0 = w * 0.04;

    final roofTopY = h * 0.08;
    final neckY = h * 0.24;
    final waistY = h * 0.80;
    final skirtY = h * 0.94;

    // Far-right glue tab after 4th panel.
    final rx = x0 + panelCount * panelW;
    final gluePath = Path()
      ..moveTo(rx, neckY + 14)
      ..lineTo(rx + glueW, neckY + 42)
      ..lineTo(rx + glueW, waistY - 42)
      ..lineTo(rx, waistY - 14)
      ..close();
    canvas.drawPath(gluePath, Paint()..color = tabFill);
    canvas.drawPath(gluePath, solidStroke);

    for (var i = 0; i < panelCount; i++) {
      final px = x0 + i * panelW;
      final cx = px + panelW / 2;
      final insetRoof = panelW * 0.24;

      // Top trapezoid roof hood.
      final roof = Path()
        ..moveTo(px + insetRoof, roofTopY)
        ..lineTo(px + panelW - insetRoof, roofTopY)
        ..lineTo(px + panelW, neckY)
        ..lineTo(px, neckY)
        ..close();
      canvas.drawPath(roof, Paint()..color = roofFill);
      canvas.drawPath(roof, solidStroke);

      // Crown top tiny glue tab.
      final crownTab = Path()
        ..moveTo(px + insetRoof + 10, roofTopY - 22)
        ..lineTo(px + panelW - insetRoof - 10, roofTopY - 22)
        ..lineTo(px + panelW - insetRoof, roofTopY)
        ..lineTo(px + insetRoof, roofTopY)
        ..close();
      canvas.drawPath(crownTab, Paint()..color = tabFill);
      _drawDashedPath(canvas, crownTab, ink, 2.0);

      // Main panel rectangle.
      final rect = Rect.fromLTWH(px, neckY, panelW, waistY - neckY);
      canvas.drawRect(rect, Paint()..color = panelFill);
      canvas.drawLine(Offset(px, neckY), Offset(px + panelW, neckY), solidStroke);
      canvas.drawLine(Offset(px, waistY), Offset(px + panelW, waistY), solidStroke);
      if (i == 0) {
        canvas.drawLine(Offset(px, neckY), Offset(px, waistY), solidStroke);
      } else {
        _drawDashedLine(canvas, Offset(px, neckY), Offset(px, waistY), ink, 2.4);
      }
      if (i == panelCount - 1) {
        _drawDashedLine(
          canvas,
          Offset(px + panelW, neckY),
          Offset(px + panelW, waistY),
          ink,
          2.4,
        );
      }

      // Pointed Islamic arch cutout window inside face.
      final archW = panelW * 0.64;
      final archLeft = cx - archW / 2;
      final archRight = cx + archW / 2;
      final archTop = neckY + (waistY - neckY) * 0.12;
      final archSpring = neckY + (waistY - neckY) * 0.36;
      final archBot = waistY - (waistY - neckY) * 0.12;
      final arch = Path()
        ..moveTo(archLeft, archBot)
        ..lineTo(archLeft, archSpring)
        ..quadraticBezierTo(archLeft, archTop + 18, cx, archTop)
        ..quadraticBezierTo(archRight, archTop + 18, archRight, archSpring)
        ..lineTo(archRight, archBot)
        ..close();
      canvas.drawPath(arch, Paint()..color = Colors.white); // audit-ok: physical paper cutout window
      _drawDashedPath(canvas, arch, bwInk ? ink : emerald, 2.2);

      // Alternating motif inside the window: Crescent moon / 8-point star.
      final motifCy = (archSpring + archBot) * 0.48;
      if (i.isEven) {
        final rOuter = panelW * 0.16;
        final crescent = Path()
          ..addOval(Rect.fromCircle(center: Offset(cx, motifCy), radius: rOuter));
        final cutout = Path()
          ..addOval(
            Rect.fromCircle(
              center: Offset(cx + rOuter * 0.42, motifCy - rOuter * 0.12),
              radius: rOuter * 0.82,
            ),
          );
        final moon = Path.combine(PathOperation.difference, crescent, cutout);
        canvas.drawPath(moon, Paint()..color = goldFill);
        canvas.drawPath(moon, innerAccentStroke);
      } else {
        final star = _eightPointStar(
          center: Offset(cx, motifCy),
          outerR: panelW * 0.18,
          innerR: panelW * 0.08,
        );
        canvas.drawPath(star, Paint()..color = goldFill);
        canvas.drawPath(star, innerAccentStroke);
      }

      // Bottom base flap.
      final skirt = Path()
        ..moveTo(px, waistY)
        ..lineTo(px + panelW, waistY)
        ..lineTo(px + panelW - 22, skirtY)
        ..lineTo(px + 22, skirtY)
        ..close();
      canvas.drawPath(skirt, Paint()..color = tabFill);
      canvas.drawPath(skirt, solidStroke);
      _drawDashedLine(canvas, Offset(px, waistY), Offset(px + panelW, waistY), ink, 2.4);
      _drawDashedLine(canvas, Offset(px, neckY), Offset(px + panelW, neckY), ink, 2.4);
    }
  }

  Path _eightPointStar({
    required Offset center,
    required double outerR,
    required double innerR,
  }) {
    final p = Path();
    const points = 16;
    for (var i = 0; i < points; i++) {
      final angle = -math.pi / 2 + (i * math.pi * 2 / points);
      final r = i.isEven ? outerR : innerR;
      final pt = Offset(
        center.dx + math.cos(angle) * r,
        center.dy + math.sin(angle) * r,
      );
      if (i == 0) {
        p.moveTo(pt.dx, pt.dy);
      } else {
        p.lineTo(pt.dx, pt.dy);
      }
    }
    p.close();
    return p;
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Color color,
    double width,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final total = (end - start).distance;
    const dash = 10.0;
    const gap = 7.0;
    var dist = 0.0;
    while (dist < total) {
      final t1 = dist / total;
      final t2 = math.min(dist + dash, total) / total;
      canvas.drawLine(
        Offset.lerp(start, end, t1)!,
        Offset.lerp(start, end, t2)!,
        paint,
      );
      dist += dash + gap;
    }
  }

  void _drawDashedPath(
    Canvas canvas,
    Path path,
    Color color,
    double width,
  ) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    for (final metric in path.computeMetrics()) {
      var dist = 0.0;
      const dash = 9.0;
      const gap = 6.0;
      while (dist < metric.length) {
        final sub = metric.extractPath(dist, math.min(dist + dash, metric.length));
        canvas.drawPath(sub, paint);
        dist += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Fanous3DNetPainter old) => old.bwInk != bwInk;
}

class _LanternStreetSheetBody extends StatelessWidget {
  const _LanternStreetSheetBody({
    required this.isAr,
    required this.bwInk,
    required this.kids,
    required this.border,
  });

  final bool isAr;
  final bool bwInk;
  final List<LocalPrintChild> kids;
  final Color border;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.light;
    final ink = palette.ink;
    final stroke = bwInk ? ink : palette.paperEmerald;
    final oddFill = bwInk
        ? Colors.white // audit-ok: physical A4 paper sheet for home printing
        : palette.paperGold.withValues(alpha: 0.24);
    const oddDays = {21, 23, 25, 27, 29};

    final roles = [
      for (var i = 0; i < kids.length && i < 4; i++)
        '${kids[i].name} — ${roleForRamadanBand(kids[i].ageGroup, isAr, i)}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var row = 0; row < 5; row++) ...[
          if (row > 0) const SizedBox(height: 12),
          SizedBox(
            width: 945,
            height: 166,
            child: Row(
              children: [
                for (var col = 0; col < 6; col++) ...[
                  if (col > 0) const SizedBox(width: 12),
                  Builder(
                    builder: (_) {
                      final day = row * 6 + col + 1;
                      final isOdd = oddDays.contains(day);
                      final cellBorder = isOdd && !bwInk
                          ? palette.paperGold
                          : stroke;
                      return Container(
                        width: 147,
                        height: 166,
                        decoration: BoxDecoration(
                          color: isOdd
                              ? oddFill
                              : Colors.white, // audit-ok: physical A4 lantern cell for coloring
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: cellBorder,
                            width: isOdd ? 2.4 : 1.5,
                          ),
                        ),
                        child: Stack(
                          children: [
                            CustomPaint(
                              size: const Size(147, 166),
                              painter: _OutlineLanternCellPainter(
                                strokeColor: stroke,
                                accentColor: cellBorder,
                                crescentColor: bwInk ? ink : palette.paperGold,
                                isOdd: isOdd,
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 66,
                              child: Text(
                                _localizeDigits(day, isAr),
                                textAlign: TextAlign.center,
                                style: GoogleFonts.cairo(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  height: 1.0,
                                  color: ink,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Container(
          width: 945,
          height: 158,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white, // audit-ok: physical A4 paper sheet for home printing
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border.withValues(alpha: 0.45), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CustomPaint(
                    size: const Size(18, 18),
                    painter: _CrescentBadgePainter(
                      fillColor: bwInk ? Colors.white : palette.paperGold, // audit-ok: crescent badge swatch on paper
                      strokeColor: bwInk ? ink : palette.paperEmerald,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 878,
                    child: Text(
                      roles.isNotEmpty
                          ? (isAr
                              ? 'أدوار أطفالنا اللطيفة في ليالي رمضان (الهلال يميّز الليالي الوترية ٢١–٢٩):'
                              : 'Children\'s Gentle Ramadan Roles (Crescent marks odd nights 21–29):')
                          : (isAr
                              ? 'علّق الخريطة على باب الثلاجة ولوّن قنديلًا كل ليلة مع الأسرة (الليالي الوترية ٢١–٢٩).'
                              : 'Hang on the fridge and color one lantern each night together (odd nights 21–29).'),
                      maxLines: roles.isNotEmpty ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                        color: ink,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ],
              ),
              if (roles.isNotEmpty) ...[
                const SizedBox(height: 10),
                for (var r = 0; r < (roles.length > 2 ? 2 : 1); r++) ...[
                  if (r > 0) const SizedBox(height: 8),
                  SizedBox(
                    height: 40,
                    child: Row(
                      children: [
                        for (var c = 0; c < 2; c++)
                          if (r * 2 + c < roles.length) ...[
                            if (c > 0) const SizedBox(width: 14),
                            Container(
                              width: 444,
                              height: 40,
                              alignment: AlignmentDirectional.centerStart,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              decoration: BoxDecoration(
                                color: bwInk
                                    ? Colors.white // audit-ok: printable role card on physical paper sheet
                                    : palette.paperIvory,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: border, width: 1.3),
                              ),
                              child: Text(
                                roles[r * 2 + c],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.cairo(
                                  fontSize: 17.5,
                                  fontWeight: FontWeight.w700,
                                  color: ink,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                          ],
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TableCardsSheetBody extends StatelessWidget {
  const _TableCardsSheetBody({
    required this.isAr,
    required this.bwInk,
    required this.kids,
    required this.border,
  });

  final bool isAr;
  final bool bwInk;
  final List<LocalPrintChild> kids;
  final Color border;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.light;
    final ink = palette.ink;
    final headerBg = bwInk
        ? Colors.white // audit-ok: physical A4 paper sheet for home printing
        : palette.paperEmerald.withValues(alpha: 0.10);
    final jarPrompts = isAr
        ? const [
            'شكرًا لأنك أسعدتَ بيتنا اليوم بـ: ____________',
            'أجمل خُلُق رأيناه فيك هذا الأسبوع: ____________',
            'دعوة صادقة من القلب قبل الأذان لـ: ____________',
            'موقف كرم وتعاون لن ننساه من: ____________',
            'شيء جميل تعلّمناه معًا في سهرتنا: ____________',
            'كلمة محبة نضعها في جرّة الأسرة لـ: ____________',
          ]
        : const [
            'Thank you for brightening today by: ____________',
            'A kind habit I loved seeing in you: ____________',
            'A warm heartfelt dua before sunset for: __________',
            'A generous moment we noticed from: ____________',
            'Something wise we learned together: ____________',
            'A loving note for our Kind-Words Jar: ____________',
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 30,
          child: Text(
            isAr
                ? 'بطاقات سفراء السفرة — قصّ كل بطاقة واطوِها من الوسط لتقف أمام طبق الطفل'
                : 'Iftar Table Ambassador Cards — Cut each card & fold along the middle line',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.cairo(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: ink,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: 14),
          SizedBox(
            width: 945,
            height: 274,
            child: Row(
              children: [
                for (var col = 0; col < 2; col++) ...[
                  if (col > 0) const SizedBox(width: 21),
                  Builder(
                    builder: (_) {
                      final idx = row * 2 + col;
                      final hasChild = idx < kids.length;
                      final band = hasChild
                          ? kids[idx].ageGroup
                          : const ['4-6', '7-9', '10-12', '13+'][idx];
                      final role = roleForRamadanBand(band, isAr, idx);
                      final desc = _roleDescriptionForBand(band, isAr, idx);
                      final nameLine = hasChild
                          ? kids[idx].name
                          : (isAr ? 'الاسم: ______________' : 'Name: ______________');

                      return Container(
                        width: 462,
                        height: 274,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white, // audit-ok: physical A4 foldable table card
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: border, width: 2),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Transform.rotate(
                              angle: math.pi,
                              child: Container(
                                height: 74,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: headerBg,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  role,
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.cairo(
                                    fontSize: 19,
                                    fontWeight: FontWeight.w800,
                                    color: border,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              height: 26,
                              alignment: Alignment.center,
                              child: Text(
                                isAr
                                    ? '- - - -  اطوِ هنا لتقف البطاقة  - - - -'
                                    : '- - - -  Fold here to stand card  - - - -',
                                maxLines: 1,
                                style: GoogleFonts.cairo(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: palette.textSecondary,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ),
                            SizedBox(
                              height: 146,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    nameLine,
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.cairo(
                                      fontSize: 27,
                                      fontWeight: FontWeight.w800,
                                      height: 1.25,
                                      color: ink,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    role,
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.cairo(
                                      fontSize: 18.5,
                                      fontWeight: FontWeight.w800,
                                      color: border,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    desc,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.cairo(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      height: 1.3,
                                      color: ink,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        SizedBox(
          height: 32,
          child: Text(
            isAr
                ? 'قصاصات مرطبان الكلمات الطيبة — اقرؤوها معًا ليلة الجمعة'
                : 'Kind-Words Jar Slips — Cut strips & read together on Friday',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.cairo(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: ink,
              decoration: TextDecoration.none,
            ),
          ),
        ),
        const SizedBox(height: 10),
        for (var row = 0; row < 3; row++) ...[
          if (row > 0) const SizedBox(height: 12),
          SizedBox(
            width: 945,
            height: 118,
            child: Row(
              children: [
                for (var col = 0; col < 2; col++) ...[
                  if (col > 0) const SizedBox(width: 21),
                  Container(
                    width: 462,
                    height: 118,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white, // audit-ok: printable kindness slip on physical paper
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: bwInk ? ink : palette.paperGold,
                        width: 1.8,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: bwInk ? ink : palette.paperGold,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 406,
                          child: Text(
                            jarPrompts[row * 2 + col],
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.cairo(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w700,
                              height: 1.4,
                              color: ink,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PrintableFooter extends StatelessWidget {
  const _PrintableFooter({
    required this.border,
    required this.bwInk,
    required this.footerTitle,
    required this.qrUrl,
    required this.qrCodeLabel,
  });

  final Color border;
  final bool bwInk;
  final String footerTitle;
  final String qrUrl;
  final String qrCodeLabel;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.light;
    final ink = palette.ink;
    return Container(
      width: 945,
      height: 130,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white, // audit-ok: physical A4 paper footer strip
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 102,
            height: 102,
            padding: const EdgeInsets.all(4),
            color: Colors.white, // audit-ok: optical QR quiet zone for camera scanners
            child: QrImageView(
              data: qrUrl,
              size: 94,
              gapless: true,
              backgroundColor: Colors.white, // audit-ok: optical QR quiet zone for camera scanners
              eyeStyle: QrEyeStyle(color: ink, eyeShape: QrEyeShape.square),
              dataModuleStyle: QrDataModuleStyle(
                color: ink,
                dataModuleShape: QrDataModuleShape.square,
              ),
            ),
          ),
          const SizedBox(width: 18),
          SizedBox(
            width: 790,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  footerTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                    color: ink,
                    decoration: TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'tg-api.alsaba.cloud/go?ref=$qrCodeLabel',
                  textDirection: TextDirection.ltr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                    fontSize: 17.5,
                    fontWeight: FontWeight.w800,
                    color: bwInk ? ink : palette.paperEmerald,
                    decoration: TextDecoration.none,
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

class _CrescentBadgePainter extends CustomPainter {
  const _CrescentBadgePainter({
    required this.fillColor,
    required this.strokeColor,
  });

  final Color fillColor;
  final Color strokeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width * 0.44;
    final outer = Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    final inner = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(cx + r * 0.42, cy - r * 0.12),
          radius: r * 0.82,
        ),
      );
    final crescent = Path.combine(PathOperation.difference, outer, inner);
    canvas.drawPath(crescent, Paint()..color = fillColor);
    canvas.drawPath(
      crescent,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(covariant _CrescentBadgePainter old) =>
      old.fillColor != fillColor || old.strokeColor != strokeColor;
}

class _OutlineLanternCellPainter extends CustomPainter {
  const _OutlineLanternCellPainter({
    required this.strokeColor,
    required this.accentColor,
    required this.crescentColor,
    required this.isOdd,
  });

  final Color strokeColor;
  final Color accentColor;
  final Color crescentColor;
  final bool isOdd;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = isOdd ? accentColor : strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = isOdd ? 2.2 : 1.8
      ..strokeJoin = StrokeJoin.round;

    // Top ring.
    canvas.drawCircle(Offset(w * 0.5, h * 0.13), w * 0.055, paint);

    // Dome cap.
    final dome = Path()
      ..moveTo(w * 0.28, h * 0.28)
      ..quadraticBezierTo(w * 0.5, h * 0.13, w * 0.72, h * 0.28)
      ..close();
    canvas.drawPath(dome, paint);

    // Lantern hexagon body.
    final body = Path()
      ..moveTo(w * 0.26, h * 0.30)
      ..lineTo(w * 0.74, h * 0.30)
      ..lineTo(w * 0.80, h * 0.58)
      ..lineTo(w * 0.67, h * 0.78)
      ..lineTo(w * 0.33, h * 0.78)
      ..lineTo(w * 0.20, h * 0.58)
      ..close();
    canvas.drawPath(body, paint);

    // Base pedestal.
    final base = Path()
      ..moveTo(w * 0.36, h * 0.78)
      ..lineTo(w * 0.64, h * 0.78)
      ..lineTo(w * 0.59, h * 0.88)
      ..lineTo(w * 0.41, h * 0.88)
      ..close();
    canvas.drawPath(base, paint);

    if (isOdd) {
      final cx = w * 0.84;
      final cy = h * 0.15;
      const r = 9.0;
      final outer = Path()
        ..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
      final inner = Path()
        ..addOval(
          Rect.fromCircle(
            center: Offset(cx + r * 0.42, cy - r * 0.12),
            radius: r * 0.82,
          ),
        );
      final moon = Path.combine(PathOperation.difference, outer, inner);
      canvas.drawPath(moon, Paint()..color = crescentColor);
      canvas.drawPath(
        moon,
        Paint()
          ..color = strokeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _OutlineLanternCellPainter old) =>
      old.strokeColor != strokeColor ||
      old.accentColor != accentColor ||
      old.crescentColor != crescentColor ||
      old.isOdd != isOdd;
}
