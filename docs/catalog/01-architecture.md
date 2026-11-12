# 01 — البنية المعمارية

## 1) الصورة الكبرى

«المربّي الذكي» = **تطبيق Flutter للأهل (Android)** + **باكند FastAPI/RAG واحد** + **قاعدة معرفة JSON** + **خطوط محتوى وتشغيل خارج الإنتاج**. الباكند هو المنتج (README: «الـbackend/API هو المنتج»)، والتطبيق هو العميل النهائي، و`frontend/` عميل اختبار + قوالب هبوط.

```
 هاتف الأب/الطفل (Flutter، حزمة com.alsaba.almorabbi)
   │ HTTPS  (Bearer / Child-Bearer · SSE للبث)
   ▼
 Cloudflare ── tunnel tg_cloudflared ──► tg_backend:8000   (tg-api.alsaba.cloud : API + هبوط + /go /l /p)
 alsaba.cloud/seo  و /methodology ── analytics_nginx ──► tg_backend:8000   (وكيل مشروع آخر على نفس الـVPS)
                                                │
   ┌────────────────────────────────────────────┼───────────────────────────────────────────────┐
   │ حاوية tg_backend (python:3.11، uid 10001، 2 CPU/4GB) — Uvicorn + FastAPI                    │
   │  middleware: ClientIP → RateLimit → Auth → CORS                                              │
   │  29 router · حلقة إشعارات محلية-الساعة (كل 15 دقيقة)                                        │
   │  ┌ ChromaDB (e5-small) + BM25 + Cross-Encoder ┐  ┌ SQLite: conversations.db / sessions.db ┐  │
   │  │ knowledge_base/chroma_db (volume tg_chroma) │  │ /app/ops (volume tg_sessions)          │  │
   │  └─────────────────────────────────────────────┘  └─────────────────────────────────────────┘  │
   └──────┬──────────────┬───────────────────┬──────────────────┬───────────────────────────────┘
          │              │                   │                  │
     DeepSeek API    Ollama على tg-home   Firebase Admin     Redis tg_redis
     (الأساسي)       (Tailscale؛ احتياطي) (FCM — مفتاح      (حصة AI اليومية
                                           ملف 600 bind)     وحدّ المعدل)
          └─ Tafsir MCP / Bahouth MCP (HTTP)   └─ Telegram Bot API (ملاحظات/تقارير)   └─ Google Play Developer API (تحقق المشتريات)
```

## 2) المكوّنات وأين تعيش

| المكوّن | الشيفرة | أين يعمل | ملاحظات |
|---|---|---|---|
| **الباكند** | `backend/app/` | حاوية `tg_backend` على الـVPS | الصورة مخبوزة؛ النشر = سحب صورة من GHCR |
| **مخزن المتجهات** | `retrieval.py` | volume `tg_chroma` | Chroma **<1** محجوز عمدًا (فهرس الإنتاج بصيغة 0.6)؛ فهرس مخبوز في الصورة (`chroma_seed`) وينسخه الإقلاع |
| **SQLite** | `db/init_db.py` + خدمات | volume `tg_sessions` على `/app/ops` | `conversations.db` (المنتج: 51 جدولًا من 54، SCHEMA_VERSION 37) و`sessions.db` (تيليمتري وكاشات) |
| **Redis** | `rate_limit.py` | حاوية `tg_redis` (appendonly) | حصة AI اليومية؛ بدونه تسقط للذاكرة وتتصفّر عند كل نشر |
| **الاستدلال** | `ai_gateway.py` | DeepSeek (سحابة) ← Ollama (tg-home) | تفاصيل 06 |
| **تطبيق الموبايل** | `mobile/` | هاتف المستخدم | Riverpod + Navigator؛ Firebase (Analytics/Crashlytics/Messaging) |
| **صفحات الويب العامة** | `routers/web.py` وأخواته | نفس الحاوية | هبوط، SEO، منهجية، خصوصية |
| **صفحة المراهق** | `backend/static/child_mode/` | نفس الحاوية | QR |
| **تلجرام** | `feedback.py`, `ops/scripts/*report*` | الحاوية + كرون | بوت ملاحظات (webhook) + تقارير |
| **خطوط المحتوى** | `scripts/`, `ops/tools/`, `remotion-reels/`, `mobile/tool/` | اللابتوب / tg-home (لا الإنتاج) | NotebookLM، Ollama Cloud، ElevenLabs، Gemini TTS، fal.ai/Recraft، Veo، Remotion |
| **وكلاء النشر المحليون** | مستودع تشغيل منفصل لدى المشغّل | اللابتوب | نشر/ريلز/بودكاست (بعضها ما زال يعمل من نسخة الأرشيف المحلية) |
| **CI/CD** | `.github/workflows/` | GitHub-hosted + runner ذاتي على الـVPS | تفاصيل 07 |

## 3) تدفّق السؤال (الأهم)

1. **التطبيق** ينشئ/يجدّد جلسة (`POST /api/chat/sessions` مع `device_id` وإثبات الجهاز عند الحاجة) ثم يفتح `POST /api/assistant/stream` بجسم `UserMessage` = `{age_group, domain?, behavior_type, severity, message_text, session_id?, child_id?, conversation_history[]}`.
2. **Middleware:** ClientIP يحدد العميل → RateLimit (نطاق ai + حصة يومية) → Auth يربط `device_id/session_id`.
3. **`assistant.py` — الحواجز قبل أي نموذج (بالترتيب):** دعم القلق الذاتي ← حظر النوايا ← كلمات الطوارئ/الشدة ← إساءة/اختصارات حوارية ← حارس العقاب البدني ← حارس الفتوى (بعد الطوارئ — إصلاح C1) ← مخارج جاهزة تُرسل كإطار `done` واحد بلا `token`.
4. **التفاهم مع الذاكرة:** إخفاء أسماء الأطفال (`privacy.redact_family`) وجلب حقائق الطفل (`child_memory`) إن مُكِّنت وسُمح بها.
5. **التصنيف:** `domain_classifier` (كلمات سريعة ← كاش ← LLM مساعد) + `query_rewriter` للعامّي.
6. **الاسترجاع:** `retrieve_hybrid`: ساق المتجهات (Chroma + e5) وساق BM25 → RRF → Cross-Encoder → فلترة العمر/المجال → وحدات + (آية → تفسير موثّق).
7. **الكاش:** إن كان أول سؤال في الجلسة وفُعِّل `ANSWER_CACHE_ENABLED` يُقدَّم الجواب المخزّن (`provider=answer_cache` في `llm_calls`).
8. **توجيه الجودة:** `tier_router.choose_tier` (cloud_quality أو local_fast).
9. **التوليد:** `llm_service.build_full_prompt` ثم `AIGateway.stream` (مسارات منفصلة للمزوّد الأساسي والمحلي والمساعد؛ آجال مطلقة؛ سقوط إلى Ollama فالصمام السحابي).
10. **الحواجز بعد التوليد:** `guardrails.apply_guardrails` (شدّة/مجال/إحالة طبية/نص بديل) + تنظيف مخرجات النموذج + استشهادات المصادر.
11. **الإطارات:** `event: token {delta}` … `event: done {reply_text, domain, severity, needs_human_review, escalation_target, mode, session_id}`؛ بث حيّ مع keep-alives (`SSE_KEEPALIVE_S`) وإلغاء عند الإيقاف.
12. **التسجيل:** `conversation_store` (رسائل)، `session_logger` (استعمال بلا نص)، `retrieval_log` (مُخفى الأسماء)، `llm_calls` (تيليمتري LLM).

## 4) تدفقات أخرى

| التدفق | المسار |
|---|---|
| **سطح الطفل** | الأب يدخل «وضع الطفل» (PIN) ← باب التسليم ← `POST /value-tracking/child-sessions` يُصدر Child-Bearer ويفتح جلسة شاشة ← نبض كل بضع ثوانٍ يُحاسَب بالخادم ← بوابة العمر والاتفاقية تُفرَض في `child_budget`/`auth` ← مهمة/رخصة/عادات ← المساء: تأكيد الأب ← ملخّص 21:00 |
| **المتابعات والذاكرة** | جواب → استخراج حقيقة (LLM مساعد، سقف 3M توكن/شهر) → متابعة مجدولة → إشعار 19:00 بتوقيت الأسرة → رد الأب → حقيقة جديدة |
| **الإشعارات** | (1) كرون 17:00 UTC داخل الحاوية (إعادة تفاعل). (2) حلقة `main.py` كل 15 دقيقة للمحلية-الساعة. (3) `POST /api/admin/send-push` يدوي. كلها عبر `push_sender` (Firebase Admin) |
| **حلقة الملاحظات** | التطبيق → `POST /api/feedback/app` → تلجرام (+صوت) → ردّ المسؤول → webhook → `feedback_replies` + FCM → التطبيق يستطلع `GET /feedback/replies` |
| **الهوية والاستعادة** | أول تشغيل: `POST /api/chat/sessions` (`mint_kind=new`) ← `POST /api/chat/restore-key` يُخزَّن «<deviceId> tgr_…» في SharedPreferences (يدخل نسخ أندرويد) ← بعد إعادة تثبيت: سكّ بترويسة `X-Device-Restore` (`mint_kind=restore`) فتعود العائلة؛ ربط Google اختياري ولا يؤكَّد من جلسة عارية |
| **الإسناد** | رابط حملة `/go?ref=…` → سجل نقرة → Google Play referrer → التطبيق يقرأ `play_install_referrer` → `POST /referral/claim` |
| **المحتوى** | وحدات `knowledge_base/units` ← فهرسة Chroma (`build_vector_db.py`/خبز الصورة) ← منهج `curriculum/` ← وسائط `docs/` (rsync) ← `lesson_index.json` ← `GET /program/*` |
| **النشر** | PR ← دمج في main بـ`almorabbi/almorabbi` ← `backend.yml` (اختبارات) ← `deploy.yml`: gate ← image (GHCR) ← deploy على الـVPS (فحص media، نسخ احتياطي، recreate، فحص صحة، تراجع) ← alert |
| **الإصدار** | `mobile/pubspec.yaml` (version+build) ← `mobile-e2e.yml` (بوابة) ← AAB موقَّع محليًا أو `release-play.yml` ← Play (track + rollout) |

## 5) الخدمات الخارجية

| الخدمة | الاستعمال | أين |
|---|---|---|
| DeepSeek API | المزوّد الأساسي لتوليد الإجابات (إنتاج) + مساعدون (تصنيف/إعادة صياغة/استخراج) | `ai_gateway.py` · `DEEPSEEK_*` |
| Ollama (tg-home عبر Tailscale افتراضيًا) | احتياطي محلي + إحماء إن كان الأساسي | `llm_config.py` · `OLLAMA_*` |
| Ollama Cloud (`ollama.com/v1`) | شغل دفعي: ترجمة/مراجعة/حكم فجوات (ليس مسار المستخدم) | `ops/tools/*` · `OLLAMA_API_KEY` |
| Azure OpenAI (DeepSeek-V4-Flash) | طبقة سحابية اختيارية (مطفأة) | `CLOUD_TIER_ENABLED` · `AZURE_*` |
| Tafsir MCP `mcp.tafsir.net` / Bahouth MCP `bahouth.tafsir.net` | تفسير موثّق وتحليل لغوي قرآني (JSON-RPC over SSE) | `tafsir_service.py` · `quranic_linguistics_service.py` |
| Firebase (FCM/Admin، Analytics، Crashlytics) | إشعارات وقياس وأعطال | `push_sender.py` · `mobile/lib/core/analytics.dart` |
| Google Play (Developer API، Billing، Install Referrer) | رفع الإصدارات، تحقق المشتريات، إسناد التثبيت | `scripts/play_*.py` · `donations.py` · `referral_service.dart` |
| Google Sign-In / tokeninfo | ربط حساب اختياري | `identity.py` · `identity_service.dart` |
| Telegram Bot API | ملاحظات، تقارير، تنبيه نشر، قناة المربّي | `feedback.py` · `ops/scripts` |
| Buffer | جدولة نشر اجتماعي | `social_media_autoposter.py` · `publish_reels_to_buffer.py` |
| NotebookLM | توليد بودكاست/فيديو/إنفوجراف/تقارير الدروس | `scripts/*` · `notebooklm_env` (غير متعقَّب) |
| ElevenLabs / Gemini TTS / edge-tts | سرد القصص والتعليق الصوتي والبودكاست المحلي | `mobile/tool/gen_story_narration.py` · `remotion-reels/scripts/gen_vo.py` · `scripts/gen_tts_podcasts.py` |
| fal.ai (Recraft v3) / Veo | رسوم ومواد بصرية وفيديو | `ops/tools/fal_common.py`, `gen_visuals.py`, `generate_veo_assets.py` |
| Gemini (gemini-2.5-flash) | فحص التعليق الصوتي | `remotion-reels/scripts/check_vo.py` |
| everyayah.com | صوت التلاوة آية-آية | `mobile/lib/features/quran/models/reciters.dart` |
| Kaggle / HuggingFace | ضبط نموذج وتنزيل نماذج التضمين | `ops/kaggle/*` · `Dockerfile` |
| GHCR | سجل صور الباكند | `deploy.yml` |
| GA4 | قياس القمع والحملات | `scripts/ga4_cohort_report.py` |
| Cloudflare | نفق + عناوين العملاء | `middleware/client_ip.py` |

## 6) حدود المسؤولية بين المشروعين المتجاورين على الـVPS

`tg_backend` عضو في شبكة `analytics-platform_production_network` (لأن `analytics_nginx` يوكّل `alsaba.cloud/seo` و`/methodology` إليه). نتيجتان: (1) **اسم `redis` العام يحلّ لحاوية analytics** → استعمل `tg_redis` صريحًا؛ (2) إعادة إنشاء ستاك analytics لا تمسّ التطبيق (نفق Cloudflare يصل `tg_backend` مباشرة). المستودعان وCI والـrunner منفصلة.
