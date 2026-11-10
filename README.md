# Tutor Guardian – الذكاء التربوي الحارس

[![Backend tests](https://github.com/almorabbi/almorabbi/actions/workflows/backend.yml/badge.svg)](https://github.com/almorabbi/almorabbi/actions/workflows/backend.yml)
[![Flutter](https://github.com/almorabbi/almorabbi/actions/workflows/flutter.yml/badge.svg)](https://github.com/almorabbi/almorabbi/actions/workflows/flutter.yml)
[![Docker](https://github.com/almorabbi/almorabbi/actions/workflows/docker.yml/badge.svg)](https://github.com/almorabbi/almorabbi/actions/workflows/docker.yml)

هذا المشروع يطوِّر مساعدًا تربويًا ذكيًا للأهل، يعتمد على RAG، ويجمع بين ثلاث مجالات معرفة:

المجال الطبي (سلوك ونفسية الأطفال، دون تقديم تشخيص سريري مباشر أو وصف أدوية).

المجال الشرعي والتربوي (تربية نبوية وفقه واقع الأسرة المسلمة المعاصرة).

المجال السيبراني (حماية الأطفال رقميًا من المخاطر، وإدارة استخدام الأجهزة والألعاب).

هيكل المشروع الحالي:

backend/ : خدمات الـ API ومحرك الـ RAG والـ Guardrails.

frontend/ : واجهة استخدام الأهل ولوحة التحكم.

knowledge_base/ : مستودع المعرفة الهجين، بنية JSON + Vector DB.

ops/ : سكربتات التشغيل، الأتمتة، وأدوات التطوير.

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

> **ملاحظة:** الـ backend/API هو المنتج. صفحة `frontend/` مجرد عميل اختبار — المنتج النهائي تطبيق موبايل.

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
