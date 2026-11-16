/// Personalized on-device Printable Ramadan Kit («عدّة رمضان الورقية لأسرتك»).
///
/// Privacy invariant: children's names & age bands are read strictly locally
/// from [childrenListProvider] / [activeChildProfileProvider] and rendered only
/// on the parent's phone (or exported locally as an image for home printing).
/// Never sent to `/print/*` network URLs.
library;

import 'dart:io';

import 'package:flutter/material.dart';
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

class LocalPrintChild {
  const LocalPrintChild({required this.name, required this.ageGroup});

  final String name;
  final String ageGroup;
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

  String _roleForBand(String band, bool isAr, int index) {
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
      final widgetToCapture = Directionality(
        textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
        child: Material(
          color: Colors.white, // audit-ok: physical A4 paper sheet exported for printing
          child: SizedBox(
            width: 1080,
            height: 1528,
            child: Padding(
              padding: const EdgeInsets.all(42),
              child: _PrintablePosterCard(
                isAr: isAr,
                bwInk: _bwInk,
                headline: l10n.ramadanPrintKitTitle,
                namesBanner: l10n.ramadanPrintKitForChildren(namesText),
                roles: [
                  for (var i = 0; i < kids.length; i++)
                    '${kids[i].name} — ${_roleForBand(kids[i].ageGroup, isAr, i)}',
                ],
                footerTitle: l10n.ramadanPrintKitBannerHint,
                qrUrl: isAr
                    ? 'https://tg-api.alsaba.cloud/go?ref=PR03'
                    : 'https://tg-api.alsaba.cloud/go?ref=PR04',
                qrCodeLabel: isAr ? 'PR03' : 'PR04',
                compact: false,
              ),
            ),
          ),
        ),
      );

      final bytes = await ScreenshotController().captureFromWidget(
        widgetToCapture,
        pixelRatio: 1.5,
        targetSize: const Size(1080, 1528),
      );
      final dir = await Directory.systemTemp.createTemp('tg_print_kit_');
      final file = File('${dir.path}/ramadan_kit_$lang.png');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: l10n.ramadanPrintKitTitle,
        ),
      );
    } catch (_) {
      // Calm silent fallback in headless environments without share plugin.
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
          const SizedBox(height: 14),
          _PrintablePosterCard(
            key: const ValueKey('print_kit_poster_preview'),
            isAr: isAr,
            bwInk: _bwInk,
            headline: l10n.ramadanPrintKitTitle,
            namesBanner: l10n.ramadanPrintKitForChildren(namesText),
            roles: [
              for (var i = 0; i < kids.length; i++)
                '${kids[i].name} — ${_roleForBand(kids[i].ageGroup, isAr, i)}',
            ],
            footerTitle: l10n.ramadanPrintKitBannerHint,
            qrUrl: isAr
                ? 'https://tg-api.alsaba.cloud/go?ref=PR03'
                : 'https://tg-api.alsaba.cloud/go?ref=PR04',
            qrCodeLabel: isAr ? 'PR03' : 'PR04',
            compact: true,
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

class _PrintablePosterCard extends StatelessWidget {
  const _PrintablePosterCard({
    super.key,
    required this.isAr,
    required this.bwInk,
    required this.headline,
    required this.namesBanner,
    required this.roles,
    required this.footerTitle,
    required this.qrUrl,
    required this.qrCodeLabel,
    required this.compact,
  });

  final bool isAr;
  final bool bwInk;
  final String headline;
  final String namesBanner;
  final List<String> roles;
  final String footerTitle;
  final String qrUrl;
  final String qrCodeLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.light;
    final ink = palette.ink;
    final border = bwInk ? ink : palette.paperEmerald;
    final fill = bwInk ? Colors.white : palette.paperIvory;
    final pillFill = bwInk ? Colors.white : palette.paperEmerald.withValues(alpha: 0.12);
    final pad = compact ? 14.0 : 28.0;

    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(compact ? 18 : 28),
        border: Border.all(color: border, width: compact ? 2 : 3.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Text(
            headline,
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
              fontSize: compact ? 17 : 34,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
          SizedBox(height: compact ? 6 : 12),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 18,
              vertical: compact ? 6 : 12,
            ),
            decoration: BoxDecoration(
              color: pillFill,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border, width: 1.4),
            ),
            child: Text(
              namesBanner,
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: compact ? 13.5 : 24,
                fontWeight: FontWeight.w800,
                color: ink,
              ),
            ),
          ),
          SizedBox(height: compact ? 10 : 22),
          if (compact)
            _LanternStreetPreviewGrid(bwInk: bwInk, isAr: isAr, compact: true)
          else
            Expanded(
              child: _LanternStreetPreviewGrid(
                bwInk: bwInk,
                isAr: isAr,
                compact: false,
              ),
            ),
          if (roles.isNotEmpty) ...[
            SizedBox(height: compact ? 10 : 18),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final r in roles.take(4))
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 10 : 16,
                      vertical: compact ? 5 : 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white, // audit-ok: printable role card on physical paper sheet
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: border),
                    ),
                    child: Text(
                      r,
                      style: GoogleFonts.cairo(
                        fontSize: compact ? 11.5 : 20,
                        fontWeight: FontWeight.w700,
                        color: ink,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          SizedBox(height: compact ? 12 : 20),
          Row(
            children: [
              QrImageView(
                data: qrUrl,
                size: compact ? 54 : 112,
                backgroundColor: Colors.white, // audit-ok: optical QR quiet zone for camera scanners
                eyeStyle: QrEyeStyle(color: ink, eyeShape: QrEyeShape.square),
                dataModuleStyle: QrDataModuleStyle(
                  color: ink,
                  dataModuleShape: QrDataModuleShape.square,
                ),
              ),
              SizedBox(width: compact ? 10 : 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      footerTitle,
                      style: GoogleFonts.cairo(
                        fontSize: compact ? 11 : 18,
                        fontWeight: FontWeight.w600,
                        color: ink,
                      ),
                    ),
                    Text(
                      'tg-api.alsaba.cloud/go?ref=$qrCodeLabel',
                      textDirection: TextDirection.ltr,
                      style: GoogleFonts.cairo(
                        fontSize: compact ? 10.5 : 17,
                        fontWeight: FontWeight.w800,
                        color: border,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LanternStreetPreviewGrid extends StatelessWidget {
  const _LanternStreetPreviewGrid({
    required this.bwInk,
    required this.isAr,
    required this.compact,
  });

  final bool bwInk;
  final bool isAr;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.light;
    final stroke = bwInk ? palette.ink : palette.paperEmerald;
    final oddColor = bwInk ? Colors.white : palette.paperGold.withValues(alpha: 0.25);
    const oddDays = {20, 22, 24, 26, 28};

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 30,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisSpacing: compact ? 5 : 10,
        crossAxisSpacing: compact ? 5 : 10,
        childAspectRatio: 0.85,
      ),
      itemBuilder: (_, idx) {
        final day = idx + 1;
        final isOdd = oddDays.contains(day);
        return Container(
          decoration: BoxDecoration(
            color: isOdd ? oddColor : Colors.white,
            borderRadius: BorderRadius.circular(compact ? 8 : 12),
            border: Border.all(
              color: isOdd && !bwInk ? palette.paperGold : stroke,
              width: 1.4,
            ),
          ),
          child: CustomPaint(
            painter: _OutlineLanternCellPainter(
              strokeColor: stroke,
              label: '$day${isOdd ? "☾" : ""}',
              fontSize: compact ? 10 : 19,
            ),
          ),
        );
      },
    );
  }
}

class _OutlineLanternCellPainter extends CustomPainter {
  const _OutlineLanternCellPainter({
    required this.strokeColor,
    required this.label,
    required this.fontSize,
  });

  final Color strokeColor;
  final String label;
  final double fontSize;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeJoin = StrokeJoin.round;

    final dome = Path()
      ..moveTo(w * 0.3, h * 0.28)
      ..quadraticBezierTo(w * 0.5, h * 0.12, w * 0.7, h * 0.28)
      ..close();
    final body = Path()
      ..moveTo(w * 0.28, h * 0.30)
      ..lineTo(w * 0.72, h * 0.30)
      ..lineTo(w * 0.78, h * 0.56)
      ..lineTo(w * 0.66, h * 0.74)
      ..lineTo(w * 0.34, h * 0.74)
      ..lineTo(w * 0.22, h * 0.56)
      ..close();
    canvas.drawPath(dome, paint);
    canvas.drawPath(body, paint);

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: strokeColor,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((w - tp.width) / 2, h * 0.42));
  }

  @override
  bool shouldRepaint(covariant _OutlineLanternCellPainter old) =>
      old.strokeColor != strokeColor || old.label != label;
}
