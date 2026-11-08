# 07 — التشغيل والنشر والبنية التحتية

> **أسماء المتغيرات فقط — لا قيم أسرار هنا ولا في أي ملف كتالوج.** القيم الحية في `/root/tutor-guardian/.env` على الـVPS (600، خارج git؛ مجلد نسخة الإنتاج ما زال بهذا الاسم بحسب `deploy.yml`)، وفي `.env` المحلي لدى المشغّل، وأسرار/متغيرات GitHub Actions في `almorabbi/almorabbi`.

## 1) أين يعمل ماذا

| الماكينة | ما يعمل عليها | وصول |
|---|---|---|
| **VPS** (مشترك مع مشاريع أخرى حيّة — لا تُلمَس) | حاوية `tg_backend` + `tg_redis` · كرونات المربّي · runner ذاتي `vps-tg` (labels `self-hosted, Linux, X64, production`) مسجَّل على `almorabbi/almorabbi` · نسخة git الإنتاج `/root/tutor-guardian` · `/root/tg-backups` · مجلد الميديا `docs/` المنقول rsync | SSH root |
| **اللابتوب** | التطوير · وكلاء PCC (نشر/ريلز/بودكاست) · OMAR (مراقبة كل 30 دقيقة) · مولّدات المحتوى · مفاتيح التوقيع `key.properties`/`almorabbi-upload.jks` (خارج git) | محلي |
| **tg-home** (شبكة خاصة عبر Tailscale) | Ollama للاستدلال الاحتياطي/المحلي · وجهة الأعمال الثقيلة (قاعدة المشغّل: بناء الصور/ffmpeg/TTS الجماعي) | `ssh tg-home` |
| **GitHub Actions** | اختبارات الباكند/Flutter، بناء صورة الباكند (GHCR)، E2E على محاكي، بناء AAB | GitHub-hosted (المستودع عام ⇒ مجاني) |
| **الهاتف** | تطبيق Android (Google Play) | — |

## 2) الحاويات والشبكات والـvolumes (`docker-compose.production.yml`)

| الخدمة | الحاوية | الصورة | حدود | منافذ | healthcheck |
|---|---|---|---|---|---|
| `backend` | `tg_backend` | تُبنى من `backend/Dockerfile` (الإنتاج يسحب `ghcr.io/almorabbi/almorabbi-backend@<digest>` ويوسمها محليًا `tutor-guardian-backend:latest`) | 2 CPU / 4GB (حجز 0.5 CPU / 1GB) | `expose 8000` فقط (لا ربط بالمضيف) | `curl -fsS /health` كل 30ث، `start_period 90s` (إحماء ONNX + Chroma) |
| `redis` | `tg_redis` | `redis:7-alpine` (`--appendonly yes`) | — | داخلي | `redis-cli ping` |

**Volumes:** `tg_sessions`→`/app/ops` (SQLite) · `tg_chroma`→`/app/knowledge_base/chroma_db` · `tg_redis_data`→`/data`.
**Bind mounts (قراءة فقط):** `./docs`→`/app/docs` (ميديا ~2GB) · `./backend/secrets`→`/app/backend/secrets` · `./ops/scripts` · `./ops/tools` · `./ops/data` · `./mobile/assets` · `./frontend` · `./mobile/lib/l10n` (يتطلبه `weekly_kb_gap_report.py`). *الـbinds الصريحة لـ`ops/tools` و`ops/data` ضرورية لأن volume `tg_sessions` على `/app/ops` يحجب ما في الصورة (الحاوية حملت 20 أداة والمستودع 45 يومًا — وكل حرّاس المحتوى الشرعي غائبة).* **أي مسار جديد تحت `/app/ops` يحتاج bind صريحًا.**
**الشبكات:** `internal` (bridge) + `analytics_net` = `analytics-platform_production_network` (خارجية؛ لوصول `analytics_nginx`). 🚨 اسم `redis` العام يحلّ لحاوية analytics ⇒ استعمل `tg_redis`.
**التطوير المحلي** (`docker-compose.yml`): `tg_ollama` (11434) + `tg_backend` (8000؛ `CHILD_MODE_SECRET` افتراضي dev-only) مع volumes `ollama_models`/`app_data`/`chroma_index`.

## 3) الصورة (`backend/Dockerfile`)

`python:3.11-slim` ← مستخدم `appuser` (uid 10001) ← `libgomp1 curl` ← `pip install --require-hashes --no-deps --only-binary` من `.github/ci/requirements-prod.lock` (torch CPU-only من wheel مباشر؛ `pip check` ورفض أي `nvidia-*`) ← تنزيل e5 + Cross-Encoder داخل الصورة ← `COPY backend/ knowledge_base/` ← `HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1` ← **خبز فهرس Chroma** (`python -m app.services.index_seed` ثم نقل `chroma_db`→`chroma_seed`) ← `COPY ops/tools ops/scripts ops/data/campaign_* frontend docs .well-known` ← `CMD uvicorn app.main:app --app-dir backend --host 0.0.0.0 --port 8000`. `PROJECT_ROOT=/app`, `PYTHONPATH=/app/backend`, `CONVERSATIONS_DB=/app/ops/conversations.db`.

## 4) خط النشر (`deploy.yml`) — **كل push إلى main لمسارات `backend/**` · `knowledge_base/**` · `ops/tools/**` · `ops/scripts/**` · `frontend/**` · `docs/lesson_index.json` · `docs/lesson_assets/**` (+ `docker-compose.production.yml` · `backend/Dockerfile` · `requirements*.txt` · `.github/ci/{constraints-prod.txt,requirements-prod.lock}` · `.dockerignore` · `deploy.yml` نفسه) = نشر إنتاج**

| المرحلة | أين | ما تفعله |
|---|---|---|
| `gate` | GitHub-hosted (≤60 دقيقة) | **حارس الانتقال:** لا يعمل إلا إذا `github.repository == 'almorabbi/almorabbi'` و`vars.CUTOVER_DONE == 'true'` (مضبوط — مُقاس 2026-11-08)؛ تخطّيه يتخطّى image/deploy/alert. ثم `ops/tools/deploy_gate.py`: ينتظر نجاح `Backend tests` لنفس الـSHA عبر API (يفشل مغلقًا) |
| `image` | GitHub-hosted (≤45) | يبني ويفحص (`candidate_smoke.py` + `check_kb_integrity`) داخل الصورة نفسها ثم يدفع `:<sha>` و`:main` إلى GHCR |
| `deploy` | self-hosted `[self-hosted, production]` على الـVPS (≤90) | يسحب الصورة بالـdigest (الحزمة قد تكون خاصة: `docker login` بتوكن المهمة `packages: read` داخل `DOCKER_CONFIG` مؤقت يُحذف عند الخروج)؛ `git fetch && reset --hard <sha>` للـbinds؛ فحص `CLOUD_BUDGET_ENFORCE`؛ `check_served_assets.py` (يوقف النشر لو الفهرس يشير لميديا غائبة/مشتركة)؛ نسخة احتياطية للبيانات؛ جعل الـvolumes قابلة للكتابة لـuid 10001؛ `up -d --no-build --force-recreate backend`؛ فحص `/health` و`/privacy-policy` و`/api/app-config`؛ **تراجع تلقائي** للصورة السابقة السليمة؛ تقليم الصور؛ ذيل اللوج |
| `alert` | الـVPS | رسالة تلجرام عند فشل/إلغاء أي مرحلة قبله |

تعديل `ops/scripts/**` يصل الكرونات بـ`git reset` فقط؛ تعديل `backend/**` يحتاج الصورة كاملة. تنظيف: `vps_cleanup`-النمط يدوي. تطبيق الموبايل **لا** يُنشر آليًا: `mobile-e2e.yml` بوابة ثم رفع Play (`release-play.yml` أو `scripts/play_upload.py`).

## 5) CI

| الفحص | أين | محتوى |
|---|---|---|
| `Backend tests` | `backend.yml` (3.11) | job `pytest` (بيئة الإنتاج + النماذج + الفهرس؛ يشغّل `scripts/tests/test_release_play_workflow.py` ثم `pytest backend/tests ops/tests/test_golden_ci.py`) + job `KB integrity` (ومعه حرّاس الآيات/الأحاديث/التغطية وحارسا قصص الأنبياء والسيرة) + job `ruff` (القواعد E9/F601/F811/F821 فقط) |
| `Flutter` | `flutter.yml` (3.44.1) | analyze `--fatal-infos --fatal-warnings` + test |
| `Mobile E2E` | `mobile-e2e.yml` | APK release للرأس والأساس + Maestro + بوابة delivery؛ `E2E_BASELINE_REF` متغير GitHub يثبّت خط الأساس على بناء Play المنشور |
| فحص الصورة | `candidate-image.yml` | بناء + smoke + كسر الصورة ثلاثًا ليُثبَت أن البوابة ترفض |
| قفل الاعتماديات | `.github/ci/lock-backend-deps.py` + `constraints-prod.txt` | يعيد توليد `requirements-prod.lock` من حزم الإنتاج الحية؛ **لا تعدّل القفل يدويًا** |
| حراس محلية | `.githooks/` | انظر 03 §8 |

أسرار GitHub (أسماء): `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `PLAY_SERVICE_ACCOUNT_JSON` (لـrelease-play)؛ متغيرات: `E2E_BASELINE_REF` (حاليًا وسم آخر إصدار Play؛ الافتراضي في الملف أول كوميت `ab3d9fbd` = 1.0.75+120) و`CUTOVER_DONE` (يفتح النشر). الصورة: `ghcr.io/almorabbi/almorabbi-backend`.

## 6) الجدولة

انظر `03-interfaces.md` §5 (كرونات الـVPS، حلقة الإشعارات داخل العملية، وكلاء PCC، مؤقّتات GitHub).

## 7) الاعتماديات

- **الباكند:** `backend/requirements.txt` (+`-dev`: pytest، pytest-anyio) والقفل المشفّر `.github/ci/requirements-prod.lock` المشتق من `constraints-prod.txt` (إنتاج: fastapi 0.142.2، starlette 1.7.0، uvicorn 0.54.0، **chromadb 0.6.3**، sentence-transformers 6.0.0، torch 2.13.0+cpu، rank-bm25 0.2.2، firebase_admin 7.7.0، redis 8.1.0، cryptography 50.0.2، openai 3.24.0). غيرها: pydantic 2، jsonschema، pyyaml، httpx، requests، onnxruntime، transformers 5.16.1، huggingface_hub، pdfplumber، google-auth. ⚠️ `chromadb>=0.5,<1` محجوز عمدًا؛ FastAPI محليًا 0.136 مقابل 0.142 في CI/الإنتاج (`app.routes` متعشّشة في الأحدث ⇒ اختبار قد يعدّي فارغًا).
- **الموبايل:** `mobile/pubspec.yaml` (Flutter 3.44.1, Dart ^3.12): flutter_riverpod, http, flutter_secure_storage, shared_preferences, firebase_core/analytics/crashlytics/messaging, google_sign_in 7, in_app_purchase(+android), just_audio, audioplayers, record, video_player, flame, lottie, flutter_svg, flutter_local_notifications+timezone, app_links, play_install_referrer, share_plus, screenshot, qr_flutter, wakelock_plus, file_picker, package_info_plus, flutter_markdown_plus.
- **Remotion:** `remotion-reels/package.json`.
- **أدوات خارجية في الخط:** NotebookLM CLI (`notebooklm_env/` غير متعقَّب)، Maestro، Tesseract/pdf2image، ffmpeg، Kaggle CLI.

## 8) متغيرات البيئة (أسماء — مقاسة بالمسح الآلي)

طريقة القياس: مسح `os.environ.get/getenv/environ[...]` في `backend/ ops/ scripts/ mobile/tool remotion-reels/scripts .github e2e` (بلا الاختبارات) + `${VAR}` في سكربتات sh/yml لأسماء بادئاتها معروفة. `.env.example` يغطي جزءًا منها فقط (≈42 اسمًا) — الباقي إعدادات مضبوطة افتراضيًا أو خاصة بأدوات. الأسرار (عمود «سرّ؟») بلا أي قيمة.

**الأمان والهوية والبوابات**

| الاسم | الافتراضي في الكود | سرّ؟ | أين يُقرأ |
|---|---|---|---|
| `AGREEMENT_REQUIRED` | `""` |  | `child_budget.py` |
| `AI_DAILY_LIMIT` | `"20"` |  | `rate_limit.py` |
| `CHILD_MODE_SECRET` |  | نعم | `child_token.py` |
| `CHILD_SURFACE_ENABLED` | `"true"` |  | `child_budget.py` |
| `CHILD_WEB_TOKEN_TTL_SECONDS` | `"72000"` |  | `child_token.py` |
| `CLOUDFLARE_EDGE_IPS` | `DEFAULT_CLOUDFLARE` |  | `client_ip.py` |
| `COACH_TIP_ENABLED` | `"false"` |  | `coach_service.py`, `debug_coach.py` |
| `CORS_ORIGINS` | `"http://localhost:3000,http://127.0.0.1:` |  | `main.py` |
| `DONATIONS_FX_USD_JSON` | `""` |  | `donations.py` |
| `DONATIONS_PLAY_FEE` | `DEFAULT_PLAY_FEE` |  | `donations.py` |
| `DONATION_PRODUCT_IDS` | `""` |  | `donations.py` |
| `FEEDBACK_ADMIN_KEY` |  | نعم | `feedback.py` |
| `FEEDBACK_TELEGRAM_BOT_TOKEN` |  | نعم | `feedback.py` |
| `FEEDBACK_TELEGRAM_CHAT_ID` | `""` |  | `feedback.py` |
| `FEEDBACK_TELEGRAM_WEBHOOK_SECRET` |  | نعم | `feedback.py` |
| `IDENTITY_CROSS_DEVICE` | `""` |  | `identity.py` (+`sync.py` عبر `cross_device_enabled()`؛ يُفعَّل مع `SESSION_MINT_ENFORCE`) |
| `MILESTONES_MIN_BUILD` | `""` |  | `milestone_push.py` |
| `LATEST_BUILD_NUMBER` | `"0"` |  | `health.py` (بطاقة «نسخة جديدة متاحة» الاختيارية؛ 0 = لا شيء) |
| `MINIMUM_BUILD_NUMBER` | `"0"` |  | `health.py`, `device_proof.py` |
| `OPS_METRICS_TOKEN` |  | نعم | `stats.py` |
| `PLAY_PACKAGE_NAME` | `""` |  | `donations.py` |
| `PLAY_SERVICE_ACCOUNT` | `""` |  | `donations.py`, `play_listing_upload.py`, `play_reviews.py` +1 |
| `PLAY_SERVICE_ACCOUNT_JSON` |  | نعم | `release-play.yml` |
| `PROGRAMS_AS_OF_ENABLED` | `""` |  | `programs_common.py` |
| `RATE_LIMIT_FEEDBACK_PER_MINUTE` | `"5"` |  | `rate_limit.py` |
| `RATE_LIMIT_GENERAL_PER_MINUTE` | `"120"` |  | `rate_limit.py` |
| `RATE_LIMIT_PER_MINUTE` | `"30"` |  | `rate_limit.py` |
| `RATE_LIMIT_SESSION_PER_MINUTE` | `"30"` |  | `rate_limit.py` |
| `RATE_LIMIT_SUPPORT_VERIFY_PER_MINUTE` | `"5"` |  | `rate_limit.py` |
| `REPORT_PUBLIC_KEY_PEM` |  | نعم | `runtime_readiness_report.py` |
| `SESSION_MINT_ENFORCE` | `""` |  | `chat.py`, `device_twins.py`, `runtime_readiness_report.py` (قرار التفعيل: `bare_mint_readiness.py`) |
| `STORE_URL` | `"https://play.google.com/store/apps/deta` |  | `health.py` |
| `STORY_AUTH_ENFORCE` | `""` |  | `auth.py` |
| `STORY_MOTION_MODE` | `"ab"` |  | `health.py` |
| `TG_ADMIN_KEY` |  | نعم | `main.py` |
| `TG_OPS_METRICS_TOKEN` |  | نعم | `weekly_dashboard.py` |
| `TOKEN_TTL_DAYS` | `"180"` |  | `init_db.py` |
| `TRUSTED_PROXY_IPS` | `DEFAULT_TRUSTED` |  | `client_ip.py` |
| `TWIN_FOLD_BORN_BEFORE` | `""` |  | `device_twins.py` |

**أخرى**

| الاسم | الافتراضي في الكود | سرّ؟ | أين يُقرأ |
|---|---|---|---|
| `ANDROID_HOME` |  |  | `mobile-e2e.yml` |
| `ANDROID_KEYSTORE_BASE64` |  |  | `release-play.yml` |
| `ANDROID_KEYSTORE_PASSWORD` |  | نعم | `release-play.yml` |
| `ANDROID_KEY_ALIAS` |  |  | `release-play.yml` |
| `ANDROID_KEY_PASSWORD` |  | نعم | `release-play.yml` |
| `ANDROID_SDK_ROOT` | `${ANDROID_HOME:?set ANDROID_HOME or ANDR` |  | `install_system_image.sh` |
| `BASELINE_INDEX` |  |  | `chroma-1x-runtime.yml` |
| `BASELINE_MARKED` |  |  | `rehearsal.sh` |
| `CHROMA_SEED_DIR` | `str(CHROMA_PERSIST_DIR.parent / "chroma_` |  | `retrieval.py` |
| `COMPOSE` |  |  | `migrate_schema_v27.sh` |
| `DIGEST` |  |  | `action.yml` |
| `ENV_FILE` | `.env` |  | `min_build.sh` |
| `EVENT` |  |  | `mobile-e2e.yml` |
| `FILES` |  |  | `mobile-e2e.yml` |
| `FORCE` | `0` |  | `min_build.sh` |
| `GHCR_TOKEN` |  | نعم | `mobile-e2e.yml` |
| `HOME` | مجلد المستخدم (`expanduser`) |  | `gen_podcasts_cron.py` |
| `HORIZON_STRIP_ENABLED` | `"1"` |  | `health.py` |
| `IMAGE` |  |  | `action.yml` |
| `MAESTRO_SHA256` |  |  | `mobile-e2e.yml` |
| `MAESTRO_VERSION` |  |  | `mobile-e2e.yml` |
| `NBLM_BIN` | `./notebooklm_env/bin/notebooklm` |  | `nblm_session.sh` |
| `NBLM_KEEP_BACKUPS` | `5` |  | `nblm_session.sh` |
| `NBLM_READ_TIMEOUT` | `90` |  | `nblm_session.sh` |
| `NBLM_SLEEP_SCALE` | `1` |  | `nblm_session.sh` |
| `NBLM_VALIDATED_THIS_RUN` |  |  | `nblm_session.sh` |
| `NEEDS_JSON` |  |  | `mobile-e2e.yml` |
| `NOOR_HEADER_ENABLED` | `"1"` |  | `health.py` |
| `NOTEBOOK_MAIN` |  |  | `nblm_session.sh` |
| `PROOF_DAYS` | `7` |  | `min_build.sh` |
| `PROOF_MIN` | `20` |  | `min_build.sh` |
| `REAL_EVAL_SET_PATH` | `"/app/data/eval/real_set.jsonl",` |  | `build_real_eval_set.py` |
| `REPO` |  |  | `candidate-image.yml` |
| `REPORT_DIR` |  |  | `runtime-readiness.yml` |
| `SESSIONS_DB` | `str(_DB.parent / "sessions.db"` |  | `weekly_funnel_report.py` |
| `SKIP_MOBILE_CHECKS` | `0` |  | `pre-push` |
| `TG_RERANKER_V2_DIR` | `str(Path(__file__` |  | `reranker.py` |
| `TMPDIR` | `"/tmp"` |  | `eval_ollama_compare.py` |
| `TTS_ENGINE` | `"gemini"` |  | `gen_story_narration.py` |

**LLM / نماذج**

| الاسم | الافتراضي في الكود | سرّ؟ | أين يُقرأ |
|---|---|---|---|
| `ANSWER_CACHE_DB` | `str(Path(__file__` |  | `answer_cache.py`, `eval_answers.py`, `eval_ollama_models.py` |
| `ANSWER_CACHE_ENABLED` | `"false"` |  | `answer_cache.py`, `eval_answers.py` |
| `ANSWER_CACHE_MIN_SIM` | `"0.92"` |  | `answer_cache.py` |
| `ANSWER_CACHE_TTL_DAYS` | `"45"` |  | `answer_cache.py` |
| `AUX_CALLER_WORKERS` | `"8"` |  | `assistant.py` |
| `AUX_LLM_TIMEOUT_S` | `"8"` |  | `ai_gateway.py` |
| `AUX_WAIT_S` | `"20"` |  | `assistant.py` |
| `AZURE_DEEPSEEK_API_KEY` |  | نعم | `llm_config.py` |
| `AZURE_DEEPSEEK_API_VERSION` | `os.environ.get("AZURE_OPENAI_API_VERSION` |  | `llm_config.py` |
| `AZURE_DEEPSEEK_ENDPOINT` | `os.environ.get("AZURE_OPENAI_ENDPOINT", ` |  | `llm_config.py` |
| `AZURE_DEEPSEEK_MODEL` | `os.environ.get("AZURE_OPENAI_DEPLOYMENT"` |  | `llm_config.py` |
| `AZURE_OPENAI_API_KEY` |  | نعم | `build_golden_set.py`, `eval_answers.py`, `generate_dataset_v2.py` |
| `AZURE_OPENAI_API_VERSION` | `"2024-12-01-preview"` |  | `build_golden_set.py`, `eval_answers.py`, `generate_dataset_v2.py` |
| `AZURE_OPENAI_DEPLOYMENT` | `"DeepSeek-V4-Flash"` |  | `build_golden_set.py`, `eval_answers.py`, `generate_dataset_v2.py` |
| `AZURE_OPENAI_ENDPOINT` |  |  | `build_golden_set.py`, `eval_answers.py`, `generate_dataset_v2.py` |
| `CHILD_MEMORY_EXTRACT_TIMEOUT_S` | `"20"` |  | `child_memory.py` |
| `CHILD_MEMORY_MIN_BUILD` | `""` |  | `child_memory.py` |
| `CHILD_MEMORY_MONTHLY_TOKEN_CAP` | `"3000000"` |  | `child_memory.py` |
| `CLASSIFIER_TIMEOUT_S` | `str(AUX_TIMEOUT_S` |  | `domain_classifier.py` |
| `CLOUD_BUDGET_ANCHOR_PATH` | `""` |  | `llm_config.py` |
| `CLOUD_BUDGET_ENFORCE` |  |  | `llm_config.py`, `runtime_readiness_report.py` |
| `CLOUD_TIER_ENABLED` | `"false"` |  | `llm_config.py` |
| `CLOUD_TIER_TIMEOUT` | `"60"` |  | `llm_config.py` |
| `COST_BREAKDOWN_USD` | `""` |  | `donations.py` |
| `COST_MONTHLY_USD` | `""` |  | `donations.py` |
| `CUDA_VISIBLE_DEVICES` |  |  | `build_notebook.py`, `push_kaggle_v6_dpo_kernel.py`, `push_kaggle_v6_kernel.py` |
| `DEEPSEEK_API_KEY` |  | نعم | `llm_config.py`, `eval_answers.py`, `generate_dataset_v2.py` +1 |
| `DEEPSEEK_BASE_URL` | `"https://api.deepseek.com"` |  | `llm_config.py`, `generate_dataset_v2.py`, `ingest_pdf.py` +1 |
| `DEEPSEEK_BILLING_PROFILE_ALIASES` | `""` |  | `llm_config.py` |
| `DEEPSEEK_FALLBACK_ENABLED` | `"false"` |  | `llm_config.py` |
| `DEEPSEEK_FALLBACK_MONTHLY_TOKEN_CAP` | `"10000000"` |  | `llm_config.py` |
| `DEEPSEEK_MODEL` | `"deepseek-flash"` |  | `llm_config.py`, `generate_dataset_v2.py`, `ingest_pdf.py` |
| `DEEPSEEK_MODEL_FALLBACK` | `"deepseek-flash"` |  | `llm_config.py` |
| `DEEPSEEK_PRIMARY_MONTHLY_TOKEN_CAP` |  |  | `llm_config.py` |
| `DEEPSEEK_PRIMARY_MONTHLY_USD_CAP` |  |  | `llm_config.py` |
| `EVAL_OLLAMA_URL` | عنوان Ollama على tg-home (مكتوب في الشيفرة) |  | `eval_ollama_models.py` |
| `FAL_KEY` |  | نعم | `fal_common.py` |
| `FC_MODEL` | `"qwen2.5:3b"` |  | `gen_flashcards_quizzes.py` |
| `FIQH_INTENT_MODE` | `"off"` |  | `fiqh_guard.py`, `fiqh_intent.py` |
| `FIQH_LOG_RETENTION_DAYS` | `"90"` |  | `fiqh_guard.py` |
| `GEMINI_API_KEY` |  | نعم | `eval_ollama_compare.py`, `generate_veo_assets.py` |
| `GOLDEN_REVISION` | `"unknown"` |  | `golden_ci.py` |
| `GOOGLE_API_KEY` |  | نعم | `generate_veo_assets.py` |
| `HF_HUB_DISABLE_XET` |  |  | `push_kaggle_v6_dpo_kernel.py` |
| `HF_TOKEN` |  | نعم | `build_notebook.py`, `finetune_commandr_kaggle.py`, `push_kaggle_v6_dpo_kernel.py` +2 |
| `HUGGING_FACE_HUB_TOKEN` |  | نعم | `push_kaggle_v6_dpo_kernel.py` |
| `JUDGE_DEEPSEEK_MODEL` | `"deepseek-flash"` |  | `eval_answers.py` |
| `JUDGE_GEMINI_MODEL` | `"gemini-2.5-flash"` |  | `eval_ollama_compare.py` |
| `JUDGE_OLLAMA_MODEL` | `"mistral-large-3:675b"` |  | `eval_answers.py` |
| `LLM_AUX_WORKERS` | `"6"` |  | `ai_gateway.py` |
| `LLM_DEADLINE_SLACK_S` | `"4"` |  | `ai_gateway.py` |
| `LLM_FALLBACK_FIRST_TOKEN_S` | `"150"` |  | `assistant.py` |
| `LLM_FIRST_TOKEN_TIMEOUT_S` | `"75"` |  | `assistant.py` |
| `LLM_GENERATE_DEADLINE_S` | `"150"` |  | `ai_gateway.py` |
| `LLM_LOCAL_WORKERS` | `"4"` |  | `ai_gateway.py` |
| `LLM_MIN_ATTEMPT_S` | `"10"` |  | `ai_gateway.py` |
| `LLM_PRIMARY_FIRST_TOKEN_S` | `"30"` |  | `ai_gateway.py` |
| `LLM_PRIMARY_PREFLIGHT_RETRIES` | `"2"` |  | `ai_gateway.py` |
| `LLM_PRIMARY_PROVIDER` | `"ollama"` |  | `llm_config.py` |
| `LLM_PRIMARY_STALL_S` | `"60"` |  | `ai_gateway.py` |
| `LLM_PRIMARY_TOTAL_S` | `"300"` |  | `ai_gateway.py` |
| `LLM_PRIMARY_WORKERS` | `"6"` |  | `ai_gateway.py` |
| `LLM_STREAM_DEADLINE_S` | `"300"` |  | `assistant.py` |
| `LLM_STREAM_STALL_S` | `"60"` |  | `assistant.py` |
| `LLM_STREAM_WORKERS` | `"8"` |  | `assistant.py` |
| `OLLAMA_API_KEY` |  | نعم | `check_quoted_texts.py`, `deepen_paths.py`, `eval_answers.py` +5 |
| `OLLAMA_BASE_URL` | `"http://localhost:11434"` |  | `llm_config.py`, `main.py`, `domain_classifier.py` +3 |
| `OLLAMA_FALLBACK_MODEL` | `"gemma4:e4b"` |  | `llm_config.py` |
| `OLLAMA_FAST_MODEL` | `"qwen2.5:3b"` |  | `domain_classifier.py`, `fiqh_intent.py` |
| `OLLAMA_HOME_SERVER_URL` | عنوان Ollama على tg-home (مكتوب في الشيفرة) |  | `llm_config.py` |
| `OLLAMA_LOCAL_BASE_URL` | `DEFAULT_HOME_OLLAMA_URL` |  | `llm_config.py`, `main.py`, `domain_classifier.py` +5 |
| `OLLAMA_LOCAL_FALLBACK_MODEL` | `"gemma4:e4b"` |  | `llm_config.py` |
| `OLLAMA_LOCAL_FAST_MODEL` | `"qwen2.5:3b"` |  | `llm_config.py`, `main.py`, `domain_classifier.py` +3 |
| `OLLAMA_MAX_RETRIES` | `"3"` |  | `llm_config.py` |
| `OLLAMA_MODEL` | `"tg-tutor:v4"` |  | `warm_answer_cache.py` |
| `OLLAMA_PRIMARY_MODEL` | `"qwen2.5:3b"` |  | `llm_config.py` |
| `OLLAMA_TEMPERATURE` | `"0.3"` |  | `llm_config.py` |
| `OLLAMA_TIMEOUT` | `"120"` |  | `llm_config.py` |
| `PROMPT_VARIANT_LOCAL` | `"compact"` |  | `llm_service.py` |
| `PYTORCH_CUDA_ALLOC_CONF` |  |  | `push_kaggle_v6_dpo_kernel.py` |
| `RERANKER_MODEL` | `str(_FINETUNED_RERANKER_DIR` |  | `reranker.py` |
| `RERANK_BUDGET_S` | `"6.0"` |  | `reranker.py` |
| `RERANK_ENABLED` | `"true"` |  | `reranker.py` |
| `RERANK_MAX_STRIKES` | `"3"` |  | `reranker.py` |
| `RERANK_MIN_SCORE` | `"-6.0"` |  | `reranker.py` |
| `RETRIEVAL_DOMAIN_FUSION` | `"global"` |  | `retrieval.py` |
| `TOKENIZERS_PARALLELISM` |  |  | `push_kaggle_v6_dpo_kernel.py` |

**التشغيل والمسارات**

| الاسم | الافتراضي في الكود | سرّ؟ | أين يُقرأ |
|---|---|---|---|
| `API_BASE_URL` | `"https://tg-api.alsaba.cloud"` |  | `social_media_autoposter.py`, `publish_reels_to_buffer.py` |
| `BACKUP` |  |  | `migrate_schema_v27.sh` |
| `BACKUP_ROOT` | `/root/tg-backups` |  | `backup_user_data.sh` |
| `BAHOUTH_CACHE_ENABLED` | `"true"` |  | `quranic_linguistics_service.py` |
| `BAHOUTH_CACHE_TTL_DAYS` | `"30"` |  | `quranic_linguistics_service.py` |
| `BAHOUTH_MCP_URL` | `"https://bahouth.tafsir.net/mcp"` |  | `quranic_linguistics_service.py` |
| `BAHOUTH_TIMEOUT` | `"15"` |  | `quranic_linguistics_service.py` |
| `CONTAINER` | `<لا توجد>` |  | `deploy.yml` |
| `CONVERSATIONS_DB` | `str(_DEFAULT` |  | `init_db.py`, `v16_habit_templates.py`, `v20_feedback_replies.py` +15 |
| `DATA_DIR` | `"/kaggle/input/tg-qa-dataset"` |  | `build_notebook.py`, `finetune_commandr_kaggle.py` |
| `DB_PATH` |  |  | `migrate_schema_v27.sh`, `min_build.sh` |
| `FIREBASE_CREDENTIALS` |  | نعم | `push_sender.py` |
| `FIREBASE_CREDENTIALS_PATH` | `""` |  | `push_sender.py` |
| `PROJECT_ROOT` | `Path(__file__` |  | `main.py`, `privacy.py`, `candidate_smoke.py` |
| `REDIS_URL` | `""` |  | `rate_limit.py` |
| `RETENTION_DAYS` | `14` |  | `backup_user_data.sh` |
| `SKIP_WARMUP` |  |  | `main.py` |
| `SSE_KEEPALIVE_S` | `"15"` |  | `assistant.py` |
| `TAFSIR_CACHE_ENABLED` | `"true"` |  | `tafsir_service.py` (تضبطه `anbiya_sources.py`/`sira_sources.py` على false لجلب طازج) |
| `TAFSIR_CACHE_TTL_DAYS` | `"30"` |  | `tafsir_service.py` |
| `TAFSIR_MCP_URL` | `"https://mcp.tafsir.net/mcp"` |  | `tafsir_service.py` |
| `TAFSIR_TIMEOUT` | `"10"` |  | `tafsir_service.py` |

**تلجرام/نشر/محتوى**

| الاسم | الافتراضي في الكود | سرّ؟ | أين يُقرأ |
|---|---|---|---|
| `BUFFER_ACCESS_TOKEN` |  | نعم | `social_media_autoposter.py` |
| `DEEPEN_REVIEW_PATIENCE_S` | `4 * 3600` |  | `deepen_paths.py` |
| `DEEPEN_REVIEW_TIMEOUT_S` | `420` |  | `deepen_paths.py` |
| `FRESH_CACHE` |  |  | `run_review.py` |
| `NOTEBOOKLM_COOLDOWN_HOURS` | `"3"` |  | `trigger_and_download_podcasts.py` |
| `NOTEBOOKLM_HOME` | `~/.notebooklm` |  | `nblm_session.sh` |
| `PODCAST_MAX_DELAY` | `"30.0"` |  | `trigger_and_download_podcasts.py` |
| `PODCAST_MAX_TRIGGER_PER_RUN` | `"0"` |  | `trigger_and_download_podcasts.py` |
| `PODCAST_MIN_DELAY` | `"1.0"` |  | `trigger_and_download_podcasts.py` |
| `TELEGRAM_BOT_TOKEN` |  | نعم | `campaign_report.py`, `launch_weekly_report.py`, `weekly_dashboard.py` +3 |
| `TELEGRAM_CHANNEL_ID` | `""` |  | `social_media_autoposter.py` |
| `TELEGRAM_CHAT_ID` | `""` |  | `campaign_report.py`, `launch_weekly_report.py`, `weekly_dashboard.py` +2 |
| `TG_NOTEBOOKLM_PROFILE` | `"tg-video"` |  | `refresh_source_map.py`, `gen_aqeedah_infographics_batch.py`, `gen_path_videos_cron.py` +2 |

**CI/نشر**

| الاسم | الافتراضي في الكود | سرّ؟ | أين يُقرأ |
|---|---|---|---|
| `E2E_APKS` |  |  | `rehearsal.sh` |
| `E2E_CHILD_NAME` | `E2E-Rehearsal` |  | `rehearsal.sh` |
| `E2E_OUT` |  |  | `mobile-e2e.yml` |
| `E2E_QUESTION` | `E2E test how can I teach my child to be ` |  | `rehearsal.sh` |
| `E2E_SDK_ATTEMPTS` | `3` |  | `install_system_image.sh` |
| `E2E_SDK_BACKOFF` | `15` |  | `install_system_image.sh` |
| `GH_TOKEN` |  | نعم | `deploy_gate.py` |
| `GITHUB_EVENT_NAME` |  |  | `runtime_readiness_report.py` |
| `GITHUB_OUTPUT` |  |  | `action.yml`, `mobile-e2e.yml` |
| `GITHUB_REF` | `f"refs/heads/{BRANCH}"` |  | `deploy_gate.py`, `runtime_readiness_report.py` |
| `GITHUB_REPOSITORY` | `""` |  | `deploy_gate.py` |
| `GITHUB_SHA` |  |  | `runtime_readiness_report.py` |
| `GITHUB_STEP_SUMMARY` |  |  | `mobile-e2e.yml`, `deploy_gate.py` |
| `GITHUB_TOKEN` |  | نعم | `deploy_gate.py` |
| `READINESS_EXPECTED_SHA` | `''` |  | `runtime_readiness_report.py` |
| `READINESS_WORKFLOW_SHA` |  |  | `runtime_readiness_report.py` |
| `RUNNER_TEMP` |  |  | `chroma_recall_capture.py` |
| `TG_API_BASE` | `"https://tg-api.alsaba.cloud"` |  | `weekly_dashboard.py` |
| `TG_DRIFT_GRACE` | `45 * 60` |  | `check_deploy_drift.py` |
| `TG_DRIFT_STATE` | `"/root/.tg_deploy_drift.json"` |  | `check_deploy_drift.py` |
| `TG_REPO` | `"/root/tutor-guardian"` |  | `check_deploy_drift.py` |
| `TG_VPS_HOST` | عنوان الـVPS (مكتوب في الشيفرة) |  | `trigger_and_download_podcasts.py` |
| `TUTOR_VPS_HOST` | عنوان الـVPS (مكتوب في الشيفرة) |  | `publish_reels_to_buffer.py` |

### أسرار/مفاتيح تعيش في ملفات (ليس متغيرات)

| الملف | ماذا | ملاحظة |
|---|---|---|
| `backend/secrets/firebase-adminsdk.json` | Firebase Admin (FCM) | bind read-only، 600، خارج git |
| `backend/secrets/play_service_account.json` | حساب خدمة Play لتحقق المشتريات (مقيَّد: View financial data + Manage orders) | لا تعيد استعمال حساب رفع الإصدارات |
| `mobile/android/app/key.properties`, `almorabbi-upload.jks` | توقيع الرفع | خارج git؛ تُنسخ يدويًا لأي شجرة معزولة قبل `flutter build appbundle` ثم تُمسح؛ تحقق `jarsigner -verify -certs` ⇒ `CN = Alsaba Tutor Guardian` |
| `scripts/play_service_account.json` | حساب خدمة رفع Play | خارج git |
| `.env`, `.env.openrouter`, `.env.elevenlabs` (جذر الشجرة الرئيسية) | مفاتيح محلية | غير متعقَّبة |

## 9) قوائم تحقق تشغيلية

- **قبل أي نشر:** التحقق بالأثر: `docker ps` (healthy) + `/health` + سؤال حقيقي للمحادثة يرجع إجابة (لا exit 0).
- **بعد تعديل وحدات المعرفة:** `normalize_units.py` ← `build_vector_db.py` ← `./check.sh --full`.
- **حدّ التحديث الإجباري:** `ops/scripts/min_build.sh current|census|plan|apply`؛ الحد ≤ آخر بناء متاح 100% على Play.
- **تغيير تشغيلي:** قيد مؤرَّخ في سجل العمليات لدى المشغّل (خارج هذا الريبو).
- **الميديا:** تصل الإنتاج بـrsync فقط؛ قبل نشر `lesson_index.json` تأكد من وجود الملفات على الـVPS.
- **Chroma:** لا ترفع المكتبة لـ1.x ضمن تحديث روتيني (هجرة صيغة فهرس الإنتاج 0.6).

