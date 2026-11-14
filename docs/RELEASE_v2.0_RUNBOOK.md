# دليل إغلاق البوابات وإعلان الإصدار `2.0.0`

يحدّد هذا الدليل تسلسل التشغيل المنضبط للانتقال من `1.0.x` إلى `2.0.0` على الإنتاج، مع إبقاء بوابة السكّ العاري وميزة حساب الأسرة محميتَين حتى يتحقّق شرط التبني الآمن (`restore_key_share >= 85%`).

---

## ١) بوابات إعلان `2.0.0` الأربع

يُقاس الاستعداد الكامل عبر الأمر القرائي فقط:

```bash
python3 ops/scripts/v2_gate_check.py --json
```

ولا يرتفع رقم الإصدار في `mobile/pubspec.yaml` إلى `2.0.0` إلا عندما تعود النتيجة `"ready_for_v2_0_0": true` عبر تحقّق البوابات الأربع معًا:

1. **`gate1_headlines` — العناوين الثلاثة على الإنتاج:**
   - `child_centric_home`: واجهة «الرئيسية حول الطفل» (`child_home_v2`).
   - `family_account`: جداول حساب الأسرة (`families` و`family_members`) وموجّه `backend/app/routers/families.py`.
   - `visual_unification`: توثيق `docs/catalog/VISUAL_UNIFICATION_2_0.md` وحسم `STORY_MOTION_MODE` على الإنتاج إلى `motion` أو `static`.
2. **`gate2_d7_action` — الفعل التربوي في الأسبوع الأول:**
   - معدل `strict_d7_rate_4w >= 12%` مع حجم عينة `eligible_families_4w >= 150` عبر ٤ أسابيع ناضجة.
3. **`gate3_identity_lock` — قفل الهوية ومفتاح الاستعادة:**
   - نسبة الأجهزة النشطة آخر ١٤ يومًا التي تحمل مفتاح استعادة `restore_key_share >= 0.85` (`85%`).
   - تفعيل `SESSION_MINT_ENFORCE=1` على الإنتاج.
4. **`gate4_zero_unconsumed` — إغلاق القدرات غير المستهلكة:**
   - عدد بنود `⚠️` في `docs/catalog/FEATURES.md` يساوي `0`.

---

## ٢) تسلسل إغلاق السكّ العاري وتفعيل حساب الأسرة (البوابة ٣)

### الخطوة أ — رفع حد البناء الأدنى إلى `122`

البناء `122` (`1.0.77`) هو أول بناء يسجّل مفتاح الاستعادة (`device_restore_keys`). بعد التأكد من نتائج الفحص المسبّق عبر `ops/scripts/min_build.sh plan 122`:

```bash
bash ops/scripts/min_build.sh apply 122
```

يُحدّث السكربت ملف `.env` بعد أخذ نسخة احتياطية `.env.bak.<UTC>`، ويعيد إنشاء حاوية `backend`، ويتحقّق من أن `/api/app-config` يخدم `"minimum_build_number": 122`. يُترك بعدها التحديث الطبيعي حتى تصعد نسبة الأجهزة الجديدة وتتقادم صفوف الأجهزة الأقدم.

### الخطوة ب — المتابعة اليومية لنسبة مفتاح الاستعادة

```bash
python3 ops/tools/bare_mint_readiness.py --days 14 --min-build 122
```

تُراقَب النسبة يوميًا (`active_with_restore_key / active_devices`) حتى تبلغ `>= 0.85` مع انخفاض حالات السكّ العاري (`bare`) إلى حدٍّ مقبول.

### الخطوة ج — التفعيل المتزامن على الإنتاج عند بلوغ `>= 85%`

1. أخذ نسخة احتياطية مشدّدة الصلاحيات من `.env`:

```bash
cp -p .env ".env.bak.v2_cutover.$(date -u +%Y%m%dT%H%M%SZ)"
chmod 600 .env .env.bak.*
```

2. ضبط المتغيّرين التاليين في `.env` مع **الإبقاء على `IDENTITY_CROSS_DEVICE=0`** (قفل الربط القديم عبر الأجهزة):
   - `SESSION_MINT_ENFORCE=1`
   - `FAMILY_SHARING_ENABLED=1`
   - `IDENTITY_CROSS_DEVICE=0`

3. فحص متغيّرات البيئة وإعادة إنشاء حاوية `backend`:

```bash
chmod 600 .env
python3 ops/tools/deploy_gate.py --check-env .env
docker compose -f docker-compose.production.yml up -d --no-build --remove-orphans backend
```

4. التحقق من الاستجابة الحية والبوابات:

```bash
curl -fsS http://127.0.0.1:8000/api/app-config
python3 ops/scripts/v2_gate_check.py --json
```

يجب أن يظهر `"family_sharing_enabled": true` في `/api/app-config`، وأن تعود نتيجة `"ready_for_v2_0_0": true` من `v2_gate_check.py`.

### الخطوة د — رفع رقم الإصدار والطرح

1. تعديل `version` في `mobile/pubspec.yaml` إلى `2.0.0+<next>`.
2. إضافة ملف ملاحظات الإصدار الثنائي اللغة في `docs/release_notes/2.0.0+<next>.json`.
3. تشغيل سير عمل الإطلاق على المتجر ثم تحديث متغيّر المستودع `E2E_BASELINE_REF` بعد اعتماد الإصدار على مسار الإنتاج الكامل.

---

## ٣) خطة الرجوع الفوري (Rollback)

في حال ظهور أي عارض تشغيلي بعد تفعيل البوابة ٣:

1. تعديل `.env` (أو استعادة آخر نسخة `.env.bak.*` عبر `cp -p` مع `chmod 600`):
   - ضبط `FAMILY_SHARING_ENABLED=0` لإخفاء واجهة حساب الأسرة وتعطيل مسارات `/api/families/*` فورًا.
   - و/أو ضبط `SESSION_MINT_ENFORCE=0` لتخفيف قفل السكّ العاري مؤقتًا.
   - الإبقاء دائمًا على `IDENTITY_CROSS_DEVICE=0`.
2. التحقق وإعادة إنشاء الحاوية:

```bash
chmod 600 .env
python3 ops/tools/deploy_gate.py --check-env .env
docker compose -f docker-compose.production.yml up -d --no-build --remove-orphans backend
```

لا يمسّ هذا الرجوع جداول قاعدة البيانات (`families`, `family_members`, `family_invites`, `family_deletion_requests`) ولا يحذف أي بيانات محلية على هواتف الوالدَين.
