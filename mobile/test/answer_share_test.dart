// Copy/share under Noor's answer: plain text out, not Markdown.

import 'package:flutter_test/flutter_test.dart';

import 'package:almorabbi/features/share/share_service.dart';

void main() {
  test('Markdown marks are taken out, the words kept', () {
    const md = '## خطوة اليوم\n\n**اجلس** معه عشر دقائق.\n- اسأله عن يومه\n* واسمع\n\n\n\nانتهى';
    expect(ShareService.plainAnswer(md),
        'خطوة اليوم\n\nاجلس معه عشر دقائق.\n• اسأله عن يومه\n• واسمع\n\nانتهى');
  });
}
