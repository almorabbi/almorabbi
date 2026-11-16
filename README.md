# المربّي (`Al-Morabbi`) — الإصدار `v2.0.0`

[![Backend tests](https://github.com/almorabbi/almorabbi/actions/workflows/backend.yml/badge.svg)](https://github.com/almorabbi/almorabbi/actions/workflows/backend.yml)
[![Flutter](https://github.com/almorabbi/almorabbi/actions/workflows/flutter.yml/badge.svg)](https://github.com/almorabbi/almorabbi/actions/workflows/flutter.yml)
[![Docker](https://github.com/almorabbi/almorabbi/actions/workflows/docker.yml/badge.svg)](https://github.com/almorabbi/almorabbi/actions/workflows/docker.yml)

**«المربّي» (`com.alsaba.almorabbi`)** رفيق تربوي إسلامي متكامل للأسرة **من الحمل حتى ١٨ سنة** بالعربية والإنجليزية — **مجاني بالكامل لوجه الله بلا إعلانات ولا اشتراكات ولا مشتريات داخلية** ([Google Play](https://play.google.com/store/apps/details?id=com.alsaba.almorabbi)).

### ركائز الإصدار `2.0.0`
- **واجهة «نور والقناديل» حول الطفل (`child_home_v2`):** دربٌ يومي واضح تحت سماء تتبع ساعة اليوم والمواسم بأسلوب الورق المقصوص (`Paper-Cut`).
- **حساب الأسرة المشترك (`families`):** مشاركة متابعة الأطفال وقناديلهم بأمان بين هاتفَي الوالدَين عبر رمز دعوة مؤقّت، مع قفل الهوية ومفتاح الاستعادة (`docs/RELEASE_v2.0_RUNBOOK.md`).
- **«فوازير نور العائلية» (`family_puzzles`):** تحديات تفكير بصري ومسارات مياه وتفكير جانبي للوالدَين والطفل معًا.
- **حزمة رمضان ٢.٠ الإبداعية:** فوازير الـ ٣٠ ليلة، الحكواتي والكبسولات الصوتية بلا شاشة، عدّة الفانوس الورقية للطباعة (`/print/lantern-craft`)، وتعهّد شوال وبطاقة العيد الخالية من البيانات الشخصية.

ويجمع المساعد التربوي المعتمد على RAG بين ثلاث مجالات معرفة:

- **المجال الطبي:** سلوك ونفسية الأطفال، دون تقديم تشخيص سريري مباشر أو وصف أدوية.
- **المجال الشرعي والتربوي:** تربية نبوية وفقه واقع الأسرة المسلمة المعاصرة، مع إبقاء القرآن بنصّه العربي دائمًا.
- **المجال السيبراني:** حماية الأطفال رقميًا من المخاطر، وإدارة وقت الشاشة.

هيكل المستودع:

- `mobile/` : تطبيق Flutter لأندرويد (`com.alsaba.almorabbi`).
- `backend/` : خدمات الـ API ومحرك الـ RAG وحراس النصوص الشرعية.
- `frontend/` : صفحة الهبوط والتعريف الثنائية اللغة (`/go`, `/ui/`) وعُدّة الطباعة.
- `knowledge_base/` : مستودع المعرفة الهجين، الدروس، القصص، والبرامج الموسمية.
- `ops/` و`scripts/` : سكربتات التشغيل، بوابات الجودة والإطلاق، والتحقق التلقائي.

---

## التحقق من وحدات المعرفة

للتحقق من صحة ملفات JSON في knowledge_base/ مقابل الـ Schema:

```bash
python ops/tools/validate_knowledge_units.py --dir knowledge_base/examples
```

---

## تشغيل واجهة الـ API

```bash
cd ~/projects/tutor-guardian
PYTHONPATH=$(pwd):$PYTHONPATH python -m uvicorn backend.app.main:app --reload --port 8090
```

ثم افتح http://localhost:8090/docs للاطلاع على Swagger UI، وعميل الاختبار على http://localhost:8090/ui/

> **ملاحظة:** تعمل `mobile/` و`backend/` معًا لخدمة التطبيق على أندرويد، وتخدم `frontend/` صفحة الهبوط الثنائية اللغة (`/go`) وصفحات الطباعة المخصّصة للأسر.

---

## التشغيل عبر Docker

```bash
docker compose up -d ollama
docker compose exec ollama ollama pull qwen2.5:3b   # لمرة واحدة
docker compose up -d backend
# API: http://localhost:8000 · عميل الاختبار: http://localhost:8000/ui/
```

الإعدادات كلها في `.env.example` (انسخه إلى `.env`). الافتراضي في الكود استدلال محلي عبر Ollama (`LLM_PRIMARY_PROVIDER=ollama`)، أما **الإنتاج** فيعمل بـ DeepSeek السحابي أساسيًا (`LLM_PRIMARY_PROVIDER=deepseek`) مع Ollama احتياطيًا، وتُخفى أسماء الأطفال قبل أي نداء سحابي — التفاصيل في `docs/catalog/06-ai.md`.

> **المنفذ:** أمر `uvicorn` أعلاه يستعمل `8090`، أما `docker compose` فيفتح `8000` (`BACKEND_HOST_PORT`).

---

## حارس سلامة قاعدة المعرفة (مهم)

يقارن وحدات المعرفة ↔ الـ schema ↔ `taxonomy.py` ↔ ChromaDB ويمنع أي انحراف صامت.

```bash
./check.sh                         # فحص سريع (schema / enums / taxonomy)
./check.sh --full                  # + تزامن ChromaDB + الاختبارات
python ops/tools/check_kb_integrity.py --check-index   # الفحص الكامل
```

الفحص يعمل تلقائياً عند كل `git commit` (عبر `.githooks/pre-commit`) وفي الـ CI.
تفعيل الـ hook بعد الاستنساخ:

```bash
git config core.hooksPath .githooks
```

عند إضافة/تعديل وحدات معرفة، شغّل التنظيف والإعادة:

```bash
python ops/tools/normalize_units.py    # تنظيف قيم enum
python ops/tools/build_vector_db.py    # إعادة بناء الفهرس + units_index.json
```

---

## الاختبارات

```bash
backend/.venv/bin/python -m pytest backend/tests   # آلاف الاختبارات (انظر docs/catalog/08-gotchas.md §2 قبل الاعتماد على python المجرد)
```

راجع `API.md` لعقد الـ API الكامل (للفريق الذي يبني تطبيق الموبايل).

---

## CI / CD (الاختبار التلقائي)

workflows تحرس الـ `main` branch (القائمة الكاملة في `.github/workflows/` وشرحها في `docs/catalog/07-infra-deploy.md`):

| Workflow | يـ guard ضد |
|---|---|
| `backend.yml` | regression في اختبارات الباكند (pytest) + سلامة قاعدة المعرفة + ruff — وهي بوابة النشر |
| `flutter.yml` | analyzer warnings/errors + failing widget tests على الـ mobile |
| `docker.yml` | image لا تبني أو لا تـ start — Phase 0 regression (privacy policy مفقود) |
| `deploy.yml` | بوابة (gate) ← بناء صورة ← نشر على الـ VPS عبر runner ذاتي الاستضافة (انظر أدناه) |

كل workflow يـ skip إذا الـ paths تاعته ما اتغيرتش. الـ concurrency بيـ cancel in-flight runs على نفس الـ ref. الـ `main` branch لازم يكون **protected** (Settings → Branches → Require status checks: backend, flutter, docker).

> 🚨 **`push` إلى `main` على مسارات الباكند/المعرفة/`ops/tools`/`ops/scripts`/`frontend` = نشر إنتاج** (`deploy.yml`). لا تدمج ما لست مستعدًا لرؤيته حيًّا.

### Production deploy

`deploy.yml` **لا** يستعمل `workflow_run` ولا SSH: لا يبدأ إلا في `almorabbi/almorabbi` ومع متغير المستودع `CUTOVER_DONE=true`، ثم يتحقق (job `gate`) أن "Backend tests" نجح لنفس الـ commit عبر API (`ops/tools/deploy_gate.py`)، ثم `image` يبني ويدخّن الصورة على runner مستضاف عند GitHub ويدفعها إلى GHCR، ثم `deploy` يعمل **على الـ VPS نفسه** (runner ذاتي `self-hosted, production`) فيسحب الصورة ويتحقق من `/health` و`/privacy-policy` و`/api/app-config` ويرجع تلقائيًا للصورة السابقة عند الفشل؛ و`alert` يرسل تنبيه تلجرام عند أي فشل. التفاصيل الكاملة في تعليق رأس `.github/workflows/deploy.yml` وفي `docs/OPS_RUNBOOK.md` §4.1.

تشغيل يدوي: `Actions → Deploy → Run workflow` (على `main` فقط، ومحروس بالبوابة نفسها).
