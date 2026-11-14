# 02 — الوحدات والملفات (كل ملف متعقَّب في git)

> **مولَّد آليًا** من `git ls-files` ثم مُنسَّق: كل ملف متعقَّب يظهر إمّا في صف خاص به أو داخل صف «مجموعة» (بيانات/ميديا بالآلاف). لا يوجد ملف خارج هذا الجدول — راجع «قاعدة التغطية» في الأسفل.
> وصف الملف = أول docstring/تعليق فيه (قد يكون بالإنجليزية)، وللملفات الجوهرية وصف عربي منسّق يدويًا. عمود «أسطر» للشيفرة والنص فقط.


## 1) الباكند — `backend/app/` (FastAPI + RAG)

حاوية `tg_backend`. نقطة الدخول `backend/app/main.py` (uvicorn `app.main:app`, `PYTHONPATH=/app/backend`).

### backend/app/ — الجذر والإعداد والنواة

| الملف | أسطر | الدور |
|---|---:|---|
| `backend/app/__init__.py` | 0 | علامة حزمة بايثون |
| `backend/app/config/__init__.py` | 0 | علامة حزمة بايثون |
| `backend/app/config/guardrails_loader.py` | 306 | تحميل backend/guardrails/*.yaml (سياسات المجالات + سياسة بوابة سطح الطفل العمرية) — يُوقف الإقلاع إن تعذّر |
| `backend/app/config/llm_config.py` | 284 | إعداد كل شيء متعلق بالـLLM من env: Ollama، DeepSeek (أساسي/احتياطي)، Azure، الطبقة السحابية، سقوف الميزانية الشهرية، CLOUD_BUDGET_ENFORCE |
| `backend/app/core/__init__.py` | 0 | علامة حزمة بايثون |
| `backend/app/core/circuit_breaker.py` | 58 | قاطع دائرة للفشل المتتالي (يستعمله tier_router للطبقة السحابية) |
| `backend/app/core/contact.py` | 5 | عنوان التواصل الوحيد للأهل (سياسة الخصوصية، /delete-account، أخطاء device-proof) |
| `backend/app/core/eval_traffic.py` | 31 | وسم حركة التقييم كي تُستبعد من المقاييس |
| `backend/app/core/log_safety.py` | 35 | بدائل آمنة للّوج لمعرّفات تعمل كبيانات اعتماد (device_id المرفوض) |
| `backend/app/core/proof.py` | 119 | حرّاس FastAPI للمسارات التي تشترط إثبات الجهاز (request_proven + اعتماديات المسارات المحمية) |
| `backend/app/core/real_traffic.py` | 120 | قاعدة «الحركة الحقيقية فقط» التي تستعملها كل التقارير لاستبعاد تست/تقييم/مشغّل |
| `backend/app/core/service_account.py` | 44 | قراءة JSON حساب خدمة Google بحيث لا يُسقط فشلُها الميزةَ كلها |
| `backend/app/core/taxonomy.py` | 228 | مصدر الحقيقة الوحيد لمفردات قاعدة المعرفة (فئات عمرية، مجالات، شدّة، تدخّل، أنواع مراجع) |
| `backend/app/core/times.py` | 35 | شكل موحّد لكل طابع زمني يعيده الـAPI: ISO8601 UTC بـZ |
| `backend/app/curriculum_loader.py` | 442 | تحميل المنهج (paths/lessons/daily_tips + i18n/en) من knowledge_base/curriculum وفهرس docs/lesson_index.json وفحص وجود الميديا (media_exists) |
| `backend/app/data/quran.json` |  | نص المصحف (6236 آية، ~1.7MB) لفهرس الكلمات→آية في tafsir_service |
| `backend/app/main.py` | 319 | نقطة دخول FastAPI: lifespan (إحماء embedder/Chroma/reranker/Ollama + حلقة الإشعارات المحلية-الساعة)، 4 middleware، تركيب 28 router + /api/admin/send-push + static mounts (/docs /ui /assets /child-mode/web /.well-known) |
| `backend/app/media_naming.py` | 120 | مصدر واحد لتسمية ملفات الميديا (لغة الملف، فيديو المسار) للـAPI والمولّدات |
| `backend/app/middleware/__init__.py` | 0 | علامة حزمة بايثون |
| `backend/app/middleware/auth.py` | 251 | AuthMiddleware: Bearer (جهاز) وChild-Bearer (مقصور على مسارات الطفل)، قوائم المسارات العامة/المحمية/الناعمة، فحص جلسة شاشة الطفل (403 child_budget_exhausted) |
| `backend/app/middleware/client_ip.py` | 172 | ClientIPMiddleware: عنوان العميل الحقيقي خلف Cloudflare/nginx بقائمة وكلاء موثوقين (TRUSTED_PROXY_IPS) |
| `backend/app/middleware/rate_limit.py` | 362 | تحديد المعدل لكل هوية (جهاز/توكن/IP): نطاقات ai/general/feedback/session/support + حصة AI يومية (AI_DAILY_LIMIT) — Redis أو ذاكرة |
| `backend/app/middleware/security_headers.py` | 50 | SecurityHeadersMiddleware: ترويسات أمان أساسية على كل رد (nosniff، X-Frame-Options، Referrer-Policy، Permissions-Policy، HSTS) — لم يكن على tg-api أي ترويسة حتى 2026-11-09 |
| `backend/app/models/__init__.py` | 0 | علامة حزمة بايثون |
| `backend/app/models/api.py` | 133 | نماذج Pydantic لطلبات/ردود الـAPI الأساسية (UserMessage, AssistantReply, ConversationTurn…) |
| `backend/app/models/daily_routine.py` | 234 | نماذج «حِساب اليوم» (أحداث النوم/الرضاعة/الحفاض) |
| `backend/app/models/knowledge.py` | 140 | نموذج وحدة المعرفة المطابق للـJSON schema |
| `backend/app/models/value_tracking.py` | 189 | نماذج «ميزان العادات» (عادات ديناميكية بالعمر + وضع الطفل) |
| `backend/app/quiz_data.py` | 322 | بنك أسئلة الكويز المخدوم من GET /api/program/quiz (مؤصّل في المصادر الخام للمنهج) |
| `backend/app/security/__init__.py` | 1 | Security review contracts; runtime guards remain in their existing modules. |
| `backend/app/security/route_policy.py` | 744 | جدول جرد المسارات الموثّقة كعقد مراجعة واختبار — لا يستهلكه التطبيق وقت التشغيل |

### backend/app/db/ — قاعدة البيانات والترحيلات

| الملف | أسطر | الدور |
|---|---:|---|
| `backend/app/db/__init__.py` | 0 | علامة حزمة بايثون |
| `backend/app/db/init_db.py` | 1777 | قاعدة conversations.db: كل جداول المنتج (51 من 54) ودوال _ensure_* وSCHEMA_VERSION=37 (v37: `api_tokens.mint_kind` + `device_restore_keys` + `merge_tombstones`)؛ فيها إعادة بناء مدمّرة لـlesson_progress/child_challenges/donations |
| `backend/app/db/migrations/__init__.py` | 1 | سجلّات الترحيلات المرقّمة الصريحة (v16/v20 القديمة لا تُعاد) |
| `backend/app/db/migrations/bahouth_cache_0001_baseline.py` | 135 | ترحيل أساس: تبنّي جدول bahouth_cache |
| `backend/app/db/migrations/query_rewrites_0001_baseline.py` | 105 | ترحيل أساس: تبنّي جدول query_rewrites (+redacted) |
| `backend/app/db/migrations/runner.py` | 174 | مشغّل ترحيلات مرقّمة بـchecksum وإضافية داخل قاعدة SQLite واحدة (schema_migrations) |
| `backend/app/db/migrations/sessions_0001_baseline.py` | 104 | ترحيل أساس: تبنّي جدول sessions (INSERT موضعي = ترتيب الأعمدة جزء من العقد) |
| `backend/app/db/migrations/tafsir_cache_0001_baseline.py` | 140 | ترحيل أساس: تبنّي جدول tafsir_cache الإنتاجي |
| `backend/app/db/migrations/telemetry_0001_llm_calls.py` | 96 | ترحيل ثابت 1: تبنّي llm_calls وإضافة tier/route_reason |
| `backend/app/db/migrations/telemetry_0002_usage_estimated.py` | 47 | ترحيل ثابت 2: عمود llm_calls.usage_estimated |
| `backend/app/db/migrations/v16_habit_templates.py` | 43 | ⚠️ ترحيل قديم standalone (habit_templates) — لا أحد يستوردها |
| `backend/app/db/migrations/v20_feedback_replies.py` | 50 | ⚠️ ترحيل قديم standalone (feedback_replies) — لا أحد يستوردها |

### backend/app/routers/ — مسارات الـHTTP (30 وحدة)

كل ملف يُركَّب في `main.py`. خرائط المسارات الكاملة في `03-interfaces.md`.

| الملف | أسطر | الدور |
|---|---:|---|
| `backend/app/routers/__init__.py` | 0 | حزمة routers (فارغة) |
| `backend/app/routers/assistant.py` | 1742 | قلب المنتج: /api/assistant/{draft,query,stream} — سلسلة: دعم القلق الذاتي ← حظر ← طوارئ ← discipline ← fiqh ← تصنيف ← استرجاع هجين ← LLM ← guardrails؛ SSE + كاش + ذاكرة الطفل |
| `backend/app/routers/chat.py` | 212 | جلسات المحادثة: إنشاء (عام؛ يحدد الهوية بتوكن أو مفتاح استعادة ويسجّل `mint_kind`)، `POST /restore-key`، قائمة، تاريخ، إيقاف البث |
| `backend/app/routers/child_memory.py` | 390 | ذاكرة الطفل والمتابعات وخطة الأسبوع («المربّي يعرف ابنك» v30) — 16 مسارًا |
| `backend/app/routers/child_mode.py` | 514 | مسارات وضع الطفل (Child-Bearer): جلسات الشاشة/نبض/اتفاقية/مهمة/رخصة/أحداث العادات |
| `backend/app/routers/child_mode_web.py` | 145 | تطبيق QR للمراهقين: claim-session/me/refresh |
| `backend/app/routers/children.py` | 1122 | ملفات الأطفال + التقدّم + التحدي + الاتفاقية + المهام المعلّقة + «اليوم» + رخصة الإنترنت (23 مسارًا) |
| `backend/app/routers/daily_routine.py` | 292 | «حِساب اليوم»: أحداث الروتين اليومي (0–6 سنوات) + ملخّص |
| `backend/app/routers/device_proof.py` | 95 | إثبات الجهاز عبر تحدّي FCM (get/start/complete) |
| `backend/app/routers/family.py` | 32 | «قناديل الأسبوع»: GET /api/family/week |
| `backend/app/routers/family_programs.py` | 541 | برامج الأسرة: رمضان، رحلة الصلاة، المراحل، + صلاة الطفل في وضعه |
| `backend/app/routers/feedback.py` | 700 | ملاحظات المستخدم (نص/صوت) + تحليل + ردود عبر تلجرام webhook + تقييم المحادثة |
| `backend/app/routers/habit_templates.py` | 133 | قوالب العادات المخصّصة لكل طفل |
| `backend/app/routers/health.py` | 128 | /health و/api/health و/api/app-config (بوابة التحديث الإجباري، `latest_build_number` لبطاقة التحديث الاختيارية، store_url، STORY_MOTION_MODE، `hub_hidden_items`) |
| `backend/app/routers/identity.py` | 1808 | ربط Google Sign-In الاختياري بجهاز مجهول (link-google, me) + دمج العائلات المقيّد؛ التأكيد يرفض الجلسة «العارية»، والدمج يحترم شواهد الحذف (`merge_tombstones`) |
| `backend/app/routers/insights.py` | 160 | GET /api/insights/parenting — رؤى تربوية مولّدة بالـLLM |
| `backend/app/routers/methodology.py` | 262 | صفحة «منهجيتنا ومصادرنا» العامة /methodology (+ قسما `#prophets` و`#seerah` بلغتين) |
| `backend/app/routers/print_pack.py` | 389 | `GET /print/ramadan` — برنامج «رمضان العائلة» أوراقًا للطباعة (12 ورقة A4، ar/en) تُولَّد وقت الطلب من `programs/ramadan_family.json`؛ لا نص جديد |
| `backend/app/routers/privacy.py` | 616 | /privacy-policy و/delete-account (HTML عام) + حذف ذاكرة الأطفال (يسجّل شواهد حذف) + حذف الحساب كله (كل جدول فيه `device_id`) |
| `backend/app/routers/program.py` | 927 | المنهج: مسارات/دروس/أصول/بحث/نصيحة المرشد/كويز/قصة مولّدة/تقدّم الدرس/تقرير شهري/موقف بقرار |
| `backend/app/routers/push.py` | 151 | تسجيل توكن FCM للجهاز (+app_version/build_number)؛ تغيّر التوكن بلا إثبات يُلغي تأكيد روابط Google للجهاز |
| `backend/app/routers/quranic_linguistics.py` | 175 | تحليل لغوي قرآني (جذور/مواضيع/قراءات) فوق خدمة Bahouth MCP — عام |
| `backend/app/routers/referral.py` | 177 | كود الدعوة الشخصي + مطالبة (تشمل أكواد الحملات) |
| `backend/app/routers/seo.py` | 644 | صفحات SEO لأسئلة الألم الشائعة /seo/{slug} |
| `backend/app/routers/stats.py` | 164 | إحصاء مجتمعي عام + /api/stats/ops-llm لمراقبة OMAR (X-Ops-Token) |
| `backend/app/routers/story_events.py` | 128 | تجربة «صورة حيّة»: POST /api/stories/events |
| `backend/app/routers/support.py` | 76 | «ادعم المربّي»: شفافية عامة + تحقق مشتريات Play |
| `backend/app/routers/tafsir.py` | 131 | تفسير موثّق (آية/نزول) فوق Tafsir MCP — عام |
| `backend/app/routers/value_tracking.py` | 410 | «ميزان العادات» (7–18 سنة): اليوم/أحداث/ملخّص |
| `backend/app/routers/web.py` | 455 | الصفحات العامة: الهبوط (/، /go، /ui/)، /l/{lesson}، /p/{path} (عربي/إنجليزي حسب اللغة + `Vary: Accept-Language`)، sitemap.xml، robots.txt + إسناد التثبيت |

### backend/app/services/ — منطق العمل (62 ملفًا)

| الملف | أسطر | الدور |
|---|---:|---|
| `backend/app/services/__init__.py` | 0 | حزمة services (فارغة) |
| `backend/app/services/age_normalization.py` | 58 | تطبيع الفئات العمرية للقيم القانونية |
| `backend/app/services/ai_gateway.py` | 1964 | البوابة الموحّدة لكل نداءات LLM: مزوّدات (Ollama/OpenAI-compat/DeepSeek)، مسارات threads، آجال مطلقة، تتبّع البث، تيليمتري llm_calls، حجز ميزانية السحابة، aux_generate |
| `backend/app/services/answer_cache.py` | 308 | كاش الإجابات الدلالي (تطابق مُطبَّع ثم cosine e5 ≥ 0.92) لأول سؤال في الجلسة فقط |
| `backend/app/services/attribution.py` | 383 | إسناد التثبيت: بناء رابط Google Play بالـreferrer، تسجيل نقرات /go، مطابقة IP خلال 24 ساعة |
| `backend/app/services/bm25_index.py` | 106 | فهرس BM25 في الذاكرة (الساق المعجمية للاسترجاع الهجين) |
| `backend/app/services/child_budget.py` | 553 | ميزانية وقت الشاشة للطفل على الخادم (نبض لا ساعة جدار، تاريخ محلي من الخادم، أرضية 24 ساعة) |
| `backend/app/services/child_license.py` | 473 | رخصة الإنترنت المستوى 1: مواقف تدريبية → حديث الأسرة → منح (لا صلاحية حقيقية) |
| `backend/app/services/child_memory.py` | 1738 | ذاكرة الطفل: استخراج حقائق (LLM) + إخفاء الأسماء + سقف توكنز شهري + متابعات |
| `backend/app/services/child_missions.py` | 563 | بطاقة المهمة اليومية بعيدًا عن الشاشة + تأكيد المساء + مهام رحلة الصلاة |
| `backend/app/services/child_token.py` | 229 | توكنات وضع الطفل (HMAC بـCHILD_MODE_SECRET، بلا device_id) |
| `backend/app/services/cloud_budget.py` | 1017 | دفتر ميزانية سحابية دائم لكل محاولة سلكية (حجز/تسوية/anchor/witness triggers) — اختياري CLOUD_BUDGET_ENFORCE |
| `backend/app/services/cloud_budget_bootstrap.py` | 67 | CLI تشغيلي لتهيئة دفتر الميزانية (cutover) دون قراءة env/DB افتراضية |
| `backend/app/services/coach_safety.py` | 106 | فاحص حتمي لسلامة نصائح المرشد (الطول/المجال/العمر) |
| `backend/app/services/coach_service.py` | 677 | المرشد التربوي الاستباقي: نصيحة مخصّصة لطفل اليوم بتدهور رشيق إلى النصيحة اليومية (COACH_TIP_ENABLED) |
| `backend/app/services/content_lang.py` | 74 | اختيار ملف لغة بنك المحتوى (ar/en) مع رجوع للعربية |
| `backend/app/services/conversation_store.py` | 455 | تخزين الجلسات والرسائل والتوكنات (chat_sessions/chat_messages/api_tokens) + `mint_kind` و`token_is_bare` و`is_birth_race` (نافذة 120ث) |
| `backend/app/services/device_alerts.py` | 167 | إشعار الهاتف الذي فقد توكن الحساب (نهارًا بتوقيت الأسرة، مرة يوميًا) |
| `backend/app/services/device_proof.py` | 504 | إثبات أن الجلسة تحمل الهاتف خلف device_id عبر تحدّي FCM |
| `backend/app/services/device_twins.py` | 550 | إصلاح «توائم الجهاز» (معرّفان لتثبيت واحد) بدمج صفوف التوأم في العائلة |
| `backend/app/services/discipline_guard.py` | 449 | حارس: المربّي لا يوجّه أبدًا إلى الضرب/العقاب البدني (دقة عالية) |
| `backend/app/services/domain_classifier.py` | 975 | مصنّف المجالات v3.1: مسار سريع بالكلمات + كاش + LLM مساعد؛ سؤال «لماذا خلق الله الشر» → `aqeedah` أولًا |
| `backend/app/services/donations.py` | 813 | دفتر «ادعم المربّي»: تحقق Play، مجموع الشهر، شفافية (DONATIONS_ENABLED) |
| `backend/app/services/erased_devices.py` | 146 | سجل الأجهزة المحذوفة (الحساب المحذوف يبقى محذوفًا) |
| `backend/app/services/family_actions.py` | 308 | السجل المرجعي للأفعال الأسرية ذات المعنى («عدّاد صادق») |
| `backend/app/services/family_agreement.py` | 337 | الاتفاقية الأسرية للإعلام: بنود مزدوجة (أهل/طفل) وتوقيع لكل بند ثم لكل شخص |
| `backend/app/services/feedback_analyzer.py` | 272 | تحليل ذكي (LLM) لملاحظات المستخدمين إلى قرارات مرتّبة |
| `backend/app/services/fiqh_guard.py` | 255 | حارس: يحجب أسئلة الفتوى/الأحكام العقدية برد آمن ويسجّل في blocked_fiqh_log |
| `backend/app/services/fiqh_intent.py` | 222 | بروتوكول نيّة فقهية — ظلّي فقط (FIQH_INTENT_MODE=shadow) لا إنفاذ |
| `backend/app/services/followup_push.py` | 167 | إشعار «جرّبت النصيحة؟ نفعت؟» الساعة 19:00 بتوقيت الأسرة |
| `backend/app/services/guardrails.py` | 296 | تطبيق سياسات المجال/الشدة على المسودة؛ طوارئ، إحالة طبية، رسالة بديلة |
| `backend/app/services/habit_streak.py` | 142 | سلاسل العادات وشريط 7 أيام |
| `backend/app/services/hadith_guard.py` | 262 | حارس الحديث على إجابة المساعد قبل أن تُقرأ: الصحيحان بلفظهما ← تخريج يُكتب؛ السنن الأربعة بما صحّحه/حسّنه الألباني ← تخريج + الدرجة؛ غير ذلك ← تُحذف الجملة (فوق `scripture_scan`) |
| `backend/app/services/hijri_seasons.py` | 90 | «سماوات المواسم»: رجب/شعبان/أوائل ذي الحجة |
| `backend/app/services/index_seed.py` | 48 | خبز فهرس المعرفة داخل الصورة (يُنفَّذ في Dockerfile) |
| `backend/app/services/intent_guard.py` | 1408 | حارس النوايا الضارة، الطوارئ، الإساءة، الاختصارات الحوارية، لغة الرد — قبل أي LLM |
| `backend/app/services/knowledge_loader.py` | 189 | تحميل وحدات المعرفة من القرص مع تطبيع age_group |
| `backend/app/services/license_alert.py` | 73 | الإشعار الوحيد الذي لا ينتظر المساء (تنبيه الأب من موقف الرخصة) |
| `backend/app/services/llm_service.py` | 472 | بناء الـprompt الكامل وتوليد الرد وتنظيفه واستشهادات المصادر (لا يُعدّ «كتاب إسلامي» مصدرًا) وتحويل pivot عام |
| `backend/app/services/mawaqif.py` | 65 | «موقف بقرار» (docs/MAWAQIF.md): تحميل بنك المواقف ونسخته الإنجليزية، التحقق من اكتمال العنصر، والتصفية حسب العمر |
| `backend/app/services/merge_tombstones.py` | 105 | **شواهد الحذف عبر الأجهزة** (v37): ما حذفه الوالد (طفل/حقيقة/ذاكرة) يبقى محذوفًا في دمج حساب Google؛ مفاتيح مُجزّأة؛ يكتبها `privacy.erase_*` و`child_memory.delete_*`، ويقرؤها `identity._merge_legacy_device_data` |
| `backend/app/services/milestone_push.py` | 315 | إشعار المراحل قبل شهر الساعة 20:00 بتوقيت الأسرة (MILESTONES_MIN_BUILD) |
| `backend/app/services/milestones.py` | 228 | المراحل الاستباقية («ابنك هيكمّل ٧ سنين الشهر الجاي») |
| `backend/app/services/mission_digest.py` | 201 | ملخّص المساء للأب (إشعار واحد) + حلقة الإشعارات المحلية-الساعة DIGEST_TICK_SECONDS |
| `backend/app/services/prayer_journey.py` | 663 | «رحلة الصلاة»: تسجيل، مراحل، مهام الطفل، تخرّج (بلا عقاب) |
| `backend/app/services/privacy.py` | 958 | إخفاء أسماء الأطفال (عربي/لاتيني، تصريفات وإخوة كعناصر نائبة) قبل أي نص يغادر لنموذج أو خدمة خارجية؛ Family/redact_family/relabel |
| `backend/app/services/programs_common.py` | 410 | ما تشترك فيه برامج الأسرة الثلاثة: المحتوى والعمر وساعة الأسرة |
| `backend/app/services/push_sender.py` | 353 | إرسال FCM عبر Firebase Admin (best-effort) + دالة send_to_device |
| `backend/app/services/query_rewriter.py` | 155 | إعادة صياغة السؤال العامّي لبحث أفضل (LLM مساعد) مع كاش query_rewrites |
| `backend/app/services/quranic_linguistics_service.py` | 754 | طبقة التحليل اللغوي القرآني (Bahouth MCP) مع كاش bahouth_cache |
| `backend/app/services/ramadan_program.py` | 817 | «رمضان العائلة»: اليوم، سلّم الصيام، علامات «تمّ»، بطاقة الأسرة |
| `backend/app/services/reranker.py` | 180 | إعادة ترتيب بـCross-Encoder (mmarco-mMiniLMv2) مع ميزانية زمن وحدّ أدنى للثقة |
| `backend/app/services/restore_keys.py` | 88 | **مفتاح الاستعادة** (v37): مفتاح `tgr_…` لكل جهاز (تُخزَّن بصمته فقط في `device_restore_keys`) يثبت هوية الجهاز بعد إعادة التثبيت عبر ترويسة `X-Device-Restore` — يُغلق «السكّ العاري» (H5). الـdocstring يذكر `/api/device/restore-key` والمسار الفعلي `POST /api/chat/restore-key` |
| `backend/app/services/retention.py` | 194 | فرض سياسة الاحتفاظ بالخصوصية يوميًا (90/45/7 يومًا) |
| `backend/app/services/retrieval.py` | 1041 | استرجاع ChromaDB (e5-small) هجين: متجه + BM25 → RRF → إعادة ترتيب + فلترة العمر/المجال + retrieval_log |
| `backend/app/services/sensitive_content.py` | 170 | ما يجب ألا تحتفظ به ذاكرة الطفل وما لا يجوز أن تقتبسه متابعة |
| `backend/app/services/session_logger.py` | 60 | تسجيل استعمال كل دورة في sessions (بلا نص) |
| `backend/app/services/story_experiment.py` | 170 | أرقام تجربة «صورة حيّة» للتقرير الأسبوعي وحكم نهاية الشهر |
| `backend/app/services/story_service.py` | 160 | كاش القصص المولّدة مسبقًا (قيمة×عمر×جنس) مع بطل قانوني واستبدال الاسم وقت التقديم |
| `backend/app/services/tafsir_service.py` | 889 | طبقة التفسير الموثّق (Tafsir MCP) + حلّ مرجع الآية من النص + كاش tafsir_cache |
| `backend/app/services/tier_router.py` | 83 | توجيه الجودة: cloud_quality أم local_fast بحسب خطورة/مجال/طول/ضعف الاسترجاع |
| `backend/app/services/weekly_plan.py` | 487 | «خطة الأسبوع» لكل طفل (v30): تركيز + 3 أفعال + فعل عبادة |

### backend/ — غير `app/` ولا اختبارات

| الملف | أسطر | الدور |
|---|---:|---|
| `backend/DEPENDENCIES.md` | 210 | بيان ملفات الاعتماديات (المرحلة 3) |
| `backend/Dockerfile` |  | صورة الباكند: python:3.11-slim، تثبيت مقفول بالـhash، تنزيل e5+reranker داخل الصورة، خبز فهرس Chroma، مستخدم غير root (uid 10001) |
| `backend/__init__.py` | 0 | علامة حزمة |
| `backend/docs/cloud-budget-reservations.md` | 882 | تصميم حجوزات الميزانية السحابية الشهرية |
| `backend/guardrails/child_surface.v1.yaml` | 134 | بوابة سطح الطفل العمرية (أيّ أسطح لأي شريحة) — نسخة التطبيق تُختبر ضدها |
| `backend/guardrails/policies.v1.yaml` | 206 | سياسات المجالات والشدّة (طبي/سيبراني/تربوي/تنموي) المقروءة عند كل طلب |
| `backend/requirements-dev.txt` | 5 | اعتماديات التطوير/الاختبار |
| `backend/requirements.txt` | 48 | اعتماديات الباكند (chromadb<1 محجوز عمدًا) |
| `backend/scripts/debug_coach.py` | 94 | أداة تصحيح: توليد نصيحتين مع لوج مفصّل |
| `backend/scripts/generate_coach_samples.py` | 140 | توليد ~20 عيّنة نصيحة للمراجعة البشرية (Gate #1) |
| `backend/static/child_mode/index.html` | 238 | صفحة المراهق عبر QR (مفتوحة على /child-mode/web) |
| `backend/static/child_mode/styles.css` | 69 | أنماط صفحة المراهق |

## 2) اختبارات الباكند — `backend/tests/`

pytest (`pytest.ini` في الجذر)؛ المحلي يجب `backend/.venv/bin/python -m pytest` لا `python3` المجرّد. دعم مشترك: `conftest.py`, `*_support.py`, `fake_deepseek.py` (خادم DeepSeek/Ollama مُحاكى).

### backend/tests/

| الملف | أسطر | الدور |
|---|---:|---|
| `backend/tests/__init__.py` | 0 | علامة حزمة بايثون |
| `backend/tests/budget_test_helpers.py` | 26 | Explicit simulated cutover evidence for paid-wire tests; never production data. |
| `backend/tests/conftest.py` | 189 | Shared test fixtures — isolates the conversation DB to a temp file. |
| `backend/tests/conversations_db_support.py` | 102 | The per-test conversations DB (conftest's autouse `_temp_conversations_db`). Every test gets a fresh SQLite file, and `db_path()` reads… |
| `backend/tests/device_proof_support.py` | 71 | Run the real device-proof challenge from a test (services/device_proof.py). FCM is replaced by an inbox that records each silent data message — what… |
| `backend/tests/fake_deepseek.py` | 535 | Simulated DeepSeek (OpenAI-compatible SSE) + Ollama NDJSON server. A test helper, not a test: written for the PR #24 review (round 2) and kept |
| `backend/tests/fixtures/fiqh_author_fix_validation.json` |  | اختبارات: fiqh author fix validation |
| `backend/tests/fixtures/fiqh_intent_phase1_validation.json` |  | اختبارات: fiqh intent phase1 validation |
| `backend/tests/fixtures/ga4_cohort_by_campaign_2026-10-16.json` |  | اختبارات: ga4 cohort by campaign 2026-10-16 |
| `backend/tests/fixtures/lesson11_reviewed_db07c35f/ar.json` |  | اختبارات: ar |
| `backend/tests/fixtures/lesson11_reviewed_db07c35f/en.json` |  | اختبارات: en |
| `backend/tests/fixtures/play_vitals_crash_rate_2026-10-16.json` |  | اختبارات: play vitals crash rate 2026-10-16 |
| `backend/tests/fixtures/prod_device_tables_2026-10-04.sql` | 320 | اختبارات: prod device tables 2026-10-04 |
| `backend/tests/fixtures/prod_launch_report_tables_2026-10-16.sql` | 173 | اختبارات: prod launch report tables 2026-10-16 |
| `backend/tests/fixtures/prod_sessions_db_2026-10-08.sql` | 88 | اختبارات: prod sessions db 2026-10-08 |
| `backend/tests/prod_schema_support.py` | 84 | Production's sessions.db schema, for baseline-migration tests. The fixture is production's own DDL (copied read-only from tg_backend, schema |
| `backend/tests/programs_support.py` | 110 | Shared set-up for the family-program tests (schema v34). The app is mounted with a stub auth middleware, like the other child-surface |
| `backend/tests/test_account_deletion.py` | 353 | Account deletion — DELETE /api/privacy/account (Google Play: in-app deletion). Two halves, both needed: |
| `backend/tests/test_agreement_build_gate.py` | 107 | The agreement gate must not lock out a build that cannot sign. The gate has been finished, tested and switched **off** since 2026-08-16, for |
| `backend/tests/test_answer_cache.py` | 71 | Semantic answer cache tests (growth plan §5.1). |
| `backend/tests/test_answer_cache_callers_revision.py` | 103 | Real cache writes through streaming and both offline warmers, without models. |
| `backend/tests/test_answer_cache_source_revision.py` | 252 | Quarantining a source must invalidate answers before index startup/purge. |
| `backend/tests/test_answer_reliability.py` | 1148 | Unanswered questions — one test per mechanism, each failing without its fix. Production, 30 days to 2026-10-04: 44 of 290 parent questions (15.2%)… |
| `backend/tests/test_api_smoke.py` | 195 | API smoke tests — endpoint wiring, guardrails, auth, and session persistence. The LLM gateway and the vector retrieval are mocked, so these run fast… |
| `backend/tests/test_app_help_routing.py` | 436 | App-help questions reach the app-help units — and parenting questions never do. Before 2026-10-05 nothing in the knowledge base described the app… |
| `backend/tests/test_app_help_stays_internal.py` | 175 | app_help` is a server-side domain: no response, stream frame or chat row a client reads ever carries it. |
| `backend/tests/test_aqeedah_reachable.py` | 83 | The aqeedah domain must stay reachable, and «الله» must not become a catch-all. Ten authored units — «من هو الله؟», «ما بعد الموت؟», «أسماء الله… |
| `backend/tests/test_asset_content.py` | 68 | Asset-content endpoint tests — GET /api/program/asset-content/{asset_id}. Validates the additive v1 endpoint that serves full flashcard/quiz JSON |
| `backend/tests/test_attribution.py` | 221 | Install-referrer contract — the link the server builds vs. what reads it. Two readers parse the `referrer` we put on a Google Play link, and neither… |
| `backend/tests/test_audit_regressions.py` | 232 | Regression tests for the 2026-09 audit fixes (see AUDIT_AND_ROADMAP.md). All of these run against the real `app.main.app` — its real AuthMiddleware — |
| `backend/tests/test_aux_llm_routing.py` | 244 | Auxiliary LLM tier — domain classifier + query rewriter routing. Both used to post straight at a hard-coded Ollama host with a 45s / 6s |
| `backend/tests/test_avatar_picker_server_parity.py` | 39 | كل أفاتار يعرضه منتقي التطبيق يقبله الخادم (انحدار ⭐ و«العائلة» ذات 9 نقاط ترميز، 2026-11-06) |
| `backend/tests/test_background_work_isolation.py` | 75 | Work a test leaves running must finish on that test's own DB. CI, 2026-10-08 (PR #93, run 37840203783): 4116 passed, 1 error — |
| `backend/tests/test_bare_mint_closure.py` | 498 | إغلاق السكّ العاري (H5) واستيلاء ربط Google: `mint_kind`، توريث «العاري»، مفتاح الاستعادة، سلوك `SESSION_MINT_ENFORCE` للبنايات ≥117 وما قبلها |
| `backend/tests/test_build_census.py` | 110 | What is actually installed out there — the number the force-update lever needs. `MINIMUM_BUILD_NUMBER` is a lever that force-updates every device… |
| `backend/tests/test_cache_invalidation.py` | 70 | Rebuilding the knowledge index must drop the answers derived from it. A cached answer freezes what the units said when it was generated, «📚 المصادر» |
| `backend/tests/test_cache_schema_migrations.py` | 298 | Baseline migrations for the tafsir/bahouth cache tables in ops/sessions.db. Every "production" database here is built from production's own DDL |
| `backend/tests/test_campaign_code_registry.py` | 120 | The campaign code registry, and the QR codes printed on the videos. ops/data/campaign_codes.md is where every code handed out is written |
| `backend/tests/test_campaign_codes.py` | 168 | Campaign codes: a campaign install can no longer be lost to a 404. The app makes exactly one claim per install (referral_service.dart sets |
| `backend/tests/test_campaign_report.py` | 398 | ops/scripts/campaign_report.py — numbers checked by hand on a built database. The database is the app's real schema (conftest runs init_db on a temp… |
| `backend/tests/test_check_kb_fidelity.py` | 219 | KB fidelity guard (ops/tools/check_kb_fidelity.py). The assistant cites a unit's `text_simplified` as evidence; nobody compared it |
| `backend/tests/test_child_budget.py` | 378 | The time budget, tested from the outside in. Most of these assert a refusal. The budget's only job is to say no at the |
| `backend/tests/test_child_deletion.py` | 134 | P3 (PR #26 review): deleting a child deletes everything tied to the child. DELETE /api/children/{id} used to remove only the child_profiles row,… |
| `backend/tests/test_child_license.py` | 490 | The internet licence, level 1. Most of these are negative tests, because most of what this feature promises |
| `backend/tests/test_child_memory.py` | 1058 | Child memory (schema v30) — «المربّي يعرف ابنك». What these tests pin, in the order the brief asked for them: |
| `backend/tests/test_child_missions.py` | 573 | The mission card and the evening that settles it. The card is where the product's central claim becomes checkable: a minute of |
| `backend/tests/test_child_mode_web.py` | 220 | Integration tests for the QR Web App (Phase 4). |
| `backend/tests/test_child_surface_endpoints.py` | 709 | The gate as the network sees it. test_child_budget.py proves the service refuses. This file proves the refusal |
| `backend/tests/test_child_surface_policy.py` | 208 | The child-surface policy is a gate, so these tests are mostly refusals. The shipped file loading correctly is one test. The other nineteen are |
| `backend/tests/test_child_token_v2.py` | 77 | Child tokens carry no device id (PR #26 review, P1). A child's web token used to carry the parent's device id in readable base64: a |
| `backend/tests/test_child_web_claims.py` | 92 | Audit L11: one-time QR claim codes for the teen web surface are durable, single-use under concurrency, and stored so that a copy of the table is… |
| `backend/tests/test_child_web_page.py` | 92 | The teen QR page (backend/static/child_mode/index.html) against the API it calls and the app it belongs to (UX_UI_ROADMAP §4.3, AUDIT H8). |
| `backend/tests/test_cinematic_landing.py` | 217 | The landing page in the «نور والقناديل» identity (Oct 2026 launch). Attribution — every Play link carrying ref/utm_* — is… |
| `backend/tests/test_classifier.py` | 269 | Tests for the domain classifier — keyword fast-path + cache + LLM fallback. These tests mock the Ollama call so they're fast and need no network. |
| `backend/tests/test_classifier_english_keywords.py` | 438 | English lexical routing, priority, and boundary regressions; no providers. A fast-path hit blocks the model classifier and the query rewrite, so these |
| `backend/tests/test_classifier_general_veto.py` | 54 | A "general" verdict on a question about the parent's own child is vetoed. `general` is the one classification that skips retrieval entirely and… |
| `backend/tests/test_classifier_short_keywords.py` | 464 | Short Arabic keyword regressions: lexical routing only, no provider calls. |
| `backend/tests/test_client_ip.py` | 181 | ClientIPMiddleware — the real client behind the local proxies (audit H4). Production (2026-10-04): tg-api.alsaba.cloud arrives Cloudflare → Tunnel → |
| `backend/tests/test_cloud_billing_profiles.py` | 151 | Documented profiles and explicit opt-out, without paid transports. |
| `backend/tests/test_cloud_budget_cutover.py` | 558 | Explicit cutover authority; fresh/restored telemetry is not spend authority. |
| `backend/tests/test_cloud_budget_ledger_scale.py` | 220 | Ledger under contention and history (review of PR #71, P1). A settle is never a denial: it waits for the ledger instead of being |
| `backend/tests/test_cloud_budget_lifecycle.py` | 118 | Shutdown and Linux fork regressions for the opt-in reservation settler. |
| `backend/tests/test_cloud_budget_operability.py` | 296 | Operability before anyone enables the cap (re-review of c8597396, P3). 1. Settle never waits on the request path: it settles inline only if the |
| `backend/tests/test_cloud_budget_reservations.py` | 748 | Admission must be atomic at the actual paid wire, including ambiguous failures. |
| `backend/tests/test_cloud_budget_switch.py` | 105 | CLOUD_BUDGET_ENFORCE: the branch is safe to deploy before any bootstrap. Off (the default) is production's behaviour before this branch: no wire |
| `backend/tests/test_coach_safety.py` | 52 | اختبارات: coach safety |
| `backend/tests/test_coach_tip_language.py` | 90 | The Home tab's most prominent card, in the reader's language. Seen on an emulator set to English, running 1.0.52: every label on the Home tab |
| `backend/tests/test_coach_tip_tap.py` | 107 | Coach tip tap endpoint tests — guards against mobile crash on stale tap. The POST /api/program/coach-tip/{tip_id}/tap endpoint records an analytics |
| `backend/tests/test_cron_push_triggers.py` | 309 | اختبارات: cron push triggers |
| `backend/tests/test_curriculum_i18n.py` | 379 | English lessons must actually reach English users. All 170 lessons, 39 paths and tips/search have been translated and sit in |
| `backend/tests/test_daily_quota.py` | 83 | Fair-use daily AI quota tests (growth plan §5.1). The daily cap must: count only AI-scope POSTs, refuse with the gentle Arabic |
| `backend/tests/test_daily_routine.py` | 254 | Tests for the «حِساب اليوم» daily-routine API. Uses a minimal FastAPI app with the daily_routine router only, plus the |
| `backend/tests/test_daily_tips_indexed.py` | 89 | نصائح اليوم تدخل فهرس الاسترجاع — وإلا لم يجد follow-up عليها مصدرًا. البلاغ الحي (تقرير فجوات المعرفة): أولياء يسألون عن نصيحة وصلتهم ("بخصوص |
| `backend/tests/test_deepen_paths.py` | 598 | The gates in ops/tools/deepen_paths.py are what stand between a draft and a parent. The deepened paths (prayer and religion, anger and stubbornness,… |
| `backend/tests/test_deepseek_callers_are_recorded.py` | 329 | No paid DeepSeek call outside the recorded path. October 2026: the weekly VPS cron (weekly_kb_gap_report → kb_gap_judge) judged |
| `backend/tests/test_deepseek_documented_model.py` | 298 | DeepSeek's documented model IDs, the legacy-name alias, and a USD-derived cap. Ground truth (fetched 2026-10-08, URLs + SHA-256 in |
| `backend/tests/test_deepseek_wire.py` | 310 | The DeepSeek wire, against a simulated server on a real socket. PR #24 review, round 2 (R1–R8): the provider reads DeepSeek's SSE itself, so |
| `backend/tests/test_dependency_manifests.py` | 258 | Lightweight install-contract checks; no Docker, resolver, model or API calls. Run directly with unittest so backend's application fixtures are not… |
| `backend/tests/test_deploy_gate.py` | 194 | The deploy gate: production only gets a commit whose hosted tests passed. Two halves. The decision logic of ops/tools/deploy_gate.py, on recorded API |
| `backend/tests/test_device_proof.py` | 448 | Device proof — the FCM challenge behind the protected routes (PR #26 review, round 2). The token-chain proof is gone: it locked out for good a device… |
| `backend/tests/test_device_twins.py` | 637 | Device twins (2026-10-04): an install that 1.0.58-1.0.67 split into two device ids is put back together — and nothing ever crosses families. |
| `backend/tests/test_device_twins_feedback.py` | 28 | Feedback and replies follow a folded device (PR #29 review, item 7). An old build keeps the twin's id on disk and sends it in the unauthenticated |
| `backend/tests/test_device_twins_review.py` | 219 | مراجعة PR #29 — السيناريوهات التسعة العدائية كاختبارات انحدار (كل سيناريو للمراجع بعد عكس التأكيد: كان يُثبت ثغرة قبل الإصلاح والآن يؤكد إغلاقها). سكربتات الهجوم الأصلية بقيت في scratch المراجعة (لم تُكوميت)؛ الـdocstring لم يعد يحيل إلى مسار ملف غير موجود |
| `backend/tests/test_discipline_guard.py` | 270 | The discipline guard is HIGH-PRECISION ONLY — pinned row by row. Design (coordinator, 2026-10-04): real volume is low (12 hits in 4,295 real |
| `backend/tests/test_donations.py` | 1021 | «ادعم المربّي» — the ledger, the verifier contract, and the transparency sum. Play itself is faked: the contract under test is what this server does… |
| `backend/tests/test_draft_units_gate.py` | 139 | Units awaiting a scholar's review are not indexed or served (167-F). Draft units (e.g. the parent-doubts drafts) carry `translation.draft_status ==… |
| `backend/tests/test_en_media_stall_guard.py` | 59 | scripts/cron_gen_en_media.sh — the stall guard resets only on real delivery. Runs the guard's inline Python (the heredoc in the cron script) as-is. |
| `backend/tests/test_erased_devices.py` | 283 | Erased-device tombstones (schema v35) — an account deleted in the app stays deleted (review of PR #36). |
| `backend/tests/test_eval_traffic.py` | 56 | Eval traffic is marked, and the eval harness never writes to the live DB. The 2026-09-24 baseline ran inside the production container, where |
| `backend/tests/test_evil_question_routing.py` | 138 | «ليه ربنا خلق الشر؟» يُوجَّه إلى `aqeedah` (و`fiqh`) دون التقاط «شرح/شرب» |
| `backend/tests/test_family_actions.py` | 172 | The canonical family-action registry (نور والقناديل, Phase 0 «عدّاد صادق»). The weekly funnel report and the upcoming /api/family/week must never |
| `backend/tests/test_family_agreement.py` | 225 | The agreement is two-sided or it is not an agreement. Most of these assert that half-formed agreements are refused: one that binds |
| `backend/tests/test_family_week.py` | 355 | «قناديل الأسبوع» — GET /api/family/week (نور والقناديل, Phase 3). The lantern counter reads the same registry as the weekly funnel report |
| `backend/tests/test_feature_usage_audit.py` | 150 | اختبارات قراءة فقط لجرد استعمال الجداول لمدة 30 يومًا واكتشاف انحراف العمر الثابت وجاهزية مخطط الأسرة |
| `backend/tests/test_feedback_admin_reply.py` | 222 | Admin reply endpoint — the supported way to answer a parent off Telegram. Before this existed the only way to send a reply outside Telegram was a |
| `backend/tests/test_feedback_reply_loop.py` | 297 | Feedback reply loop — security gates and routing. The Telegram webhook is a public, unauthenticated endpoint that writes to the |
| `backend/tests/test_feedback_session_ownership.py` | 155 | Real HTTP feedback attribution; no external transport is permitted. |
| `backend/tests/test_final_review_regressions.py` | 360 | PR #26 final review — the seven probes, inverted into regression tests. Each probe (review-pr26/final/probes) passed on e420b001, proving a live or a |
| `backend/tests/test_fiqh_author_fix.py` | 203 | Author fixes: independent synthetic regressions and narrow parenting routes. No current user logs/training labels. Cases derive from approved v3… |
| `backend/tests/test_fiqh_guard_precision.py` | 132 | FIQH guard precision + pipeline order (2026-09 audit). Two defects, both reproduced before the fix: |
| `backend/tests/test_fiqh_intent_phase1.py` | 240 | Mock-only protocol cases from FIQH_GUARD.md v3 and precision regressions. These are approved-example derivatives, not live-week labels or human… |
| `backend/tests/test_fiqh_log_privacy.py` | 79 | Audit M4/M5 follow-up: the blocked-question log keeps the phrasing that tripped a rule, not who asked — and not forever. |
| `backend/tests/test_followup_push.py` | 285 | The follow-up push (services/followup_push.py) — schema v30. It runs from the backend's in-process loop at 19:00 on each family's own |
| `backend/tests/test_glossary_guard.py` | 110 | The glossary guard is a programmatic constraint, not a prompt instruction. It exists because 34 real term injections shipped across four consecutive |
| `backend/tests/test_habit_streak.py` | 106 | Habit streak with the weekly shield, and the 7-day strip (UX-3, §3.2–3.3). |
| `backend/tests/test_hadith_guard.py` | 191 | The assistant's answers: hadith and verses checked before anyone reads them (hadith_guard.py), on the quotes production actually produced. |
| `backend/tests/test_health_threadpool.py` | 147 | Deep health probes must leave the event loop free for the cheap health route. |
| `backend/tests/test_hijri_seasons.py` | 149 | «سماوات المواسم» — the three quiet months the sky on «اليوم» marks. Rajab, Sha'ban and the first days of Dhu al-Hijjah are worked out from the |
| `backend/tests/test_honest_durations.py` | 117 | A path may only promise what its lessons can keep. A mother opened a path labelled «28 يومًا», found four lessons and finished |
| `backend/tests/test_identity.py` | 837 | Tests for Google identity linking with token verification and safe cross-device merge. Uses the same _AuthStubMiddleware pattern used in… |
| `backend/tests/test_index_excludes_policy_docs.py` | 71 | وثائق الحوكمة لا تدخل فهرس الاسترجاع — وتبقى على القرص. قياس 2026-08-13 على شهر من أسئلة الآباء الحقيقية: 51% من الوحدات المسترجَعة |
| `backend/tests/test_index_seed.py` | 126 | The knowledge index baked into the image replaces re-embedding at startup. backend/Dockerfile builds the index with the container's own startup call… |
| `backend/tests/test_infographic_harvest.py` | 572 | scripts/generate_missing_infographics.py — the harvest must finish and remember. Until 2026-09-29 the task list was saved only after the LAST poll;… |
| `backend/tests/test_insights.py` | 141 | اختبارات: insights |
| `backend/tests/test_intent_guard.py` | 994 | Regression tests for the intent guard. The emergency check used to be a substring test over the whole normalized |
| `backend/tests/test_kb_integrity.py` | 22 | CI gate — the knowledge base must stay in sync (the drift-detector lesson). Runs the integrity guard (fast mode) on the real units as a subprocess and |
| `backend/tests/test_landing_attribution.py` | 486 | Every public page that sends a visitor to Google Play carries attribution. `e35bcdc2` rewrote /ui/ for the cinematic landing and silently dropped both |
| `backend/tests/test_landing_language.py` | 270 | The landing in English: who gets it, and what it must keep. English-speaking preachers (EN01…) and community groups (CM01…) were sending |
| `backend/tests/test_launch_weekly_report.py` | 340 | ops/scripts/launch_weekly_report.py — numbers checked by hand. The database is built from production's own DDL (fixtures/ |
| `backend/tests/test_lesson11_source_proof.py` | 88 | Primary evidence and review holds for the authored lesson 11 source fix. |
| `backend/tests/test_lesson_index_integrity.py` | 174 | Structural invariants of docs/lesson_index.json. These are data-level checks with no media on disk, so they run in CI and inside |
| `backend/tests/test_lesson_progress_migration.py` | 300 | الترحيل نفسه: من مفتاح الإنتاج ذي العمودين إلى مفتاح لكل طفل. الاختبارات في `test_progress_upsert_key.py` تشتغل على قاعدة نظيفة، فتثبت |
| `backend/tests/test_log_schema_migrations.py` | 269 | Baseline migrations for sessions.db's `sessions` and `query_rewrites`. Built only from production's copied DDL (tests/prod_schema_support.py). The |
| `backend/tests/test_mawaqif.py` | 115 | «موقف بقرار» — the bank and GET /api/program/mawaqif (docs/MAWAQIF.md): both languages served in full and matching item by item. |
| `backend/tests/test_media_naming.py` | 174 | Media naming is a contract between the API and the generators. Both sides used to derive it independently, which produced two live defects: |
| `backend/tests/test_medical_gap_units.py` | 163 | The four medical units PR #23 found missing stay sourced, safe and reachable. PR #23 shipped red flags for puberty, periods and children's fasting in… |
| `backend/tests/test_medical_no_match_referral.py` | 456 | A medical question the knowledge base cannot answer is referred to a doctor, not sent to the off-topic pivot. |
| `backend/tests/test_memory_privacy_pr36.py` | 1122 | The server-side gaps the mobile review of child memory (PR #36) found. 1. **The memory switch OFF must hold for follow-ups too.** «لا يتعلّم المربّي |
| `backend/tests/test_methodology_prophets.py` | 20 | `/methodology` يصف قصص الأنبياء بلغتين ولا يدّعي مراجعًا بشريًا |
| `backend/tests/test_methodology_seerah.py` | 59 | `/methodology` يصف قصص السيرة (القرآن والصحيحان فقط) ومرساتها `#seerah` |
| `backend/tests/test_migration_checksums.py` | 87 | Numbered migrations are immutable once written: their checksums are pinned. The runner records each migration's SHA-256 in schema_migrations and… |
| `backend/tests/test_migration_fastpath.py` | 221 | The runner's lock-free fast path for an already-migrated database. An open that finds the namespace's ledger complete and every live shape valid |
| `backend/tests/test_min_build_script.py` | 153 | ops/scripts/min_build.sh — the force-update floor is decided on evidence. A floor above what Play actually serves locks everyone below it out with |
| `backend/tests/test_monthly_report_auth.py` | 44 | Monthly report privacy tests — a child's name/progress must never be publicly enumerable (regression for the unauthenticated endpoint). |
| `backend/tests/test_multi_child_progress.py` | 222 | Multi-child progress tracking tests. These verify the fix that makes PATCH /api/program/lessons/{id}/progress |
| `backend/tests/test_nblm_failure.py` | 55 | `scripts/nblm_failure.py`: جلسة NotebookLM ميتة (CSRF/auth) تُميَّز عن مهمة اختفت |
| `backend/tests/test_nblm_session_guard.py` | 195 | scripts/lib/nblm_session.sh — the NotebookLM session guard. Drives the real bash library against a stub `notebooklm` placed first on PATH |
| `backend/tests/test_no_hitting_endorsement.py` | 104 | No text the app serves tells a parent to hit a child. Until 2026-10-04 served knowledge units said «يمكن ضرب الأطفال على ترك الصلاة |
| `backend/tests/test_ops_metrics_auth.py` | 94 | Route-level authentication for private operational metrics (audit M15). |
| `backend/tests/test_parent_mission_today.py` | 193 | Today's mission from the parent's side — no handover needed: GET /children/{id}/mission/today writes nothing, POST …/done confirms it. |
| `backend/tests/test_phase5_progress.py` | 416 | Phase 5 tests — child profiles + progress tracking. Mounts ONLY the children + program routers onto a minimal FastAPI app |
| `backend/tests/test_phase6_streak.py` | 341 | Phase 6 tests — streak calculation + onboarding state. Mounts the children + program routers onto a minimal FastAPI app so |
| `backend/tests/test_phase7_settings.py` | 356 | Phase 7 tests — list / update / reset-progress on /api/children/*. Mounts children + program routers on a minimal FastAPI app so the |
| `backend/tests/test_phase8_challenge.py` | 131 | «رحلة الطفل» Phase 3 tests — the per-child "current challenge" and its integration with the proactive coach. |
| `backend/tests/test_podcast_sentinels.py` | 179 | scripts/gen_podcasts_cron.py — trigger sentinels are outcomes, never task ids. `if tid:` used to run before `elif tid == "STALE_SOURCE"`, so the… |
| `backend/tests/test_primary_budget.py` | 183 | Primary-provider monthly spend ceiling tests. The app is free forever, so the paid primary path (DeepSeek) needs its own |
| `backend/tests/test_print_pack.py` | 86 | /print/ramadan — the Ramadan program as A4 sheets (routers/print_pack.py), read from the program itself. |
| `backend/tests/test_privacy_policy_route.py` | 54 | Regression tests for GET /privacy-policy. The endpoint is a Google Play requirement, and on 2026-07-27 it was serving a |
| `backend/tests/test_privacy_policy_truth.py` | 323 | The privacy policy must say what the code does — and keep saying it. Until 2026-10-04 docs/privacy-policy.md said child profiles and progress stayed |
| `backend/tests/test_privacy_retention.py` | 499 | What the privacy policy promises about retention and redaction, enforced. Each test pins one sentence of docs/privacy-policy.md to the code behind it: |
| `backend/tests/test_program.py` | 259 | Program router tests — Phase 2 curriculum endpoints. Validates: |
| `backend/tests/test_program_banks.py` | 472 | Family programs (Ramadan · prayer journey · milestones) are content banks with a validator that must have teeth in the right place. |
| `backend/tests/test_programs_api_doc.py` | 38 | MOBILE_API.md §11 documents every family-program endpoint. The mobile build is written from that document alone, so an endpoint missing |
| `backend/tests/test_programs_birth_month.py` | 152 | The optional birth month on a child profile (schema v34). It is what times the milestone reminders and the Prayer Journey's entry, so it |
| `backend/tests/test_programs_milestones.py` | 457 | The proactive milestones: the cards a parent sees, and the one push a month ahead. The listing is about timing (birth month vs band fallback, the… |
| `backend/tests/test_programs_north_star.py` | 27 | A Ramadan «تمّ» and a Prayer Journey started are parenting acts. The weekly report's North Star counts families who did one real parenting |
| `backend/tests/test_programs_prayer_journey.py` | 414 | «رحلة الصلاة» — tracks, stages, the child's tasks in the mission loop, graduation. Two families of tests. The first is the program's own rules: who… |
| `backend/tests/test_programs_privacy.py` | 191 | Every row the family programs keep is reachable by the delete paths. Two paths (PR #26): deleting one child (DELETE /api/children/{id} — |
| `backend/tests/test_programs_ramadan.py` | 668 | «رمضان العائلة» over HTTP — the calendar, the day, the ladder, the marks, the card. The dates are the hard part, so most tests pin the clock… |
| `backend/tests/test_programs_review_fixes.py` | 489 | Regressions for the PR #32 review — each one began as a reproduction script (/tmp/review-pr32/probe/) that showed the bug; here it asserts the fix. |
| `backend/tests/test_progress_upsert_key.py` | 172 | ترقية التقدّم تطابق القيد الفريد: (device_id, child_id, lesson_id). القيد في الإنتاج كان (device_id, lesson_id): صفٌّ واحد لكل (جهاز، درس) مهما |
| `backend/tests/test_push_credentials.py` | 72 | Regression tests for Firebase credential loading in push_sender. On 2026-07-27 push notifications were dead in production: backend/secrets is |
| `backend/tests/test_push_token_cooldown.py` | 332 | The push-token takeover (PR #26 review, round 3). The attack: someone who knows a device id mints a session (no proof needed |
| `backend/tests/test_question_survival.py` | 231 | كل سؤال يجب أن يخرج بأثر — الطبقة التي كانت تُسقط 10.9% من الأسئلة صامتةً. قياس على الإنتاج يوم 2026-08-13: 176 من 1,617 سؤالًا (10.9%) بلا أي صف… |
| `backend/tests/test_quick_wins.py` | 66 | 1. Initially, there are no children in the DB. |
| `backend/tests/test_quiz_answer_positions.py` | 212 | The correct answer must not sit in a predictable slot. The app renders quiz options in file order and never shuffles them |
| `backend/tests/test_quranic_linguistics_service.py` | 318 | Tests for quranic_linguistics_service — Bahouth MCP client, caching, fallback. These tests mock the HTTP layer (httpx.AsyncClient) so they never hit… |
| `backend/tests/test_rate_limit_identity.py` | 224 | Rate-limit identity tests — the bucket key must not collapse to the IP. RateLimitMiddleware runs BEFORE AuthMiddleware (Starlette's add_middleware |
| `backend/tests/test_real_traffic.py` | 218 | app/core/real_traffic.py — which devices are test traffic, and the metric scripts that leave them out (weekly dashboard, gap report, campaign report;… |
| `backend/tests/test_redaction_v2.py` | 246 | A2 / P4 / A6 (PR #26 review): child-name redaction, in both directions. Every model call is redacted since PR #26, so the matcher's mistakes became |
| `backend/tests/test_referral_fingerprint.py` | 167 | Production traffic arrives Cloudflare → nginx → app, so the TCP peer is the |
| `backend/tests/test_release_hardening.py` | 190 | Release-hardening tests (audit M4, M5, M6, H6 rest). |
| `backend/tests/test_repair_device_twins.py` | 213 | ops/tools/repair_device_twins.py — the one-off backlog repair. Dry run is the default and must not be able to write; --apply folds only what |
| `backend/tests/test_reply_language.py` | 98 | The answer comes back in the language the parent wrote in. Measured, not assumed: 40% of the people who use the assistant are on |
| `backend/tests/test_reranker_floor.py` | 175 | The reranker no longer hands back an irrelevant unit just to avoid an empty list. Before: `filtered or kept[:1]` ("never return nothing"). A question… |
| `backend/tests/test_retrieval_age_reach.py` | 106 | The age filter must narrow ranking, not decide reachability. `retrieve_relevant_units` filters the vector leg to the child's own age band |
| `backend/tests/test_retrieval_age_span.py` | 212 | Wrong-childhood material must not reach a parent's answer. The vector leg has always been filtered to the child's band, but BM25 never |
| `backend/tests/test_retrieval_domain_fusion.py` | 131 | Several domains must read as one search over their union, not N searches. `retrieve_hybrid` used to give every domain its own vector / band-free / |
| `backend/tests/test_retrieval_embed_once.py` | 56 | Audit M7: one embedding per distinct query text per request. retrieve_hybrid runs domains × queries × two vector legs, plus each leg's |
| `backend/tests/test_review_en_parity.py` | 680 | The English-content gate: what it parses, what it stamps, and when a stamp dies. `ops/tools/review_en_parity.py` replaced a signature nobody was ever… |
| `backend/tests/test_review_en_parity_proof.py` | 149 | Mixed-size actual responses may prove exact current fields, never a fake cache. |
| `backend/tests/test_review_en_parity_transport.py` | 237 | The transport under the review gate: an operator can bound a run. `post()` used to hardcode 8 attempts and a 600-second request, so a review |
| `backend/tests/test_route_guards.py` | 219 | Every route, walked (PR #26 final review, item 9). Replaces the hand-written list of protected routes: the routes are read from |
| `backend/tests/test_route_policy.py` | 396 | Explicit inventory and effective guards, without invoking protected handlers. This is a drift gate, not a claim that every public endpoint needs auth… |
| `backend/tests/test_safety.py` | 166 | Safety-layer unit tests — the project's most important behavior. |
| `backend/tests/test_safety_valve.py` | 106 | Cloud safety-valve tests — the hard-capped DeepSeek last-resort fallback. The valve must stay SHUT unless all of: flag on, key present, primary is not |
| `backend/tests/test_search.py` | 57 | Curriculum search endpoint tests — GET /api/program/search. Additive v1 endpoint: substring search across published lessons, paths, |
| `backend/tests/test_security_headers.py` | 59 | Security headers on every response (app/middleware/security_headers.py). |
| `backend/tests/test_send_update_push.py` | 87 | ops/scripts/send_update_push.py — nudge only the devices that need it. The first version sent to every token ever registered: people already on the |
| `backend/tests/test_sensitive_content.py` | 150 | What child memory must never keep (PR #26 review F6). The reviewer's probe table, row for row (Egyptian euphemisms, conjugations, |
| `backend/tests/test_seo.py` | 57 | Smoke tests for public SEO pages added to backend/app/routers/seo.py. |
| `backend/tests/test_source_line_hygiene.py` | 101 | A reference_info that is not a source must never reach the parent. The value is rendered as «📚 المصدر». 33 of the 1,122 units hold something that |
| `backend/tests/test_sse_keepalive.py` | 63 | SSE keep-alive while the model is silent (audit M13, server side). The app drops a stream that sends nothing for 45 s. A slow first token |
| `backend/tests/test_stale_collection_handle.py` | 89 | A collection deleted underneath the cached handle must not take the app down. `_collection` is a process-wide singleton. When the collection it… |
| `backend/tests/test_story_auth.py` | 101 | /api/program/story used to be reachable by anyone, and it generates on the model. Locking it outright would 401 every build already on Play the… |
| `backend/tests/test_story_cache.py` | 78 | Story pre-generation cache tests (growth plan §5.1). The cache must: only serve gendered variants, personalize the hero name, |
| `backend/tests/test_story_events.py` | 120 | «صورة حيّة» experiment — the remote switch and the events endpoint. Pins: |
| `backend/tests/test_story_experiment.py` | 146 | «صورة حيّة» — the numbers behind the weekly section and the month-end verdict (app/services/story_experiment.py, ops/scripts/story_motion_verdict.py). |
| `backend/tests/test_story_privacy.py` | 42 | P6 (PR #26 review): the story feature sent the child's name to the model. On a cache miss the live prompt said «بطل القصة طفل اسمه «يوسف»». It now… |
| `backend/tests/test_stream_cancellation.py` | 71 | SSE stream worker cancellation (audit H6). The worker thread used to keep reading the whole answer after the parent |
| `backend/tests/test_tafsir_service.py` | 748 | Tests for tafsir_service — MCP client, caching, and fallback behaviour. These tests mock the HTTP layer (httpx.AsyncClient) so they never hit the |
| `backend/tests/test_taxonomy.py` | 42 | Taxonomy + age/domain normalization tests. |
| `backend/tests/test_taxonomy_unification.py` | 84 | The age vocabulary has one home. Three copies of the age-group list used to live in the codebase — taxonomy, |
| `backend/tests/test_telemetry_migrations.py` | 388 | Additive telemetry migrations on synthetic, isolated SQLite fixtures only. |
| `backend/tests/test_telemetry_usage_completeness.py` | 329 | Every paid call is an llm_calls row WITH token counts. Production, October 2026: 26 DeepSeek rows had NULL prompt/completion tokens |
| `backend/tests/test_tier_routing.py` | 161 | Phase 1 tests — cloud quality tier plumbing. Covers: <think> stripping across chunk boundaries, tier routing policy, |
| `backend/tests/test_tip_cards.py` | 183 | Daily tip cards: card tip_N.png must show tip N. The autoposter (PCC agent tutor_post) posts tip N's text from «## أ) بنك كروت |
| `backend/tests/test_token_hardening.py` | 206 | Audit H5 (rest): hashed bearer tokens, sliding expiry, log-safe device ids. |
| `backend/tests/test_translate_kb_only.py` | 65 | translate_knowledge_base.py: `--only` translates exactly the named units, and the Ollama key is read from ~/projects/email-twin/.env inside Python,… |
| `backend/tests/test_triage_feedback_fixes.py` | 119 | اختبارات: triage feedback fixes |
| `backend/tests/test_turn_races_live.py` | 348 | Turn races on a real uvicorn server — PR #24 round 2 (probes2). test_answer_reliability drives the handlers in-process and closes the body |
| `backend/tests/test_twin_fold_contract.py` | 107 | PR #26 × PR #29 (final review, item 10) — whichever lands second keeps it. #29 folds a childless twin device into the family's device when the twin |
| `backend/tests/test_v2_gate_check.py` | 383 | اختبارات بوابات 2.0.0 الأربع (نطاق 4 أسابيع لـ D7 + sustained، حدّ N≥150، توكنات pre-v37، كشف `⚠️` في الكتالوج، والقراءة فقط) |
| `backend/tests/test_v36_honest_counter.py` | 117 | Schema v36 — the honest weekly counter's shared migration (نور والقناديل). One migration adds both objects Phase 0 needs: |
| `backend/tests/test_value_tracking.py` | 580 | Tests for the «ميزان العادات» value-tracking API. Uses a minimal FastAPI app with the value_tracking router only, plus the |
| `backend/tests/test_weekly_dashboard_ops_base.py` | 74 | The weekly dashboard reads LLM metrics from the app it runs inside (127.0.0.1), not through the public URL that answered 403. |
| `backend/tests/test_weekly_funnel_report.py` | 809 | اختبارات: weekly funnel report |
| `backend/tests/test_weekly_plan.py` | 229 | «خطة الأسبوع» — the bank's integrity and the plan's behaviour (schema v30). |
| `backend/tests/test_weekly_plan_marks.py` | 256 | A weekly plan you can tick (نور والقناديل, Phase 3) — schema v36's `weekly_plan_marks` behind PUT/DELETE /api/children/{id}/weekly-plan/marks and the… |

## 3) تطبيق الموبايل — `mobile/` (Flutter، حزمة `almorabbi`، Android-first)

الإصدار الحالي في `mobile/pubspec.yaml`: **1.0.74+119**؛ معرّف الحزمة `com.alsaba.almorabbi`. إدارة الحالة Riverpod، تنقّل `Navigator.push` عبر `core/app_routes.dart`. مجلد `features/` يقسم الشاشات بحسب الميزة:

| مجلد `lib/features/` | ما يحتويه |
|---|---|
| `adhkar/` | حزمة محتوى الأسرة (آيات/نصائح/أحاديث 281 عنصرًا) + إشعار محلي يومي واحد + المنطقة الزمنية |
| `agreement/` | الاتفاقية الأسرية للإعلام: شاشة الأب، شاشة الطفل، لوحة التوقيع، التصدير كصورة |
| `child_corner/` | «ركن الطفل»: مشهد ورق مقصوص بعد باب التسليم، قصة/لعبة اليوم، «شمعة وقتك» |
| `child_memory/` | «المربّي يعرف ابنك»: حقائق، متابعات، إثبات الجهاز، الخصوصية، حذف الحساب، مسح الهاتف |
| `coins/` | عملات محلية على الجهاز + العهود + الشارات الحصرية + مولّد القصص المخصّصة |
| `companion/` | «نور يتذكّر»: دماغ حتمي يختار جملة واحدة لـ«اليوم»، شخصية نور ووجهه ومتجره المحلي |
| `deeplink/` | روابط https://tg-api.alsaba.cloud/{go,l,p} إلى شاشات التطبيق |
| `family_road/` | «درب {الاسم}» (عالم الأسرة): طريق الأسرة، الأفق، ما أضأتموه |
| `feedback/` | شاشة الملاحظات (نص/صوت) وردود المسؤول |
| `games/` | 4 ألعاب تعليمية Flame (Data Defender, Emotion Maze, Healthy Hero, Tree of Deeds) + فهرس + غلاف مشترك |
| `handover/` | «باب التسليم»: تسليم الجهاز للطفل + سياسة السطوح العمرية (نسخة العميل من بوابة الخادم) + شاشة العودة |
| `home/` | مكوّنات تبويب «اليوم»: سماء، درب اليوم، بطاقات التركيز/السؤال/مهمة الطفل، التحية |
| `hub/` | تبويب «المزيد»: كتالوج الوجهات كبيانات + ورقة «أين أجد…؟» |
| `identity/` | Google Sign-In الاختياري «احفظ تقدّمك» |
| `journey/` | «رحلة الطفل»: معالم روحية محلية، حفظ القرآن، التحدي الحالي |
| `lanterns/` | «قناديل الأسبوع» وحصاد الجمعة من /api/family/week |
| `license/` | رخصة الإنترنت: شاشة الطفل (موقف واحد 3 إجابات) وشاشة الأب |
| `missions/` | بطاقة المهمة، تأكيد المساء، المعلّقة، كلمة طيبة |
| `offscreen/` | «بدائل بلا شاشة» (الوجهة التي تشير إليها بوابة العمر) |
| `onboarding/` | التهيئة الأولى (<90 ثانية للقيمة)، اختيار الأفاتار، شاشة «إيه الجديد؟» |
| `parent_day/` | ما يراه الأب عن اليوم + بطاقة يوم الطفل |
| `program/` | المنهج: مسارات/دروس/مشغّلات الوسائط/قصص/إعدادات/أطفال/تقدّم + مستودعات + كاش المنهج |
| `programs/` | برامج الأسرة: رمضان، سلّم الصيام، رحلة الصلاة، المراحل، بطاقة رمضان عائلتنا، لحظة العيد |
| `push/` | قنوات إشعارات Android وخدمة FCM |
| `quran/` | المصحف + قراءة مع استماع آية-آية + تفسير موثّق |
| `referral/` | الدعوة «أثر دعوتك» وإسناد التثبيت وبطاقة الفخر وعدّاد المجتمع |
| `reflections/` | ملاحظات تأمّل لكل درس (محلية) |
| `routine/` | «حِساب اليوم» (0–6) و«ميزان العادات» (7–18) + وضع الطفل (قفل PIN/حالة/سطح) |
| `screen_off/` | وضع الاستماع بشاشة مطفأة + تسجيل صوت الأب لقصة |
| `share/` | مشاركة اللحظات كصور PNG |
| `shell/` | هيكل التطبيق: 4 تبويبات سفلية |
| `stories/` | «صورة حيّة»: لوحات حيّة، سرد صوتي «اسمعها من نور»، مشاهد ورق مقصوص، تجربة A/B |
| `support/` | «ادعم المربّي» (Play Billing consumables) — يظهر فقط حين يفعّله الخادم |
| `tools/` | أدوات عبادة محلية: مسبحة، محوّل هجري |
| `tour/` | جولة أول تشغيل بتسليط ضوء (مكتوبة يدويًا) |
| `whats_new/` | «الجديد في التحديث» لمن لديهم التطبيق |

### mobile/lib/ — الجذر، الواجهة العامة، الحالة، الثيم، l10n

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/api/device_id_claim.dart` | 118 | The one-time claim of the install's device id, shared by every isolate. |
| `mobile/lib/api/tg_client.dart` | 3702 | Thin HTTP/SSE client for the Tutor Guardian backend. Implements the v1 contract in `MOBILE_API.md`: * `createSession()` → POST /api/chat/sessions *… |
| `mobile/lib/config/app_config.dart` | 43 | App-wide configuration constants. The base URL is read from a `--dart-define` so the same APK can target staging/production without code changes.… |
| `mobile/lib/core/analytics.dart` | 609 | Growth analytics — thin wrapper over the (previously declared-but-unwired) firebase_analytics so we can actually measure the Phase 0 funnel and the… |
| `mobile/lib/core/app_closer.dart` | 53 | Ending the app so that the next open is a fresh launch — and telling Android's backup that the app's data changed. Used once: after an account… |
| `mobile/lib/core/app_routes.dart` | 631 | Central route registry. The app navigates imperatively (`Navigator.push`) rather than through a declarative router — see the note below on why. The… |
| `mobile/lib/core/clock.dart` | 11 | The wall clock, as a provider — so a test can stand «اليوم» on a Friday or a Monday without waiting for one. Only what decides a day-of-week moment… |
| `mobile/lib/core/crash_triage.dart` | 63 | What to do with an error that reached a global handler. There is no `fatal` member on purpose. Anything that arrives at `FlutterError.onError` or… |
| `mobile/lib/core/e2e_probes.dart` | 91 | CI-only hooks for the emulator rehearsal — compiled OUT of every build that reaches a family. The phase-2 gate of «نور والقناديل» asks the emulator… |
| `mobile/lib/core/engagement_signal.dart` | 32 | A counter of "something worthwhile just happened", read by the navigation observer to tell a finished task apart from a dead end. Lives in its own… |
| `mobile/lib/core/failures.dart` | 148 | What a failure means to the reader — not what threw it. Both the UI (which message to show) and the data layer (whether a cached copy is a better… |
| `mobile/lib/core/haptics.dart` | 88 | Semantic haptics — call sites say *what happened*, not which motor pulse. Haptics were ten direct `HapticFeedback.*` calls in six files (games,… |
| `mobile/lib/core/horizon_attribution.dart` | 65 | horizon_to_action_48h` — did a tap on the horizon lead to a parenting act within two days? (عالم الأسرة, the «على الأفق» experiment's second half:… |
| `mobile/lib/core/local_only_files.dart` | 50 | Files the app writes for a moment and that must never reach a backup: a feedback voice note on its way to the server, an agreement image on its way… |
| `mobile/lib/core/motion.dart` | 46 | Reduce-motion support (UX_UI_ROADMAP §5). With the system "remove animations" setting on, Flutter already runs every AnimationController at 5% of its… |
| `mobile/lib/core/nav_observer.dart` | 242 | Navigation observer — the "where do users get lost?" probe. Multiple users reported getting lost inside the app. Rather than guess which of the ~40… |
| `mobile/lib/core/notification_permission_gate.dart` | 43 | One-shot notification permission ask, moved off the launch path to the moment it can be answered "yes" to: right after the FIRST completed lesson… |
| `mobile/lib/core/social_links.dart` | 54 | Where «المربّي الذكي» publishes, as links a parent can open. The URLs are taken from the accounts actually connected to the publishing pipeline — the… |
| `mobile/lib/core/sound_fx.dart` | 221 | Soft interface sounds — «أصوات ناعمة بلا موسيقى». Five short sounds, synthesised by `ops/tools/gen_sfx.py` (filtered noise, a soft click, a breath of… |
| `mobile/lib/firebase_options.dart` | 28 | Generated from google-services.json — do not edit manually. Re-generate by running: flutterfire configure |
| `mobile/lib/l10n/app_ar.arb` |  | نصوص الواجهة بالعربية (المصدر الأساسي للترجمة) |
| `mobile/lib/l10n/app_en.arb` |  | نصوص الواجهة بالإنجليزية |
| `mobile/lib/l10n/app_localizations.dart` | 11594 | Callers can lookup localized strings with an instance of AppLocalizations returned by `AppLocalizations.of(context)`. Applications need to include… |
| `mobile/lib/l10n/app_localizations_ar.dart` | 6855 | The translations for Arabic (`ar`). |
| `mobile/lib/l10n/app_localizations_en.dart` | 6907 | The translations for English (`en`). |
| `mobile/lib/l10n/content_direction.dart` | 134 | Text direction for **content**, decided by the content itself. Why this is not `Directionality.of(context)` The app chrome takes its direction from… |
| `mobile/lib/l10n/l10n_global.dart` | 46 | Access to [AppLocalizations] for code that runs outside the widget tree (API-client errors, state notifiers, background services).… |
| `mobile/lib/main.dart` | 769 | classes: TutorGuardianApp, ForceUpdateScreen, _AppBootstrapper, _ParentApp, _SplashScreen |
| `mobile/lib/models/api_models.dart` | 306 | Data Transfer Objects matching the v1 contract in `MOBILE_API.md`. All classes use additive decoding — unknown fields are silently ignored, which is… |
| `mobile/lib/models/enums.dart` | 162 | Stable enums hard-coded from `backend/app/core/taxonomy.py` and `MOBILE_API.md`. These wire values are part of the v1 contract; client never… |
| `mobile/lib/screens/chat_screen.dart` | 1041 | Main chat screen — Phase 3 deliverable. Layout: * AppBar : "🛡️ المربي الذكي" + badge with turn count. * Context chip : the optional behavior_type,… |
| `mobile/lib/screens/home_screen.dart` | 513 | Home tab — "اليوم". Pure composition over existing providers. Three blocks, then a divider, then everything else. «مش عارف أبدأ منين» was the first… |
| `mobile/lib/state/chat_notifier.dart` | 1118 | Riverpod state holder for the chat screen. Owns: * The list of in-memory [ChatMessageUI] bubbles (user + assistant). * The currently selected… |
| `mobile/lib/state/connectivity_provider.dart` | 41 | Streams the device's online/offline status. Exposes a single Riverpod provider that the UI can `ref.watch` to render an "غير متصل" banner. The first… |
| `mobile/lib/theme/app_colors.dart` | 40 | The palette as a [ThemeExtension] (UX_UI_ROADMAP DS5). `context.colors` is the way new and migrated widgets read colours. It goes through `Theme.of`,… |
| `mobile/lib/theme/app_palette.dart` | 337 | The two palettes, and which one is live right now. «لدي اقتراح و اتمنى ان تطبقوه ألا و هو الوضع الداكن. فهو اريح للعين» — #fb_e7402eaa, 15 Aug 2026.… |
| `mobile/lib/theme/app_theme.dart` | 414 | Theme + colour tokens for المربي الذكي. Redesigned 2026-06 to a playful, vibrant (Duolingo-style) identity: vivid teal + amber, warm cream… |
| `mobile/lib/theme/bundled_fonts.dart` | 38 | Fonts ship inside the app (UX_UI_ROADMAP DS8). `google_fonts` used to download Cairo, Amiri Quran and Tajawal on first use. An offline first launch… |
| `mobile/lib/theme/design_tokens.dart` | 150 | Design tokens for the playful (Duolingo-style) redesign (`kVisualUnificationVersion = 'visual_unification_v2'`), `DomainStyle.glyph` (`BrandIcon`), gradients, radii, shadows and motion constants. No emoji graphics (`VISUAL_UNIFICATION_2_0.md`). |
| `mobile/lib/widgets/app_status_banner.dart` | 106 | One app-wide status line for "you are offline" and "this is a saved copy" (UX_UI_ROADMAP E2). Offline used to be signalled only inside the chat, and… |
| `mobile/lib/widgets/message_bubble.dart` | 744 | One chat bubble. User bubbles are a teal gradient at the end (left in RTL); assistant bubbles are white cards at the start with Noor beside them… — ومنذ 1.0.76 صف نسخ/مشاركة تحت إجابة نور المكتملة (`ShareService.plainAnswer/shareAnswer`) |
| `mobile/lib/widgets/safety_banner.dart` | 114 | Safety banner rendered above (or inline with) an assistant message. Driven ONLY by the structured `AssistantReply` fields — never by parsing the… |
| `mobile/lib/widgets/ui/animated_progress_bar.dart` | 71 | Chunky rounded progress bar with an animated fill and a subtle top "shine" strip — Duolingo style. |
| `mobile/lib/widgets/ui/art_image.dart` | 70 | One bundled illustration, whatever its format. The «ورق مقصوص» art set (assets/svg/) is SVG; a path that still names a raster (a story cover, an… |
| `mobile/lib/widgets/ui/bouncy_button.dart` | 139 | Wraps any child with a press-down scale bounce (Duolingo feel). Announced as a button (UX_UI_ROADMAP DS9): a bare GestureDetector is a tap target a… |
| `mobile/lib/widgets/ui/brand_glyph.dart` | 190 | BrandGlyph — the app's icon set («جولة الحرفة», item 1; «ورق مقصوص», 2026-10-14). No emoji as graphics: a colored Noto emoji is a foreign… |
| `mobile/lib/widgets/ui/celebration_overlay.dart` | 335 | How loud a celebration is («نور والقناديل» phase 1 — مستويات الاحتفال). One celebration API, two volumes, so that a quiet "well done" and a full… |
| `mobile/lib/widgets/ui/community_proof_card.dart` | 55 | Community social-proof card (Phase 3) — «X أب يربّون بثقة معنا». Fetches the public aggregate stats once and shows a warm, non-numeric-heavy line… |
| `mobile/lib/widgets/ui/count_up_text.dart` | 28 | Integer that counts up from 0 to [value] on first build. |
| `mobile/lib/widgets/ui/directional_chevron.dart` | 34 | A "go forward" chevron that points the way the language reads. The codebase had accumulated three different icons for this one meaning —… |
| `mobile/lib/widgets/ui/emoji_hero.dart` | 32 | Squircle tile with a big emoji on a tinted background — the app's illustration system (no image assets needed). |
| `mobile/lib/widgets/ui/empty_state.dart` | 113 | Friendly empty/error state: big drawn icon (or legacy emoji), bold title, soft subtitle, optional action button. Replaces the bare icon+text… |
| `mobile/lib/widgets/ui/error_retry_view.dart` | 42 | A failure the parent can act on, instead of the exception's toString(). Three screens rendered `errorGeneric(e.toString())`, which put… |
| `mobile/lib/widgets/ui/loading_view.dart` | 149 | Loading states that say something when the wait runs long (UX_UI_ROADMAP E3, E4). A bare centred spinner reads the same at one second and at fifty,… |
| `mobile/lib/widgets/ui/night_sky.dart` | 281 | Night-sky ambience shared by the bedtime surfaces. The bedtime routine, the story bookshelf and the story reader each carried their own copy of these… |
| `mobile/lib/widgets/ui/noor_mascot.dart` | 30 | «نور» — the app mascot, still and at rest: the calm face of the «ورق مقصوص» set (assets/svg/noor/noor_calm.svg), on a transparent ground. For a Noor… |
| `mobile/lib/widgets/ui/paper_lantern.dart` | 186 | A paper-cut lantern («ورق مقصوص», STYLE.md 2026-10-14), drawn in code. The shape is the reference icon `icons/lantern.svg` on its 48×48 grid — ring,… |
| `mobile/lib/widgets/ui/progress_ring.dart` | 101 | Animated circular progress ring with a center slot (emoji or %). |
| `mobile/lib/widgets/ui/skeleton.dart` | 63 | Shimmering placeholder box used while content loads. |
| `mobile/lib/widgets/ui/stat_chip.dart` | 102 | Pill chip with a drawn icon + value + label, on a tinted background. Used for the streak / lessons / badges / coins stats. |
| `mobile/lib/widgets/ui/two_column_rows.dart` | 46 | Two columns whose rows are as tall as their tallest cell. The replacement for `GridView.count(childAspectRatio: …)` on Home. A fixed aspect ratio… |

### mobile/lib/features/adhkar/

حزمة محتوى الأسرة (آيات/نصائح/أحاديث 281 عنصرًا) + إشعار محلي يومي واحد + المنطقة الزمنية

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/adhkar/data/family_adhkar.dart` | 175 | Family parenting content — Qur'an verses, hadith and practical parenting tips used for the daily notifications. 281 items: 142 verses, 124 tips and… |
| `mobile/lib/features/adhkar/screens/adhkar_screen.dart` | 245 | Browsing surface for the parenting-content pack. 281 attributed items — 142 ayahs, 124 tips, 15 hadiths — have shipped in `family_adhkar.ar.json`… |
| `mobile/lib/features/adhkar/services/local_timezone.dart` | 62 | Working out which timezone "6 AM" means. `tz.initializeTimeZones()` loads the database. It does **not** set `tz.local`, which stays UTC until… |
| `mobile/lib/features/adhkar/services/notification_service.dart` | 777 | Notification Service — one daily local notification, on-device. It used to be three: adhkar at 06:00 and 19:00, plus a Qur'an wird reminder at 17:00… |

### mobile/lib/features/agreement/

الاتفاقية الأسرية للإعلام: شاشة الأب، شاشة الطفل، لوحة التوقيع، التصدير كصورة

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/agreement/agreement_export.dart` | 71 | Turning the signed agreement into something that goes on a wall. The point of the export is that the agreement stops living in the app. A media plan… |
| `mobile/lib/features/agreement/agreement_screen.dart` | 287 | The family media agreement, from the parent's side. This screen is a release blocker for the agreement gate: since the server refuses every child… |
| `mobile/lib/features/agreement/child_agreement_screen.dart` | 200 | The agreement, from the child's side — the only surface that opens before one is signed. Each clause is acknowledged on its own. That is the whole… |
| `mobile/lib/features/agreement/signature_pad.dart` | 131 | A finger signature, drawn on a CustomPaint. No package for this. `signature_pad` would be a new dependency for what is a list of points and a Path,… |

### mobile/lib/features/child_corner/

«ركن الطفل»: مشهد ورق مقصوص بعد باب التسليم، قصة/لعبة اليوم، «شمعة وقتك»

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/child_corner/child_corner_screen.dart` | 835 | «ركن الطفل» — after the hand-over gate, one paper scene for the child. The game study (scratch/game-study/REPORT.md, the «كبير» phone of… |
| `mobile/lib/features/child_corner/corner_picks.dart` | 111 | What the corner offers today: one story and one game, chosen by the day. Not a shelf. A child handed a list of nineteen books and four games spends… |
| `mobile/lib/features/child_corner/corner_scene.dart` | 207 | The corner's paper: a sky, two cut hills and a valley, and the cards that stand in it — «ورق مقصوص» (assets/svg/STYLE.md) drawn in code, with flat… |
| `mobile/lib/features/child_corner/corner_story_view.dart` | 274 | The corner's story: the day's story, read one page at a time on paper. Deliberately not the bookshelf's reader. That screen is the parent's: it ends… |
| `mobile/lib/features/child_corner/paper_candle.dart` | 353 | «شمعة وقتك» — the child's time as a paper candle that grows shorter. The study's rule (scratch/game-study/REPORT.md): time is shown as a candle,… |

### mobile/lib/features/child_memory/

«المربّي يعرف ابنك»: حقائق، متابعات، إثبات الجهاز، الخصوصية، حذف الحساب، مسح الهاتف

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/child_memory/data/local_wipe.dart` | 136 | Clearing the phone after its account was deleted (MOBILE_API §10). The server has erased the account; this erases what the phone kept: cached… |
| `mobile/lib/features/child_memory/data/memory_models.dart` | 539 | Data shapes for «المربّي يعرف ابنك» — MOBILE_API.md §9–§10. Decoding is additive (unknown fields are ignored, missing ones fall back), the same rule… |
| `mobile/lib/features/child_memory/data/memory_repository.dart` | 200 | «المربّي يعرف ابنك» over [TgClient] — typed, and with the proof rule applied per call (MOBILE_API §9.0). Protected calls go through… |
| `mobile/lib/features/child_memory/data/pending_deletion.dart` | 85 | Finishing an account deletion the app did not see through (MOBILE_API §10; PR #36 reviews). Two ways a deletion can be left half-done on the phone: *… |
| `mobile/lib/features/child_memory/data/placeholder_names.dart` | 361 | Putting the child's name back into memory text — on the device only — and taking exactly those names out again before anything is sent. The server… |
| `mobile/lib/features/child_memory/device_proof/device_proof_service.dart` | 413 | Device proof — the FCM challenge behind every protected memory route (MOBILE_API.md §9.0.1). The server proves that a session holds the phone by… |
| `mobile/lib/features/child_memory/providers/memory_providers.dart` | 117 | Riverpod wiring for «المربّي يعرف ابنك». tgClientProvider ─► memoryRepositoryProvider ├─ memorySettingsProvider (switch; null = no memory on this… |
| `mobile/lib/features/child_memory/screens/account_deletion_screen.dart` | 705 | Settings → Privacy → «حذف الحساب» (MOBILE_API §10; Google Play's in-app account deletion requirement). The order on screen is the order of a careful… |
| `mobile/lib/features/child_memory/screens/child_memory_screen.dart` | 786 | «ما يعرفه المربّي عن <اسم>» — MOBILE_API §9.2, §9.3. What the assistant remembers about one child, and every control over it: confirm or reject a… |
| `mobile/lib/features/child_memory/screens/privacy_screen.dart` | 247 | Settings → «الخصوصية وبياناتك»: every control over the family's data in one place (MOBILE_API §9.2, §9.6, §10). * the memory switch, and «ما يعرفه… |
| `mobile/lib/features/child_memory/widgets/followup_sheet.dart` | 738 | «جرّبت النصيحة؟ نفعت؟» — the follow-up sheet (MOBILE_API §9.4). One sheet for both ways in: the Today card (with the follow-up already in hand, and… |
| `mobile/lib/features/child_memory/widgets/memory_errors.dart` | 54 | One calm, translated sentence for a failed memory or protected action. |
| `mobile/lib/features/child_memory/widgets/memory_switch_tile.dart` | 111 | The memory switch — device-wide, for every child (MOBILE_API §9.2). Switching OFF never needs a proof and is never paused: stopping must always work,… |
| `mobile/lib/features/child_memory/widgets/personalised_chip.dart` | 70 | «مخصّص لأحمد» under an answer that used child memory (MOBILE_API §9.1). Tapping it opens «ما يعرفه المربّي عن أحمد»: the parent sees — and can… |
| `mobile/lib/features/child_memory/widgets/proof_views.dart` | 275 | The three things a parent may see while a protected action waits on the device proof (MOBILE_API §9.0.1): it is under way, it is paused until a time,… |
| `mobile/lib/features/child_memory/widgets/today_followup_card.dart` | 195 | «المتابعة» on Today — plan §1.2, the loop that brings a parent back. Shows one due follow-up (the active child's first, else the oldest of any child,… |
| `mobile/lib/features/child_memory/widgets/today_weekly_plan_card.dart` | 648 | «خطة الأسبوع» on Today — plan §1.3 (MOBILE_API §9.5). One focus, three small actions, one act of worship together, one lesson — for the active child,… |

### mobile/lib/features/coins/

عملات محلية على الجهاز + العهود + الشارات الحصرية + مولّد القصص المخصّصة

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/coins/coins_providers.dart` | 69 | Riverpod wiring for the on-device coins ledger. |
| `mobile/lib/features/coins/coins_screen.dart` | 278 | Coins screen — balance, daily claim, and how-to-earn. The reward currency's "spend" side ships later (redeemables), so this screen focuses on the… |
| `mobile/lib/features/coins/coins_service.dart` | 352 | Coins — a light, fully on-device reward currency. Earned by: daily login (streak-aware), achievement badges, and small in-app actions. Persisted in… |
| `mobile/lib/features/coins/covenant_screen.dart` | 526 | Rewards belong to a child. Child 0 is the fallback for a family that has not created a profile yet — it keeps its own list rather than sharing one. |
| `mobile/lib/features/coins/covenant_service.dart` | 194 | Covenants — the one thing coins buy, and it happens off the screen. A covenant is a real reward a parent has agreed to: a trip to the park, an extra… |
| `mobile/lib/features/coins/exclusive_badges_screen.dart` | 140 | Cosmetic badges — earned, not bought. This was a store: six badges at 100–300 coins each. Selling cosmetics for a currency the app itself mints is… |
| `mobile/lib/features/coins/story_screen.dart` | 218 | Custom story generator — spend coins to create a personalized, value-teaching Arabic story starring the active child. Generation runs on the local… |

### mobile/lib/features/companion/

«نور يتذكّر»: دماغ حتمي يختار جملة واحدة لـ«اليوم»، شخصية نور ووجهه ومتجره المحلي

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/companion/data/companion_store.dart` | 361 | What «نور» keeps on the phone («نور يتذكّر», phase 2). The server already remembers facts and follow-ups; this is the small, device-only memory the… |
| `mobile/lib/features/companion/logic/answer_step.dart` | 257 | «سأجرّبها مع …» — the one step a parent can promise from an answer (NOOR_WAL_QANADIL_PLAN, phase 4, «المساعد»). The assistant answers in a fixed… |
| `mobile/lib/features/companion/logic/companion_brain.dart` | 485 | «نور يتذكّر» — which one line Noor says when the parent opens «اليوم». Pure and deterministic: the same inputs give the same line, no randomness and… |
| `mobile/lib/features/companion/providers/companion_providers.dart` | 319 | Wiring for «نور يتذكّر»: real data in, one [CompanionLine] out. Every source is optional. A failure, an older server or a slow network simply removes… |
| `mobile/lib/features/companion/widgets/noor_face.dart` | 157 | NoorFace — «نور» in the «ورق مقصوص» paper-cut set (2026-10-14). The face used to be drawn in code on a night-navy disc; the owner chose a paper-cut… |
| `mobile/lib/features/companion/widgets/noor_presence.dart` | 245 | NoorPresence — «نور» in a moon window (NOOR_WAL_QANADIL_PLAN, Phase 1). A framed, breathing character rather than a loose illustration: * a… |
| `mobile/lib/features/companion/widgets/noor_today_header.dart` | 482 | «نور يتذكّر» — Noor's one line at the top of «اليوم». Replaces the static greeting row. Shows Noor, a salutation for the time of day, and one… |

### mobile/lib/features/deeplink/

روابط https://tg-api.alsaba.cloud/{go,l,p} إلى شاشات التطبيق

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/deeplink/deep_link_handler.dart` | 231 | Deep link handler — Phase 0/1. Wires app_links to route incoming https://tg-api.alsaba.cloud/{go,l,p} links into the app. The navigatorKey is… |

### mobile/lib/features/family_road/

«درب {الاسم}» (عالم الأسرة): طريق الأسرة، الأفق، ما أضأتموه

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/family_road/logic/horizon.dart` | 283 | «على الأفق» — the gates ahead on «درب {الاسم}» (عالم الأسرة). Pure and deterministic, like Noor's brain: the same server answers give the same gates,… |
| `mobile/lib/features/family_road/logic/road_past.dart` | 124 | «ما أضأتموه» — what is behind «أنتم هنا» on «درب {الاسم}», and where «أنتم هنا» itself stands. Only what was done: this week's lit days… |
| `mobile/lib/features/family_road/providers/family_road_providers.dart` | 137 | Wiring for «درب {الاسم}» and the «على الأفق» strip (عالم الأسرة). Everything comes from answers the app already asks for — `/api/programs` (age,… |
| `mobile/lib/features/family_road/screens/family_road_screen.dart` | 663 | «درب {الاسم}» — the family's paper road with the active child (عالم الأسرة, the middle scenario the maintainer approved on 2026-10-15). It opens on what is… |
| `mobile/lib/features/family_road/widgets/family_road_entry.dart` | 74 | The way into «درب {الاسم}» from the Learn tab: one quiet row at the top of the paths list (it scrolls away with them; it never pins). |
| `mobile/lib/features/family_road/widgets/gate_bits.dart` | 222 | What a gate says and where it goes — shared by «درب {الاسم}» and the «على الأفق» strip on Today, so the two never word a gate differently. |
| `mobile/lib/features/family_road/widgets/horizon_strip.dart` | 137 | «على الأفق» — one slim line on Today's hills naming the nearest gate of «درب {الاسم}» («رمضان بعد ١١٦ يومًا»، «سنّ السابعة بعد ٤ أشهر»); a tap opens… |

### mobile/lib/features/feedback/

شاشة الملاحظات (نص/صوت) وردود المسؤول

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/feedback/feedback_screen.dart` | 200 | In-app feedback — the parent sends the maintainer a written note and/or a voice note. Posts to `/api/feedback/app` (public). Voice is optional and degrades… |
| `mobile/lib/features/feedback/widgets/feedback_replies_section.dart` | 120 | Replies the maintainer has written back, shown above the compose form. This is the half of the feedback loop that was missing: a parent could report a… |

### mobile/lib/features/games/

4 ألعاب تعليمية Flame (Data Defender, Emotion Maze, Healthy Hero, Tree of Deeds) + فهرس + غلاف مشترك

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/games/data_defender/data_defender_game.dart` | 32 | Redesigned Data Defender educational mini-game. The 50 questions moved to `assets/content/games/data_defender.ar.json` on 2026-08-13 so they can be… |
| `mobile/lib/features/games/data_defender/game_screen.dart` | 14 | Entry screen for the Data Defender mini-game. |
| `mobile/lib/features/games/emotion_maze/emotion_maze_game.dart` | 32 | Redesigned Emotion Maze educational mini-game. The 50 questions moved to `assets/content/games/emotion_maze.ar.json` on 2026-08-13 so they can be… |
| `mobile/lib/features/games/emotion_maze/game_screen.dart` | 14 | Entry screen for the Emotion Maze mini-game. |
| `mobile/lib/features/games/games_catalog.dart` | 70 | The four educational games, as data. The games were reachable only from inside a lesson, and only from a lesson in the matching domain — three levels… |
| `mobile/lib/features/games/healthy_hero/game_screen.dart` | 14 | Entry screen for the Healthy Hero mini-game. |
| `mobile/lib/features/games/healthy_hero/healthy_hero_game.dart` | 35 | Smart Habits educational mini-game (formerly "Healthy Hero"). Reframed to teach daily habits, responsibility, social/emotional and life skills — NO… |
| `mobile/lib/features/games/screens/games_screen.dart` | 126 | «الألعاب التعليمية» — one place to hand a child something to play. When the `game` budget for the day is spent, the catalogue does not disappear and… |
| `mobile/lib/features/games/shared/edu_game_models.dart` | 504 | Base educational game models and shared configuration. This is the redesign layer for the four domain-specific mini-games. It replaces the old… |
| `mobile/lib/features/games/shared/edu_game_shell.dart` | 866 | Generic educational game shell that hosts level selection and the game runner. Each domain-specific game only needs to provide its theme and a… |
| `mobile/lib/features/games/shared/edu_game_ui.dart` | 603 | Shared level selection screen, pause overlay, and result dialog for the redesigned educational mini-games. |
| `mobile/lib/features/games/tree_of_deeds/game_screen.dart` | 14 | Entry screen for the Tree of Deeds mini-game. |
| `mobile/lib/features/games/tree_of_deeds/tree_of_deeds_game.dart` | 32 | Redesigned Tree of Deeds educational mini-game. The 50 questions moved to `assets/content/games/tree_of_deeds.ar.json` on 2026-08-13 so they can be… |

### mobile/lib/features/handover/

«باب التسليم»: تسليم الجهاز للطفل + سياسة السطوح العمرية (نسخة العميل من بوابة الخادم) + شاشة العودة

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/handover/child_hand_back.dart` | 92 | The child's last screen: the session is over, and the device goes back. Every child surface used to end differently. The mission card closes the app;… |
| `mobile/lib/features/handover/child_surface_policy.dart` | 152 | Which child surfaces a band may be handed — the client's copy of the server's age gate. The server is the authority:… |
| `mobile/lib/features/handover/handover_doors.dart` | 366 | The two doors of «باب التسليم», drawn in the «ورق مقصوص» style. Two ivory paper leaves with a mashrabiya window cut into each, meeting under one… |
| `mobile/lib/features/handover/handover_gate_screen.dart` | 489 | «باب التسليم» — the one place a parent hands the device to a child. It replaces a column of nine buttons under the habit list, four of which opened a… |

### mobile/lib/features/home/

مكوّنات تبويب «اليوم»: سماء، درب اليوم، بطاقات التركيز/السؤال/مهمة الطفل، التحية

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/home/greeting.dart` | 45 | Time-aware greeting copy («نور والقناديل» phase 1 — النصوص). The greeting used to be one string for every hour of the day, and it told a parent on… |
| `mobile/lib/features/home/experiment/child_home_experiment.dart` | 90 | Client arm resolution (`ChildHomeArm`: `'v2'` / `'ab'` sticky FNV-1a32 / `'classic'`) and week-1 onboarding expansion markers (`child_home_v2`). |
| `mobile/lib/features/home/widgets/child_weekly_home.dart` | 395 | Child-centric Weekly Home body (`ChildWeeklyHome`, M2): 200%-text fold-safe header + `TodayFocusCard` first, weekly loop, birth-month nudge, and Friday harvest banner. |
| `mobile/lib/features/home/widgets/daily_gift_moment.dart` | 167 | «هدية اليوم» as a moment, not a line (جولة الحرفة, item 2). The child's login reward used to appear as a muted sentence — a coin flow the parent… |
| `mobile/lib/features/home/widgets/home_app_bar.dart` | 65 | Home tab AppBar, cut down to two actions. The coin chip moved into the stats row, and feedback/settings now live behind the «المزيد» tab — five… |
| `mobile/lib/features/home/widgets/home_community_note.dart` | 60 | A quiet closing line on Home: «X أب وأمّ يربّون بثقة معنا — لست وحدك». This used to be a tinted, bordered card on Home and was dropped when the… |
| `mobile/lib/features/home/widgets/home_shortcuts_grid.dart` | 108 | Secondary destinations, compressed into a 2×2 grid. These were four full-width cards competing head-on with the primary action. The tile styling… |
| `mobile/lib/features/home/widgets/home_stats_row.dart` | 88 | Stats: lit weeks / open-book completed lessons / medal badges / coin balance — drawn glyphs (جولة الحرفة), not emoji. «أسابيع مضيئة» (نور والقناديل,… |
| `mobile/lib/features/home/widgets/sky_band.dart` | 606 | «السماء» behind Noor on «اليوم» (plan phase 2, SkyBand): a paper-cut sky that follows the local hour — dawn, day, maghrib, night — cut in the same… |
| `mobile/lib/features/home/widgets/today_ask_block.dart` | 172 | «اسأل المربّي» — the second of the three «اليوم» blocks. The coach tip leads it because the tip is what starts conversations: 28% of questions to the… |
| `mobile/lib/features/home/widgets/today_child_block.dart` | 185 | «مهمة الطفل» — the third of the three «اليوم» blocks. What it shows is decided by the content banks, not by this widget: * **4-6 · 7-9 · 10-12 ·… |
| `mobile/lib/features/home/widgets/today_focus_card.dart` | 409 | The home tab's single primary action: resume the path the child is actually in the middle of, or — when there is none — the nudge that starts the… |
| `mobile/lib/features/home/widgets/today_loop_cards.dart` | 61 | The weekly loop on «اليوم», between ① and ② (plan §1.2–§1.3): the follow-up first (it is time-sensitive), then the week's plan. Neither card has a… |
| `mobile/lib/features/home/widgets/today_rituals_row.dart` | 97 | The two daily rituals — Qur'an and the routine/habit tracker — that used to be bottom-nav tabs. They sit directly under the primary action because… |
| `mobile/lib/features/home/widgets/today_road.dart` | 343 | «درب اليوم» (plan phase 2): the day's three stops — ① خطوة ابنك، ② اسأل المربّي، ③ مهمة الطفل — as three stations on one short paper road down the… |
| `mobile/lib/features/home/widgets/today_section.dart` | 98 | The scaffolding of the «اليوم» tab: a titled block, and the divider below the three primary blocks. The tab was cut to three blocks (2026-10) because… |

### mobile/lib/features/hub/

تبويب «المزيد»: كتالوج الوجهات كبيانات + ورقة «أين أجد…؟»

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/hub/data/hub_catalog.dart` | 222 | What lives in the «المزيد» hub, and how it is grouped (5 core groups, 15–16 tiles). Everything outside the daily loop… |
| `mobile/lib/features/hub/screens/hub_screen.dart` | 76 | «المزيد» — one predictable place for everything outside the daily loop. The app had 40+ screens behind five tabs and two overloaded app bars, and… |
| `mobile/lib/features/hub/widgets/help_sheet.dart` | 148 | «أين أجد…؟» — a list of the questions people actually get stuck on, each answering itself by navigating straight to the destination. A first-run tour… |
| `mobile/lib/features/hub/widgets/hub_group_card.dart` | 129 | One titled section of the hub, rendered as a grid of tiles (respects `hiddenIds`). |

### mobile/lib/features/identity/

Google Sign-In الاختياري «احفظ تقدّمك»

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/identity/identity_entry.dart` | 16 | ثابت `kGoogleAccountEntryEnabled` (حاليًا `true`): يُظهر/يخفي مدخل «حساب Google» في الإعدادات والمركز وورقة المساعدة (أُطفئ في 1.0.76 وعاد في 1.0.77) |
| `mobile/lib/features/identity/identity_screen.dart` | 229 | «احفظ تقدّمك» — optional Google Sign-In (Phase 1.2). Framed as protecting the parent's effort, not as a marketing funnel. The sign-in is opt-in;… |
| `mobile/lib/features/identity/identity_service.dart` | 289 | Identity service — Phase 1.2 optional Google Sign-In. Links a Google account to the anonymous device_id on the backend so child data and referral… |

### mobile/lib/features/journey/

«رحلة الطفل»: معالم روحية محلية، حفظ القرآن، التحدي الحالي

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/journey/data/challenges.dart` | 37 | «رحلة الطفل» — the current-challenge catalogue (Phase 3). Keys MUST match the backend `CHALLENGE_TOPICS` (coach_service.py). The active challenge… |
| `mobile/lib/features/journey/data/journey_milestones.dart` | 171 | «رحلة الطفل» — the spiritual-milestone catalogue (Phase 1, local). A curated, ordered list of Islamic milestones a parent can mark for their child.… |
| `mobile/lib/features/journey/data/journey_store.dart` | 135 | «رحلة الطفل» — local-only, per-child milestone log (Phase 1). Backed by [SharedPreferences]. Unlike reflection notes (which are device-global), the… |
| `mobile/lib/features/journey/data/memorization_store.dart` | 59 | «رحلة الطفل» — per-child Quran memorization tracking (Phase 4). The Quran feature itself tracks nothing memorized; this is a small, local, per-child… |
| `mobile/lib/features/journey/data/tasmee_store.dart` | 182 | «تسميع مع الوالد» — what a parent marked while their child recited (docs/TASMEE_WITH_PARENT.md): slips by kind, per child, local, with the review date. |
| `mobile/lib/features/journey/providers/journey_providers.dart` | 145 | «رحلة الطفل» providers — per-child milestone log (local, Phase 1). Hierarchy: sharedPreferencesProvider (existing, onboarding_providers) │ ▼… |
| `mobile/lib/features/journey/screens/child_journey_screen.dart` | 816 | «رحلة الطفل» — the per-child keepsake timeline (Phase 1). Shows the milestones a parent has logged for one child (a treasured record they build over… |
| `mobile/lib/features/journey/screens/quran_memorization_screen.dart` | 235 | «رحلة الطفل» — Quran memorization checklist (Phase 4). A per-child list of the 114 surahs the parent can mark as memorized. Memorizing the FIRST… |
| `mobile/lib/features/journey/screens/tasmee_screen.dart` | 432 | «تسميع مع الوالد»: the child recites, the parent follows the mushaf and taps the word where the child slipped (dropped/added/swapped/hesitated); summary, then save. |
| `mobile/lib/features/journey/widgets/child_journey_card.dart` | 99 | «رحلة الطفل» — Home entry card (Phase 1). Modeled on [CoachTipCard]: self-hides until the active child is loaded (and when [kJourneyEnabled] is off).… |
| `mobile/lib/features/journey/widgets/milestone_icon.dart` | 35 | Shows a milestone's custom badge illustration when one exists ([milestoneBadgeAsset]), otherwise falls back to its [emoji]. Used in the journey… |

### mobile/lib/features/lanterns/

«قناديل الأسبوع» وحصاد الجمعة من /api/family/week

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/lanterns/data/family_week.dart` | 172 | «قناديل الأسبوع» — `GET /api/family/week` (MOBILE_API §12) as the app reads it. One lantern per **local day** that holds at least one parenting act —… |
| `mobile/lib/features/lanterns/data/lantern_copy.dart` | 37 | The words for the week's acts — one place, so the acts sheet, the Friday card and the shared image say the same thing. |
| `mobile/lib/features/lanterns/data/lantern_seen_store.dart` | 36 | How many of this week's lanterns this phone has already shown lit. A lantern lights — a short glow and one success tap — only the first time it is… |
| `mobile/lib/features/lanterns/providers/lantern_providers.dart` | 61 | Wiring for «قناديل الأسبوع» (نور والقناديل, phase 3). One request feeds three places on «اليوم»: the lantern string under ①, the «أسابيع مضيئة» chip,… |
| `mobile/lib/features/lanterns/widgets/friday_harvest.dart` | 341 | «حصاد الجمعة» — Noor's Friday card (نور والقناديل, phase 3). Gathered on the phone from `/api/family/week` alone: the week's lanterns light again one… |
| `mobile/lib/features/lanterns/widgets/lantern_row.dart` | 201 | A row of the week's paper lanterns ([PaperLantern] — one lantern shape in the whole app), lighting one after another, and the dashed «next» lantern.… |
| `mobile/lib/features/lanterns/widgets/week_acts_sheet.dart` | 151 | The week's acts behind the lanterns — opened from the lantern string. Grouped by local day, oldest first: one lit lantern per act, its kind («درس»،… |
| `mobile/lib/features/lanterns/widgets/week_lantern_string.dart` | 206 | «قناديل الأسبوع» under ① on «اليوم» (نور والقناديل, phase 3). Only the lanterns this week has lit — one per local day with a parenting act, seven at… |

### mobile/lib/features/license/

رخصة الإنترنت: شاشة الطفل (موقف واحد 3 إجابات) وشاشة الأب

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/license/child_license_screen.dart` | 261 | The internet licence, as a child sees it: one situation, three answers. There is no text field here and there will not be one. Scenario training does… |
| `mobile/lib/features/license/parent_license_screen.dart` | 309 | The parent's half of the internet licence. Two things live here, and the second is the one that matters. **The talking points.** For each situation… |

### mobile/lib/features/mawaqif/

«موقف بقرار»: النموذج والمخزن المحلي، الشاشات الخمس، بطاقة «اليوم»

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/mawaqif/data/mawqif.dart` | 150 | «موقف بقرار» — the model (situation, three responses, hadith card, idea, step), the per-child device store `tg.mawaqif.v1`, and `nextMawqif`. Refuses anything the screen cannot render in full. |
| `mobile/lib/features/mawaqif/screens/mawqif_screen.dart` | 308 | «موقف بقرار» — five short screens: the situation → the three responses → what happens now and later → the hadith, its harder words and the idea → the step («سأجرّبها» opens the lesson's «متى» sheet; the promise is a follow-up with source `mawqif`). |
| `mobile/lib/features/mawaqif/widgets/today_mawqif_card.dart` | 170 | «موقف بقرار» on Today: the next step for the active child's band. Hides itself while loading, on any failure, on an older server, and once every step was gone through. No number. |

### mobile/lib/features/missions/

بطاقة المهمة، تأكيد المساء، المعلّقة، كلمة طيبة

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/missions/child_mission_screen.dart` | 353 | The mission card — sixty seconds of screen that buys fifteen minutes away from it. This is rule 1 of the constitution made literal: the screen is a… |
| `mobile/lib/features/missions/mission_confirmations.dart` | 219 | The evening confirmation, independent of the screen that starts it. Two ways a confirmed prayer card's coins used to be lost for good: * the parent… |
| `mobile/lib/features/missions/pending_missions_screen.dart` | 368 | The evening screen: every mission a child says they did, waiting on a parent who was not there when they said it. This is the second half of the… |
| `mobile/lib/features/missions/praise_header.dart` | 219 | «كلمة طيبة» — the note a parent sends with the evening confirmation, shown to the child the next time they hold the phone. Three rules from the plan… |
| `mobile/lib/features/missions/today_mission_row.dart` | 308 | «مهمة اليوم» on Today, for the parent — no handover needed: tell the child, mark it done, send a kind word. |

### mobile/lib/features/offscreen/

«بدائل بلا شاشة» (الوجهة التي تشير إليها بوابة العمر)

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/offscreen/offscreen_activities_screen.dart` | 189 | «بدائل بلا شاشة» — the section the age gate points at. The refusal shown to the parent of a child under two carried three activities inside its own… |

### mobile/lib/features/onboarding/

التهيئة الأولى (<90 ثانية للقيمة)، اختيار الأفاتار، شاشة «إيه الجديد؟»

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/onboarding/data/onboarding_storage.dart` | 93 | Onboarding storage — single source of truth for "first-launch" state. Backed by [SharedPreferences] (plain text on Android, NSUserDefaults on iOS).… |
| `mobile/lib/features/onboarding/providers/onboarding_providers.dart` | 202 | Riverpod providers for the onboarding flow + active-child wiring. Providers: * sharedPreferencesProvider (FutureProvider — boot once, cached) *… |
| `mobile/lib/features/onboarding/screens/avatar_picker_sheet.dart` | 100 | Avatar emoji picker — modal bottom sheet. Shows a grid of curated, child-friendly emojis grouped by theme. Tapping an emoji returns it via… |
| `mobile/lib/features/onboarding/screens/onboarding_screen.dart` | 1286 | Onboarding screen — first-launch flow, redesigned for <90s to first value. Two swipeable pages (age question → instant value): 1. One question only:… |
| `mobile/lib/features/onboarding/screens/update_splash_screen.dart` | 180 | Update splash screen — «إيه الجديد؟» shown once after each version bump. Shows the welcome hero — the «ورق مقصوص» scene with a proud «نور» in its sky… |
| `mobile/lib/features/onboarding/widgets/welcome_hero.dart` | 74 | The welcome hero — the «ورق مقصوص» scene with «نور» in its sky. assets/svg/art/onboarding_welcome.svg (360×240) is an emerald card: hills, an open… |

### mobile/lib/features/parent_day/

ما يراه الأب عن اليوم + بطاقة يوم الطفل

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/parent_day/child_day_card.dart` | 159 | The child's day, on the «اليوم» tab. The plan puts the parent panel in this tab (item 2.4). What shipped was a button on the routine screen instead —… |
| `mobile/lib/features/parent_day/parent_day_screen.dart` | 340 | What a parent sees about today. Screen minutes and listening minutes are two rows, never one total. That is the whole editorial position of the… |

### mobile/lib/features/program/

المنهج: مسارات/دروس/مشغّلات الوسائط/قصص/إعدادات/أطفال/تقدّم + مستودعات + كاش المنهج

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/program/data/backup_service.dart` | 193 | Backup service — P1.3 data export/import (local-only). Handles JSON export/import of user's local-only data: - reflections (notes per lesson) -… |
| `mobile/lib/features/program/data/badges.dart` | 91 | Achievements / badges — P1 launch item #4 (local, derived). Badges are NOT stored — they are computed purely from the child's existing progress… |
| `mobile/lib/features/program/data/child_name.dart` | 40 | What a child's name has to be, wherever the parent types one. The server takes 1–80 characters after trimming (`ChildCreateRequest` and… |
| `mobile/lib/features/program/data/curriculum_cache.dart` | 112 | A last-known-good copy of the curriculum, for when the network is not there. The app was online-only: a parent opening it on the metro, or on a phone… |
| `mobile/lib/features/program/data/favorites_storage.dart` | 94 | Favorites storage — P1 launch item #1 (local-only). Backed by [SharedPreferences]. Stores two sets of IDs: * lesson IDs that the user marked as… |
| `mobile/lib/features/program/data/models.dart` | 284 | Curriculum content models — Phase 4 (Flutter UI). These mirror the JSON shapes served by the backend… |
| `mobile/lib/features/program/data/program_repository.dart` | 179 | Repository for the curriculum program layer (Phase 4). This is the only layer that knows about the [TgClient] and the `routers/program.py` wire… |
| `mobile/lib/features/program/data/progress_models.dart` | 201 | Phase 5 models — children + lesson progress. These mirror the wire format from `routers/children.py` + `routers/program.py::patch_lesson_progress`. |
| `mobile/lib/features/program/data/progress_repository.dart` | 53 | Repository for Phase 5 (children + progress). Wraps [TgClient] and keeps the [ChildProgressBundle] shape pure-typed for the UI. |
| `mobile/lib/features/program/data/review_prompt.dart` | 61 | Gentle, one-time "rate the app" prompt — shown only AFTER a few positive moments (e.g. logging a milestone), never on first use, and never twice.… |
| `mobile/lib/features/program/data/settings_repository.dart` | 53 | Phase 7 repository — list / update / reset on /api/children. |
| `mobile/lib/features/program/data/story_models.dart` | 309 | «وقفة» — the moment inside a story where Noor stops and asks the child what they would do, before the page that answers it. Optional per story… |
| `mobile/lib/features/program/models/flashcard_deck.dart` | 44 | Flashcard deck content — served by `GET /api/program/asset-content/{id}`. |
| `mobile/lib/features/program/models/lesson_assets.dart` | 63 | What the server actually served, per medium — `{requested, podcast, video, infographic, report, data_table}`, each a language code or null. The… |
| `mobile/lib/features/program/models/quiz_deck.dart` | 96 | Quiz content models — served by `GET /api/program/asset-content/{id}` for assets whose `kind` is `quizzes` (per `lesson_assets_provider.dart`). Wire… |
| `mobile/lib/features/program/models/search_result.dart` | 47 | One curriculum search hit — served by `GET /api/program/search`. |
| `mobile/lib/features/program/providers/backup_provider.dart` | 15 | Backup service provider — P1.3 data export/import. Wraps [BackupService] so it can be consumed via Riverpod. |
| `mobile/lib/features/program/providers/favorites_provider.dart` | 74 | Favorites provider — P1 launch item #1 (local-only). Wraps [FavoritesStorage] so the rest of the app can use Riverpod to consume favorites state… |
| `mobile/lib/features/program/providers/lesson_assets_provider.dart` | 66 | Language for lesson media (podcast, video), sent as `?lang=` to `/lesson-assets`. **Derived from the app language — it is not a setting of its own.**… |
| `mobile/lib/features/program/providers/program_providers.dart` | 192 | Riverpod providers for the curriculum program layer (Phase 4). Hierarchy: tgClientProvider ── (existing) global, from chat_notifier │ ▼… |
| `mobile/lib/features/program/providers/progress_providers.dart` | 280 | Riverpod providers for Phase 5 (children + lesson progress). Hierarchy: tgClientProvider (existing) │ ▼ progressRepositoryProvider ──… |
| `mobile/lib/features/program/providers/settings_providers.dart` | 274 | Phase 7 providers — children list, update, and progress reset. Hierarchy: tgClientProvider ── (existing, in progress_providers)… |
| `mobile/lib/features/program/screens/add_child_screen.dart` | 265 | Add a new child to the device's roster. Re-uses [AvatarPickerSheet] and the [AgeGroup] enum, but unlike [OnboardingScreen] it does NOT flip the… |
| `mobile/lib/features/program/screens/badges_screen.dart` | 175 | Achievements screen (P1 #4) — shows earned + locked badges and week lanterns derived from progress. |
| `mobile/lib/features/program/screens/bedtime_routine_screen.dart` | 490 | The bedtime adhkar, three to say before sleep. Until 2026-10 this screen stood in front of every story: a tap on a book opened five taps of adhkar… |
| `mobile/lib/features/program/screens/children_list_screen.dart` | 472 | Children list — Phase 8-B multi-child switcher. Reached from: * the [ActiveChildChip] in the PathsScreen AppBar * a "Switch child" row in the… |
| `mobile/lib/features/program/screens/data_table_screen.dart` | 162 | Fetches a lesson data-table (CSV) and renders it as a vertical list of cards (one card per row, "header: value" pairs) — readable on a phone in RTL… |
| `mobile/lib/features/program/screens/edit_child_screen.dart` | 346 | Edit child screen — same fields as onboarding, but PATCHes the existing child instead of creating a new one. |
| `mobile/lib/features/program/screens/favorites_screen.dart` | 384 | Favorites screen — P1 launch item #1 (local-only). Shows all favorited lessons and daily tips in a simple list. Tapping a lesson navigates to the… |
| `mobile/lib/features/program/screens/flashcards_screen.dart` | 346 | Interactive flashcards viewer — replaces the Phase-4 placeholder. Loads one or more decks (their ids come from the lesson-assets metadata), merges… |
| `mobile/lib/features/program/screens/infographic_screen.dart` | 154 | Full-screen, zoomable viewer for a lesson infographic image. Adds a rotate-screen toggle and a download button that stamps the app logo onto the… |
| `mobile/lib/features/program/screens/lesson_screen.dart` | 1191 | Lesson screen — reads a single lesson, renders: 1. Hero (title + estimated minutes + warning chips) 2. Status chip (Phase 5 — driven by… |
| `mobile/lib/features/program/screens/path_detail_screen.dart` | 1161 | Path detail screen — shows the full path description + the lessons as «درب المسار» (a zigzag of stations on a paper road under a paper sky), then a… |
| `mobile/lib/features/program/screens/paths_screen.dart` | 479 | Path list screen — "مساراتي" tab. Reads [pathsListProvider] (filtered by the current [selectedAgeGroupProvider]). Renders a scrollable list of cards,… |
| `mobile/lib/features/program/screens/podcast_player_screen.dart` | 357 | Podcast player — P0.1 (third placeholder to be replaced). Loads a remote MP3 URL, plays it via `just_audio`, and exposes a minimal transport:… |
| `mobile/lib/features/program/screens/quiz_game_screen.dart` | 626 | Quiz Game Screen — "اختبر معلوماتك التربوية" A gamified quiz experience with timer, score tracking, and educational feedback after each question. |
| `mobile/lib/features/program/screens/quiz_screen.dart` | 604 | Quiz player — P0.1 (replaces the second AssetPlaceholderScreen). Loads one or more quiz decks (their ids come from lesson-assets metadata), merges… |
| `mobile/lib/features/program/screens/report_screen.dart` | 67 | Fetches a lesson report (markdown) and renders it. |
| `mobile/lib/features/program/screens/search_screen.dart` | 259 | Curriculum-wide search results for a query (≥2 chars). Empty for shorter. |
| `mobile/lib/features/program/screens/settings_screen.dart` | 932 | Settings screen — Phase 7. Pushed onto the navigator from an IconButton in the PathsScreen AppBar. The NavigationBar stays 2 tabs (المساعد /… |
| `mobile/lib/features/program/screens/story_bookshelf_screen.dart` | 202 | شاشة رف القصص: فلاتر العمر وسطر نور، والعرض نفسه صار `MagicShelf` («رف الحكايات») بدل شبكة «ورق مقصوص» |
| `mobile/lib/features/program/screens/story_reader_screen.dart` | 1610 | The story reader — «ورق مقصوص» (2026-10, docs/STORIES_AUDIT.md). A story is a short stack of paper leaves: 1. Noor's opening leaf — the cover scene,… |
| `mobile/lib/features/program/screens/video_player_screen.dart` | 469 | Video Player Screen — improved with better controls visibility and thumbnail support |
| `mobile/lib/features/program/services/bedtime_audio_service.dart` | 27 | Keeps the device awake while a story or the bedtime adhkar is open, then lets it sleep again. This file used to hold `BedtimeAudioService` too — a… |
| `mobile/lib/features/program/widgets/active_child_chip.dart` | 118 | Phase 8-B — shows the active child (emoji + name) in the PathsScreen AppBar. Tap → opens [ChildrenListScreen] to switch / add a child. |
| `mobile/lib/features/program/widgets/coach_tip_card.dart` | 239 | Proactive parenting coach card — the day's tip on Home. Fetches a personalized (or gracefully-degraded) coach tip for the active child via… |
| `mobile/lib/features/program/widgets/follow_us_row.dart` | 174 | «تابعنا» — one quiet row of the app's own channels, in Settings. A row of chips rather than three more full-width settings rows: these are the least… |
| `mobile/lib/features/program/widgets/full_moon_moment.dart` | 340 | «اكتمل البدر» (NOOR_WAL_QANADIL_PLAN, phase 4): the moment a path is finished. Noor's crescent fills to a full moon in 1.2 s — an emerald shadow… |
| `mobile/lib/features/program/widgets/next_step_sheet.dart` | 166 | The one concrete thing to do with the child tonight. «كيفية تنفيذ القيمة» — a parent on Facebook, 17 Aug 2026, listing what he could not work out… |

### mobile/lib/features/programs/

برامج الأسرة: رمضان، سلّم الصيام، رحلة الصلاة، المراحل، بطاقة رمضان عائلتنا، لحظة العيد

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/programs/data/programs_models.dart` | 1806 | Typed views of the family-programs payloads (MOBILE_API §11). Every string a screen renders comes from these payloads — the server picks the right… |
| `mobile/lib/features/programs/providers/programs_providers.dart` | 172 | Riverpod wiring for the family programs (MOBILE_API §11). programsOverviewProvider GET /api/programs — null when the server has no programs (404, or… |
| `mobile/lib/features/programs/screens/fasting_ladder_screen.dart` | 405 | «سلّم الصيام» — one child's fasting ladder, with the safety guidance always on screen (`GET /api/children/{id}/ramadan/fasting`). Order is safety… |
| `mobile/lib/features/programs/screens/milestones_screen.dart` | 360 | The proactive milestones — school entry, the age of discernment, the first prayer lessons at seven, first fasting, puberty, the first phone… (`GET… |
| `mobile/lib/features/programs/screens/prayer_journey_screen.dart` | 999 | «رحلة الصلاة» — the parent's view (`GET /api/children/{id}/prayer-journey`). The family loop the plan is built on: the parent starts the journey, the… |
| `mobile/lib/features/programs/screens/programs_screen.dart` | 237 | «برامج الأسرة» — every family program, per child (`GET /api/programs`). One family-wide Ramadan card (the calendar is the family's), then one card… |
| `mobile/lib/features/programs/screens/ramadan_day_screen.dart` | 67 | Any day of «رمضان العائلة» (`GET /api/children/{id}/ramadan/days/{day}`). Two reasons to open a day that is not today: tomorrow's challenge may need… |
| `mobile/lib/features/programs/screens/ramadan_recap_screen.dart` | 223 | «رمضان عائلتنا» — the family's card and its in-app counters (`GET /api/programs/ramadan/recap`). Two halves that never mix. The card (from Eid on) is… |
| `mobile/lib/features/programs/screens/ramadan_screen.dart` | 875 | «رمضان العائلة» for one child (`GET /api/children/{id}/ramadan/today`). What the screen shows follows the family's calendar: upcoming the countdown,… |
| `mobile/lib/features/programs/widgets/birth_month_field.dart` | 275 | The optional birth month on a child's profile (MOBILE_API §11.1). A month, never a day: it is enough to time the milestone reminders and the Prayer… |
| `mobile/lib/features/programs/widgets/child_prayer_card.dart` | 261 | «صلاتي اليوم» — the child's Prayer Journey tasks, inside child mode (`GET/POST /api/value-tracking/child-mode/prayer/*`, Child-Bearer). Lives on the… |
| `mobile/lib/features/programs/widgets/eid_moment.dart` | 463 | «عيدكم مبارك» (NOOR_WAL_QANADIL_PLAN, phase 5): on the first open of Eid al-Fitr, once a Hijri year, a quiet moment over «اليوم» — Noor happy under a… |
| `mobile/lib/features/programs/widgets/prayer_stage_moment.dart` | 102 | The quiet moment when the parent moves the Prayer Journey up a stage (NOOR_WAL_QANADIL_PLAN, phase 4): «انتقل أحمد إلى «الوضوء». أعانكم الله وتقبّل… |
| `mobile/lib/features/programs/widgets/program_widgets.dart` | 806 | Building blocks shared by the family-programs screens. Every colour comes from `context.colors` (the palette ThemeExtension), so the screens follow… |
| `mobile/lib/features/programs/widgets/programs_home_card.dart` | 163 | The «برامج الأسرة» entry on «اليوم» — below the three blocks, never above. A card, not a fourth numbered stop: the three blocks stay the page's three… |
| `mobile/lib/features/programs/widgets/programs_text.dart` | 59 | One-line summaries shared by the Home card and the programs list, so the two never describe the same state in different words. |
| `mobile/lib/features/programs/widgets/ramadan_recap_card.dart` | 117 | «رمضان عائلتنا» as a shareable image — the program's viral surface. Built from the server's `card` and nothing else: the headline, the lines (already… |
| `mobile/lib/features/programs/widgets/ramadan_widgets.dart` | 944 | The pieces of «رمضان العائلة»: a day's card, the family's «تمّ» marks, the fasting summary and the moon-sighting settings. Marks are tick-only. A day… |

### mobile/lib/features/push/

قنوات إشعارات Android وخدمة FCM

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/push/notification_channels.dart` | 66 | The Android notification channels this app sends on. The backend has been setting `channel_id` on every push it sends for a year, and the app never… |
| `mobile/lib/features/push/push_service.dart` | 346 | Push service — Phase 1.1 re-engagement loop. Requests notification permission, gets the FCM token, and uploads it to the backend so the server can… |

### mobile/lib/features/quran/

المصحف + قراءة مع استماع آية-آية + تفسير موثّق

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/quran/models/reciters.dart` | 21 | Quran reciters available for the listen feature. `id` is the everyayah.com data folder; the per-ayah URL is… |
| `mobile/lib/features/quran/models/surah_names.dart` | 14 | أسماء السور الـ114 |
| `mobile/lib/features/quran/providers/quran_providers.dart` | 93 | Provides the entire Quran JSON loaded from assets. Key is chapter number as string (e.g. "1"), value is list of verses. |
| `mobile/lib/features/quran/providers/tafsir_providers.dart` | 200 | Tafsir of an ayah, fetched from the backend that already had it. `/api/tafsir/{surah}/{ayah}` has proxied `mcp.tafsir.net` with a 30-day cache since… |
| `mobile/lib/features/quran/screens/quran_screen.dart` | 182 | Reverent header illustration — the first-surah milestone of the «ورق مقصوص» set, its own emerald card on either theme. |
| `mobile/lib/features/quran/screens/surah_reading_screen.dart` | 522 | The daily wird (portion) target — at least this many verses. |
| `mobile/lib/features/quran/widgets/tafsir_sheet.dart` | 287 | The bottom sheet that finally shows what an ayah means. Direction is decided by the content, not by the chrome: tafsir arrives in Arabic for every… |

### mobile/lib/features/referral/

الدعوة «أثر دعوتك» وإسناد التثبيت وبطاقة الفخر وعدّاد المجتمع

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/referral/community_providers.dart` | 32 | Public aggregate community counts — «X أب وأمّ يربّون بثقة معنا». A provider rather than a fetch inside the widget, because two surfaces show this… |
| `mobile/lib/features/referral/invite_screen.dart` | 306 | «أثر دعوتك» — the dedicated referral surface (Phase 0.2, reframed 2026-10). Leads with what the parent's sharing has already done — «وصل المربّي إلى… |
| `mobile/lib/features/referral/pride_invite_card.dart` | 144 | «ادعُ صديقًا» at pride moments only (§6.4 growth plan). The referral ask fires when the parent has something to be proud of — a ≥7-day streak —… |
| `mobile/lib/features/referral/referral_service.dart` | 135 | Referral service — the mobile half of the Phase 0.2 growth loop. On first run it reads the Google Play Install Referrer (free attribution, no… |

### mobile/lib/features/reflections/

ملاحظات تأمّل لكل درس (محلية)

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/reflections/data/reflection_storage.dart` | 109 | Phase 8-C — local-only reflection notes. Backed by [SharedPreferences]. One note per lesson, capped at [kMaxNoteLength] characters. The structure is… |
| `mobile/lib/features/reflections/providers/reflections_providers.dart` | 76 | Phase 8-C providers — reflection notes (local-only). Hierarchy: sharedPreferencesProvider (existing, in onboarding_providers) │ ▼… |
| `mobile/lib/features/reflections/widgets/reflection_note_badge.dart` | 47 | Phase 8-C — small "note exists" badge for the lesson tile in [PathDetailScreen]. Renders nothing when the user has no reflection on the lesson. |
| `mobile/lib/features/reflections/widgets/reflection_note_card.dart` | 272 | Phase 8-C — "ملاحظاتي" surface inside the lesson screen. Read mode (default): shows the saved note + edit/delete actions. Edit mode: text field +… |

### mobile/lib/features/routine/

«حِساب اليوم» (0–6) و«ميزان العادات» (7–18) + وضع الطفل (قفل PIN/حالة/سطح)

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/routine/models/habit_models.dart` | 497 | Habit models for «ميزان العادات» — age-dynamic habit tracker. |
| `mobile/lib/features/routine/models/routine_models.dart` | 172 | Daily routine models for «حِساب اليوم». |
| `mobile/lib/features/routine/providers/child_mode_providers.dart` | 722 | Stable error codes surfaced through [ChildModeState.error]. The UI maps these to localized messages; anything else is shown raw. |
| `mobile/lib/features/routine/providers/habit_providers.dart` | 77 | Riverpod providers for the habit tracker (ميزان العادات). |
| `mobile/lib/features/routine/providers/routine_providers.dart` | 78 | Riverpod providers for the daily routine tracker. |
| `mobile/lib/features/routine/screens/child_mode_lock_screen.dart` | 280 | Lock screen used to enter/exit child mode. PIN is verified locally. |
| `mobile/lib/features/routine/screens/daily_routine_screen.dart` | 1235 | Daily routine tab — «حِساب اليوم». Lists today's sleep/feed/diaper events and lets the parent add new ones. |
| `mobile/lib/features/routine/screens/habit_child_mode_screen.dart` | 355 | The child-facing self-reporting screen. Very simple, large buttons, one tap with a few seconds to undo, no edit/delete once sent. |
| `mobile/lib/features/routine/screens/habit_customize_screen.dart` | 237 | Parent screen for customizing a child's habit templates. Allows adding new custom habits per category, archiving/unarchiving existing ones, while… |
| `mobile/lib/features/routine/screens/parenting_insights_screen.dart` | 640 | Insights + monthly report (`B20`) screen; infant summary hidden on older bands when empty. |
| `mobile/lib/features/routine/services/child_mode_secure_storage.dart` | 112 | Secure storage helpers for child-mode session tokens and PIN. |
| `mobile/lib/features/routine/widgets/child_mode_gate.dart` | 49 | Who holds the device, decided before anything of the parent's is built. The root of the app under the boot checks (main.dart). While child mode is on… |
| `mobile/lib/features/routine/widgets/child_mode_shell.dart` | 161 | The frame around every child surface (UX_UI_ROADMAP §4.3, E6). The child surface used to look like the parent app with fewer buttons, so a… |
| `mobile/lib/features/routine/widgets/habit_week_strip.dart` | 226 | The 7-day habit strip and the streak badge (UX_UI_ROADMAP §3.2–3.3). A row of seven dots answers "is this week better than last?" at a glance: filled… |
| `mobile/lib/features/routine/widgets/quiet_time_bar.dart` | 114 | Time, shown to a child without a number. Rule 7 of the constitution is a calm design, and rule 1.3d of the plan says this specifically: a candle… |

### mobile/lib/features/screen_off/

وضع الاستماع بشاشة مطفأة + تسجيل صوت الأب لقصة

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/screen_off/audio_tag.dart` | 46 | Why this app has no background audio, and must not gain it casually. On 2026-08-16 I added `just_audio_background` so the screen-off listening mode… |
| `mobile/lib/features/screen_off/narration_store.dart` | 155 | A parent's voice, kept on the device. The app already generates the story; this records a parent reading it once so a child can hear it in their… |
| `mobile/lib/features/screen_off/record_narration_screen.dart` | 166 | Recording a story in a parent's voice. One take, kept on the phone. The screen shows the story text large enough to read aloud from, a record button,… |
| `mobile/lib/features/screen_off/screen_off_picker_screen.dart` | 167 | What to listen to with the screen dark. Plan item 2.2b names three audio sources and rules out a fourth: no TTS, because there is no Arabic voice… |
| `mobile/lib/features/screen_off/screen_off_player_screen.dart` | 249 | Listening with the screen dark. This is the mode that resolves the product's central tension. Screen time is visual exposure; audio with the display… |

### mobile/lib/features/share/

مشاركة اللحظات كصور PNG

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/share/share_service.dart` | 160 | Central share helper — the one place that turns any widget into a shared PNG with a reverent, pre-filled «تذكير» message and an install link. Every… |
| `mobile/lib/features/share/shareable_moment_card.dart` | 462 | Generic shareable "moment" card — the viral surface for every emotional moment in the app (milestones, badges, quiz wins, path completion, Quran… |

### mobile/lib/features/shell/

هيكل التطبيق: 4 تبويبات سفلية

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/shell/root_scaffold.dart` | 263 | The app shell: four bottom-navigation tabs. It used to be five, and the fourth one **renamed itself based on the active child's age** («حساب اليوم»… |
| `mobile/lib/features/shell/root_tab.dart` | 49 | Bottom-navigation tab indices. Lives in its own file so both the shell and the screens that ask it to switch tabs can import it without a cycle.… |

### mobile/lib/features/stories/

«صورة حيّة»: لوحات حيّة، سرد صوتي «اسمعها من نور»، مشاهد ورق مقصوص، تجربة A/B

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/stories/experiment/story_experiment.dart` | 108 | «صورة حيّة» experiment (2026-10-24, the maintainer): do children like the stories more with living pictures — the camera following the narrator — or with the… |
| `mobile/lib/features/stories/experiment/story_rating_card.dart` | 138 | «هل أعجبتك الحكاية؟» — one small question at a story's end, the same in both arms of the «صورة حيّة» experiment (it never asks about the motion: the… |
| `mobile/lib/features/stories/living/living_picture.dart` | 510 | «صورة حيّة» — the story's own painted picture, alive. The children kept choosing the original raster pages (docs/stories/, Aug 2026) over every… |
| `mobile/lib/features/stories/living/living_picture_catalog.dart` | 4654 | Which stories are told with their painted pictures, alive (living_picture.dart) — and, page by page, the things in each picture the narrator's words… |
| `mobile/lib/features/stories/living/story_cover.dart` | 46 | A story's cover on the shelf and on its first leaf: the painted cover (`docs/stories/<id>_cover.png`) for a story told with its paintings, or the… |
| `mobile/lib/features/stories/narration/story_narration.dart` | 206 | «اسمعها من نور» — a story read aloud, one recording per page, with the sentence being read lit up on the page. The recordings live next to the story… |
| `mobile/lib/features/stories/narration/word_cues.dart` | 154 | When does the narrator say a word? Read off a page manifest's sentence ranges and timings — no forced alignment, no per-language indexes. A cue is a… |
| `mobile/lib/features/stories/scene/story_scene.dart` | 270 | A story page drawn as «ورق مقصوص» — paper pieces on a paper ground. A scene is one backdrop (assets/svg/stories/bg_*.svg, 360×240) and a few props… |
| `mobile/lib/features/stories/scene/story_scene_catalog.dart` | 1322 | Which paper pieces make which page of which story. One entry per page of the story, in order, read straight off the page's text (who is there, where,… |
| `mobile/lib/features/stories/shelf/magic_shelf.dart` | 867 | «رف الحكايات»: رف كتب ليلي، رف لكل سلسلة (الأنبياء/السيرة/الحكايات)، الكتاب التالي غير المقروء يواجه القارئ ويتوهّج، احترام تقليل الحركة |
| `mobile/lib/features/stories/shelf/read_stories.dart` | 34 | مجموعة محلية (SharedPreferences) بالقصص المقروءة حتى النهاية — نجمة الكتاب المنتهي واختيار الكتاب التالي |

### mobile/lib/features/support/

«ادعم المربّي» (Play Billing consumables) — يظهر فقط حين يفعّله الخادم

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/support/support_providers.dart` | 406 | «ادعم المربّي» — the two-sided gate, the transparency read, the purchase handler, and the app-wide coordinator that owns the purchase stream. The… |
| `mobile/lib/features/support/support_screen.dart` | 421 | «ادعم المربّي» — transparency first, then the amounts. The page opens with what the app costs this month and how much of it supporters covered,… |
| `mobile/lib/features/support/support_store.dart` | 69 | The store side of «ادعم المربّي» — a thin seam over `in_app_purchase`. Why Play Billing at all, for a free app: Google Play's Payments policy… |

### mobile/lib/features/tools/

أدوات عبادة محلية: مسبحة، محوّل هجري

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/tools/data/hijri_date.dart` | 168 | Hijri ⇄ Gregorian conversion. **What this is, precisely.** The tabular ("arithmetic" / Kuwaiti) Islamic calendar: a 30-year cycle of 11 leap years,… |
| `mobile/lib/features/tools/data/tasbeeh_store.dart` | 78 | Persistence for the tasbeeh counter. Two things survive a close: the running count and the chosen target. A counter that forgets is not a counter —… |
| `mobile/lib/features/tools/screens/hijri_converter_screen.dart` | 227 | Hijri ⇄ Gregorian converter. Local arithmetic, no network, no permission. The disclosure line under the result is part of the feature, not decoration… |
| `mobile/lib/features/tools/screens/tasbeeh_screen.dart` | 239 | Tasbeeh counter. Fully local: no network, no permission, no content. The whole screen is one large tap target on purpose — a thumb should find it… |

### mobile/lib/features/tour/

جولة أول تشغيل بتسليط ضوء (مكتوبة يدويًا)

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/tour/tour_controller.dart` | 52 | Cursor state for the guided tour. Deliberately tiny: which step is showing, and whether the tour is up at all. The step *content* lives with the… |
| `mobile/lib/features/tour/tour_overlay.dart` | 403 | The spotlight veil itself. Lives in the root [Overlay] rather than inside `RootScaffold.body`, because the veil has to cover the nav bar too — `body`… |
| `mobile/lib/features/tour/tour_step.dart` | 100 | The first-run guided tour: what it points at, and whether it runs at all. Hand-rolled on purpose. The packaged spotlight widgets (`showcaseview`,… |

### mobile/lib/features/whats_new/

«الجديد في التحديث» لمن لديهم التطبيق

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/lib/features/whats_new/data/whats_new.dart` | 94 | What shipped, told to the people who already had the app. Why this exists rather than a push: the app's own numbers are 37,393 FCM notifications to… |
| `mobile/lib/features/whats_new/widgets/update_available_card.dart` | 127 | بطاقة «نسخة جديدة متاحة» اختيارية قابلة للإغلاق في «اليوم»؛ تظهر إن كان `latest_build_number` من `/api/app-config` أحدث من البناء المثبّت |
| `mobile/lib/features/whats_new/widgets/whats_new_card.dart` | 143 | The «الجديد في التحديث» card. Renders nothing at all until every condition in [WhatsNewStore.shouldShow] is met, so a fresh install, a build with no… |

## 4) اختبارات الموبايل وأدواته وتهيئته


### mobile/test/ (اختبارات Flutter)

`flutter test` (قاعدة pre-push تشغّلها حين تمسّ الدفعة `mobile/`).

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/test/account_deletion_test.dart` | 342 | Settings → Privacy: account deletion (MOBILE_API §10), erasing memory (§9.6), and what the phone keeps after a deletion. Account deletion, by effect… |
| `mobile/test/adhkar_pack_language_test.dart` | 132 | A language with no pack must fall back to Arabic, never to nothing. The daily reminder is scheduled straight out of this pack. If a lookup for… |
| `mobile/test/adhkar_rotation_test.dart` | 256 | Adhkar rotation — the content pool must actually be reachable. The scheduler picks items by index from `familyAdhkar`. Three defects made that… |
| `mobile/test/adhkar_screen_test.dart` | 78 | The adhkar browser's one hard rule: nothing is shown without its citation. The pack is guarded at commit time by four checkers in `ops/tools/` that… |
| `mobile/test/agreement_and_coins_copy_test.dart` | 103 | Two screens that said what was not true. * The family agreement said it was "available for ages 7–9 only" after the 13–15 clause bank shipped, and… |
| `mobile/test/agreement_test.dart` | 95 | The signing surfaces, tested where a family can actually get stuck. The server refuses every child surface until an agreement is signed, so a bug in… |
| `mobile/test/android_resources_named_from_dart_test.dart` | 86 | An Android resource that Dart names by string must survive resource shrinking. 2026-10-15, PR #121 (the paper-cut launcher icon): the manifest… |
| `mobile/test/answer_share_test.dart` | 13 | نسخ/مشاركة إجابة نور: نص عادي لا Markdown |
| `mobile/test/auth_store_resilience_test.dart` | 167 | Device identity must survive storage hiccups (audit H7) and session minting must carry the device proof (audit H5). `_AuthStore._safeRead` used to… |
| `mobile/test/backup_test.dart` | 83 | Backup export/import tests (P1 #3) — round-trip + validation. Added in review (the original commit shipped without tests). |
| `mobile/test/badges_screen_test.dart` | 189 | The Badges screen, as parents see it. * Every tile had a fixed height (`GridView.count`'s aspect ratio), so it could not grow with its text: it… |
| `mobile/test/badges_test.dart` | 81 | Badges/achievements tests (P1 #4) — pure computeBadges logic. |
| `mobile/test/brand_glyph_test.dart` | 348 | BrandGlyph — the brand icon set (جولة الحرفة, item 1; «ورق مقصوص» SVG since 2026-10-14). Pinned here: 1. Every glyph draws: its own SVG… |
| `mobile/test/bundled_fonts_test.dart` | 54 | DS8: fonts are bundled, and runtime fetching is off — so every GoogleFonts call in lib/ must name a bundled family, and every weight the package can… |
| `mobile/test/burst_motion_test.dart` | 122 | Frame 0ms: entrance starts at begin (0.6) |
| `mobile/test/celebration_overlay_test.dart` | 126 | «مستويات الاحتفال» — the one celebration API has two volumes, and both respect the system's reduce-motion setting. Pinned here: · milestone (the… |
| `mobile/test/chat_background_stream_test.dart` | 825 | Leaving the app mid-answer (2026-10 reliability fix + PR #24 review). The chat used to stop a streaming answer on `inactive`/`paused` — the… |
| `mobile/test/child_copy_neutral_test.dart` | 39 | Child-facing mission copy names the family, never one parent, and carries no emoji — the glyph next to it is drawn by the screen (BrandGlyph). Many… |
| `mobile/test/child_corner_test.dart` | 708 | «ركن الطفل» — the child's corner after the hand-over gate. What has to hold (scratch/game-study/REPORT.md, the brief of 2026-10-15): * only what the… |
| `mobile/test/child_hand_back_test.dart` | 216 | How a child surface ends: on a screen that asks for the device back, with child mode still on — so the only way out is the parent's PIN. The… |
| `mobile/test/child_memory_screen_test.dart` | 333 | «ما يعرفه المربّي عن <اسم>» (MOBILE_API §9.2–§9.3). The parent's controls, each by effect on the (fake) server: facts by category with the name… |
| `mobile/test/child_mode_lock_subtitle_test.dart` | 79 | The PIN screen says what to do in each of its four states. It used to show «المرحلة العمرية» on first setup and «غير متصل بالإنترنت» everywhere else. |
| `mobile/test/child_mode_restart_lock_test.dart` | 408 | A restart in the middle of child mode — or after its session ended — lands on the hand-back screen, never on the parent's app. restore() used to end… |
| `mobile/test/child_mode_test.dart` | 56 | اختبارات: child mode |
| `mobile/test/child_surface_policy_test.dart` | 124 | The hand-over gate's copy of the age gate must agree with the server's. `backend/guardrails/child_surface.v1.yaml` is the authority; the app keeps a… |
| `mobile/test/coins_test.dart` | 263 | The coin economy has one sink and two ceilings, and each of these tests pins one of the things that used to be true and should not be again. |
| `mobile/test/community_proof_test.dart` | 65 | The community line is reassurance, so silence is the only acceptable failure. It reads a network count. If that call is slow, fails, or the community… |
| `mobile/test/companion_brain_test.dart` | 640 | «نور يتذكّر» — the priority rule and the anti-nag rules, pinned. |
| `mobile/test/companion_store_test.dart` | 158 | «نور يتذكّر» — the device memory and the promise reminder rule. |
| `mobile/test/content_direction_test.dart` | 169 | Content direction follows the content, not the chrome. The reader screen used to hard-code `TextDirection.rtl` around the story text. That was right… |
| `mobile/test/crash_triage_test.dart` | 97 | Builds a details object shaped like the framework's own overflow report. |
| `mobile/test/crashlytics_disposed_safety_test.dart` | 72 | Regression test for the Crashlytics crash caused by stale/disposed state. A `Future.delayed` inside each star could call `_controller.repeat()` after… |
| `mobile/test/curriculum_offline_cache_test.dart` | 91 | The curriculum has to survive losing the network. The app was online-only: a parent opening it on the metro, or on a phone out of data, got an error… |
| `mobile/test/daily_routine_qr_dialog_widget_test.dart` | 102 | classes: _FakeTgClient |
| `mobile/test/dark_mode_test.dart` | 168 | Dark mode — requested in production (#fb_e7402eaa, 15 Aug 2026). The obstacle was never the colours. `Dt.primary` and friends were `static const… |
| `mobile/test/design_system_contrast_test.dart` | 139 | Design-system guards (UX_UI_ROADMAP.md, UX-0). Pins the three things the 2026-09 audit found broken and fixed: 1. Text on filled buttons meets WCAG… |
| `mobile/test/device_identity_race_test.dart` | 436 | One install, one device id — however many callers ask at once. 2026-10-04: a fresh install minted TWO device ids in the same second (same FCM token).… |
| `mobile/test/device_proof_test.dart` | 416 | Device proof — the FCM challenge (MOBILE_API §9.0.1). The service proves a session by posting back a code the server sent as a silent data message.… |
| `mobile/test/e2e_probes_test.dart` | 151 | The CI rehearsal's key probe (core/e2e_probes.dart): absent from every build that is not the rehearsal APK, and — where a test installs it — one F12… |
| `mobile/test/eid_moment_test.dart` | 303 | «عيدكم مبارك» (نور والقناديل phase 5): on the first open of Eid, once a Hijri year, a quiet moment over Today — Noor happy, the lanterns lighting,… |
| `mobile/test/error_retry_view_test.dart` | 88 | Parents must never be shown an exception's toString(). Three screens rendered errorGeneric(e.toString()), so a dropped connection read as "خطأ:… |
| `mobile/test/family_road_logic_test.dart` | 303 | «درب {الاسم}» (عالم الأسرة): the gates ahead and what is behind «أنتم هنا». The road opens on what is ahead — the empty road is the risk — so these… |
| `mobile/test/family_road_screen_test.dart` | 426 | «درب {الاسم}» (عالم الأسرة) on a phone: it opens on the horizon, Noor stands on «أنتم هنا», only what was done is lit below it, every gate goes… |
| `mobile/test/favorites_test.dart` | 70 | Favorites tests (P1 #1) — storage round-trip + notifier state. Added in review (the original commit shipped without tests). |
| `mobile/test/flashcards_widget_test.dart` | 127 | Flashcards screen widget tests — P0.1 media players. Same strategy as program_widget_test.dart: override [tgClientProvider] with a fake whose… |
| `mobile/test/followup_test.dart` | 439 | «جرّبت النصيحة؟ نفعت؟» — the follow-up on Today and behind the `/followup/{id}` push (MOBILE_API §9.4). Pinned by effect on the (fake) server: the… |
| `mobile/test/force_update_gate_test.dart` | 66 | The gate used to fall open on any fetch failure, so builds below the minimum kept running whenever the config call timed out. It must now fall back… |
| `mobile/test/friday_harvest_test.dart` | 316 | «حصاد الجمعة» (نور والقناديل phase 3). Noor says one line on the family's Friday — once, and only for a week with lanterns — and the line stays put… |
| `mobile/test/friendly_api_errors_test.dart` | 370 | Raw server text must never reach a parent. An E2E run caught the lesson screen showing, under «تعذّر تحميل الدرس»: TgApiError(502): The origin web… |
| `mobile/test/games_catalog_test.dart` | 85 | The games index and the «أين أجد…؟» help sheet. Both exist to rescue someone who is already lost, so a broken entry in either is worse than not… |
| `mobile/test/games_test.dart` | 422 | Question packs — the four games' content lives in `assets/content/games/*.ar.json` since 2026-08-13, not in Dart literals. What these pin is what the… |
| `mobile/test/games_time_cap_test.dart` | 221 | The four games had no clock in them at all. The only way out of a level was answering every question or losing three lives, and a child who did… |
| `mobile/test/google_account_entry_test.dart` | 40 | كل ملف يفتح `AppRoutes.identity` يحترم `kGoogleAccountEntryEnabled` |
| `mobile/test/google_identity_migration_test.dart` | 535 | Exercise the real plugin API through its platform boundary. |
| `mobile/test/greeting_test.dart` | 68 | Time-aware greeting and AppBar title («النصوص», phase 1). The hour picks صباح/مساء and ☀️/🌙; a first-day login streak drops the «مستمرة» — a journey… |
| `mobile/test/habit_child_mode_widget_test.dart` | 354 | classes: _FakeSecureStorage, _FakeTgClient |
| `mobile/test/habit_models_test.dart` | 214 | Unit tests for habit models and age-gating logic (ميزان العادات). |
| `mobile/test/handover_gate_test.dart` | 411 | «باب التسليم» (NOOR_WAL_QANADIL_PLAN phase 4): one gate for every hand-over. What has to hold: * it offers only what the child's band allows (and… |
| `mobile/test/hijri_convert_test.dart` | 99 | The converter's claim is narrow and this file is where it gets checked. Two different things are tested, and the difference matters: * **Internal… |
| `mobile/test/horizon_attribution_test.dart` | 74 | horizon_to_action_48h`: a parenting act within two days of a horizon tap fires once; worship, other events, and acts after 48 hours do not. |
| `mobile/test/hub_catalog_test.dart` | 114 | Invariants for the «المزيد» hub. The hub is the app's index of everything outside the daily loop, so a tile that resolves to a missing translation or… |
| `mobile/test/identity_error_messages_test.dart` | 138 | How google_sign_in_android 7.x reports "no Google account on the phone". |
| `mobile/test/integration_smoke_test.dart` | 129 | Phase 2 integration smoke test — runs against the real local backend on http://localhost:8090 (Tutor Guardian FastAPI). Skipped automatically when… |
| `mobile/test/invite_reward_test.dart` | 82 | «أثر دعوتك» — the invite screen says only what is true. The screen leads with how many families the parent's sharing reached, and keeps the coins to… |
| `mobile/test/journey_milestone_assets_test.dart` | 56 | «أعطال اتلقت في الطريق» — the milestone badge asset builder. The keys already start with `first_` (`first_prayer`), and the builder prepended another… |
| `mobile/test/language_unified_test.dart` | 55 | One language, not two. The app used to carry two switches: `appLocaleProvider` for the interface and curriculum text, and a separate… |
| `mobile/test/lantern_fakes.dart` | 49 | Test helpers for «قناديل الأسبوع» (MOBILE_API §12): the JSON the server sends for a week, built around the phone's own clock. |
| `mobile/test/large_text_and_rtl_test.dart` | 105 | Two layout promises on screens this branch touched, checked as numbers: * «المزيد» tiles grow with the text. They sat in a GridView with a fixed… |
| `mobile/test/living_picture_test.dart` | 606 | «صورة حيّة» — the original painted pages, alive (living_picture.dart). Pins: 1. The word engine: Arabic prefixes and a closed list of endings, `=`… |
| `mobile/test/local_timezone_test.dart` | 89 | The bug this pins: `tz.local` left at UTC, so a 6 AM reminder fired at 6 AM UTC — 9am in Riyadh, 1pm in Jakarta, 2am on the US east coast, 11pm the… |
| `mobile/test/magic_shelf_test.dart` | 120 | رف الحكايات: رف لكل سلسلة، الكتاب التالي، نجمة المنتهي، فتح الكتاب |
| `mobile/test/markdown_rendering_test.dart` | 69 | Every assistant reply is rendered as Markdown, so the renderer is on the app's most-used path. flutter_markdown was discontinued upstream and this… |
| `mobile/test/mawqif_test.dart` | 198 | «موقف بقرار» (docs/MAWAQIF.md): the model, the device store, the Today card and the five screens. |
| `mobile/test/memory_api_test.dart` | 622 | «المربّي يعرف ابنك» — the wire (MOBILE_API §9–§10) and its parsing. What each group pins: * the requests are the contract's: paths,… |
| `mobile/test/memory_fakes.dart` | 729 | Test doubles for «المربّي يعرف ابنك» (MOBILE_API §9–§10). [FakeMemoryServer] is a TgClient whose memory, follow-up, plan, proof and deletion… |
| `mobile/test/missions_surface_test.dart` | 585 | The mission card, the evening confirmation, and the surfaces around them. The backend for all of this shipped complete and tested with nothing in the… |
| `mobile/test/nav_observer_test.dart` | 129 | Unit tests for the "lostness" classifier. The interesting logic in TgNavObserver is how it decides what a finished visit *meant*. That decision is a… |
| `mobile/test/noor_assistant_test.dart` | 487 | «نور والقناديل», phase 4 — «المساعد»: Noor beside every answer (thinking while it is written, calm once done), «سأجرّبها مع …» under the latest… |
| `mobile/test/noor_face_test.dart` | 340 | NoorFace — the six-state «نور» face, «ورق مقصوص» SVG since 2026-10-14 (drawn in code before, جولة الحرفة item 4). Pins: 1. Every state paints without… |
| `mobile/test/noor_path_moments_test.dart` | 411 | «اكتمل البدر» and «درب المسار» (NOOR_WAL_QANADIL_PLAN, phase 4). The full moon is a moment, so it must be rare and earned: it rises when a path goes… |
| `mobile/test/noor_presence_test.dart` | 159 | NoorPresence — the moon-window framing around «نور», with a drawn halo in two moods (NOOR_WAL_QANADIL_PLAN, Phase 1; «ورق مقصوص» SVG face since… |
| `mobile/test/noor_today_header_test.dart` | 247 | «نور يتذكّر» — Noor's line on «اليوم»: what it shows, what its chips do, and that it gives way to the plain greeting when it has nothing to say. |
| `mobile/test/notification_after_first_lesson_test.dart` | 89 | The notification permission ask moves from launch (main.dart) to after the FIRST completed lesson (NOOR_WAL_QANADIL_PLAN, Phase 1). Why: asking… |
| `mobile/test/notification_permission_test.dart` | 131 | The reminder schedule must survive the permission prompt failing. Found by running 1.0.51 on an emulator, not by a test — which is the point of… |
| `mobile/test/offscreen_band_labels_test.dart` | 39 | تسميات شرائح العمر في «أنشطة بلا شاشة» مترجمة (كانت خريطة عربية ثابتة) |
| `mobile/test/onboarding_name_test.dart` | 443 | «الاسم» — phase 2 of docs/NOOR_WAL_QANADIL_PLAN.md. The child used to be created as «طفلي» and the name was never asked. Now the creation wait asks… |
| `mobile/test/p1_onboarding_delight_test.dart` | 420 | Phase 1 «التطبيق يصحو» — first-run cheap touches (NOOR_WAL_QANADIL_PLAN). Pins the onboarding half of the phase: * the welcome hero is the «ورق… |
| `mobile/test/phase10_login_streak_test.dart` | 127 | «اليوم»'s first stats chip — phase 10 put the login streak there (`daily_login_streak`, not the lesson streak); نور والقناديل phase 3 took it away.… |
| `mobile/test/phase4_lifecycle_test.dart` | 345 | Phase 4 lifecycle tests — bootstrap rehydration + session recycling. We use a custom BaseClient (so we can return a real StreamedResponse for the SSE… |
| `mobile/test/phase5_progress_test.dart` | 633 | Phase 5 widget + repository tests — children + progress. Same pattern as program_widget_test.dart: override tgClientProvider with a fake that returns… |
| `mobile/test/phase6_onboarding_test.dart` | 481 | Phase 6 widget + unit tests — onboarding flow + streak chip. Strategy: 1. Pure-Dart tests for OnboardingStorage (no widgets). 2. Widget tests for… |
| `mobile/test/phase7_settings_test.dart` | 315 | Phase 7 widget + repository tests — settings flow. Strategy: 1. Pure-Dart tests for SettingsRepository wrappers. 2. Widget tests for SettingsScreen,… |
| `mobile/test/phase8b_multichild_test.dart` | 569 | Phase 8-B tests — multi-child switcher. Strategy: 1. Pure-Dart tests for the on-disk persistence of OnboardingStorage when switching the active… |
| `mobile/test/phase8c_reflections_test.dart` | 295 | Phase 8-C tests — reflection notes (local-only). Strategy: 1. Pure-Dart tests for ReflectionStorage (round-trip). 2. Provider tests for… |
| `mobile/test/podcast_widget_test.dart` | 65 | Podcast player screen widget tests — P0.1 media players (third of three). We don't actually stream audio in unit tests — the `just_audio` package… |
| `mobile/test/pr36_delta_review_test.dart` | 1137 | PR #36 delta review (head 3814abbf) — one group per item, each by effect. The reviewer's probes P1–P5 are ported where they belong. 1. A pending… |
| `mobile/test/pr36_review_fixes_test.dart` | 1219 | PR #36 review — one group per item, each by effect. 1. After an account deletion the app really ends (finishAndRemoveTask), with exit(0) only as the… |
| `mobile/test/pr36_round3_review_test.dart` | 542 | PR #36 delta review, round 3 (head 7d3398ff) — one group per item, each by effect. The reviewer's probes B, B2, C1, C2 and E are ported against the… |
| `mobile/test/praise_word_test.dart` | 309 | «كلمة طيبة» — the note from parent to child. The loop has three links and each is held here: the chips on the evening screen ride the confirmation… |
| `mobile/test/prayer_stage_moment_test.dart` | 201 | «رحلة الصلاة», phase 4 of NOOR_WAL_QANADIL_PLAN: moving up a stage is a quiet moment — «انتقل أحمد إلى «الوضوء». أعانكم الله وتقبّل منكم» — on a… |
| `mobile/test/pride_invite_test.dart` | 68 | §6.4 — PrideInviteCard: the referral ask fires only at pride moments (≥7-day streak), once per 7-day tier, and dismissal persists. |
| `mobile/test/program_repository_offline_test.dart` | 175 | What a parent with no signal actually sees. Before this, ProgramRepository handed every network failure straight to the UI, so opening the app on the… |
| `mobile/test/program_widget_test.dart` | 801 | Phase 4 widget tests — program layer (paths/lessons/daily tip). Strategy: we don't hit the real network. We override [tgClientProvider] with a… |
| `mobile/test/programs_api_test.dart` | 304 | The family-programs wire (MOBILE_API §11) through the real TgClient. What these pin: every programs call carries the family's UTC offset and the UI… |
| `mobile/test/programs_contract_test.dart` | 192 | The contract changes from the PR #32 review (MOBILE_API §11), pinned on the client side: · each program stands alone — a null section is hidden,… |
| `mobile/test/programs_entry_test.dart` | 327 | The ways into the family programs, and what an older server sees. A server without schema v34 answers 404 to `GET /api/programs`. Builds stay live… |
| `mobile/test/programs_layout_test.dart` | 92 | Every programs screen survives dark mode, 200% text, both directions and a small phone: scrolled top to bottom, nothing overflows or throws. "The… |
| `mobile/test/programs_milestones_test.dart` | 74 | The proactive milestones: a card list per child, a detail with its cards, red flags shown plainly, and a graceful path when the birth month (or the… |
| `mobile/test/programs_models_test.dart` | 220 | The programs payloads parse as MOBILE_API §11 documents them — and degrade to "not shown" rather than crash when a field is missing, because the… |
| `mobile/test/programs_prayer_test.dart` | 259 | «رحلة الصلاة»: the parent's view, the child's card in child mode, and the evening confirmation that turns a claim into coins. The loop the plan rests… |
| `mobile/test/programs_ramadan_test.dart` | 341 | «رمضان العائلة» on screen: every season state, the family's tick-only marks, the fasting ladder with its safety guidance first, the family's own moon… |
| `mobile/test/programs_review2_fixes_test.dart` | 471 | PR #34 delta review (3a706677) — one group per finding, from the reviewer's repros R1–R6 (/tmp/review-pr34b/zz_review34b_*_test.dart), turned to… |
| `mobile/test/programs_review_fixes_test.dart` | 432 | PR #34 review — one test per finding, built from the reviewer's repros (/tmp/review-pr34/zz_review_repro_test.dart) and turned to assert the fix. |
| `mobile/test/programs_support.dart` | 747 | Fixtures and a fake client for the family-programs tests. The payloads mirror the samples in MOBILE_API.md §11 (backend schema v34), trimmed to what… |
| `mobile/test/push_permission_test.dart` | 72 | The one classification this change hangs on. The permission ask now retries — but only when the platform said "there is no Activity yet", never when… |
| `mobile/test/quiz_game_empty_payload_test.dart` | 105 | Regression tests for the parenting-quiz game screen's load paths. v1.0.30 softened the payload parse from `data['questions'] as List` to `as List? ??… |
| `mobile/test/quiz_game_encoding_test.dart` | 62 | Pins the Arabic decoding of the quiz payload. This screen is the only place in the app that reads `resp.body` instead of… |
| `mobile/test/quiz_widget_test.dart` | 272 | Quiz screen widget tests — P0.1 media players (second of three). Same pattern as flashcards_widget_test.dart: override tgClientProvider with a fake… |
| `mobile/test/quran_reader_exit_test.dart` | 66 | Leaving the Quran reader saves where the parent stopped, and throws nothing. Until 2026-10-15 every exit threw «Cannot use "ref" after the widget was… |
| `mobile/test/ramadan_lantern_street_test.dart` | 334 | «شارع القناديل» — phase 5 of «نور والقناديل»: the month as thirty paper lanterns. A lantern is lit when the family marked anything that day; every… |
| `mobile/test/restore_key_test.dart` | 221 | مفتاح الاستعادة في `tg_client`: التخزين، الإرسال بلا توكن فقط، المسح عند الحذف |
| `mobile/test/route_registry_test.dart` | 216 | Invariants for the central route registry. Every screen's analytics identity comes from `Screens.*`, and the whole "where do users get lost?"… |
| `mobile/test/screen_off_mode_test.dart` | 104 | Screen-off listening, and the promise about where recordings live. Two things are being protected here. A child's exit must be deliberate but… |
| `mobile/test/search_widget_test.dart` | 101 | Search feature tests — model parsing + screen behaviour. Overrides tgClientProvider with a fake whose searchCurriculum returns canned results, then… |
| `mobile/test/seerah_stories_test.dart` | 212 | موسم «من السيرة النبوية» (`sira_sahih`): ثماني قصص موسومة، صور وسرد لكل منها |
| `mobile/test/share_card_layout_test.dart` | 403 | Where a shared card puts its words, and which way they read. Two faults every shared card had, both seen only in a captured PNG: * Short content sat… |
| `mobile/test/share_service_whatsapp_uri_test.dart` | 36 | Regression test for the WhatsApp share link. The URL was built as '...?text=\${Uri.encodeComponent(text)}'. The escaped `$` turned the interpolation… |
| `mobile/test/share_sheet_l10n_test.dart` | 392 | Every share sheet, as the people a parent shares with receive it. With the app in English, each share still went out in Arabic: the install line… |
| `mobile/test/single_dart_entrypoint_test.dart` | 56 | main() must run in exactly one Flutter engine per process. 2026-10-04: every launch of 1.0.58–1.0.67 ran main() twice. The unused… |
| `mobile/test/sky_band_test.dart` | 288 | «السماء» on «اليوم»: the hour picks the sky, the night has at most twelve stars and no sun, and a dark page never gets a glaring pastel card. In… |
| `mobile/test/social_links_test.dart` | 81 | These links leave the app and land on a public page, so a wrong one sends a parent to a stranger's profile with our name attached to the tap. |
| `mobile/test/sound_fx_test.dart` | 417 | Soft interface sounds («أصوات ناعمة بلا موسيقى»): who may hear them, which haptic carries which sound, what the files are, and that a broken player… |
| `mobile/test/startup_notification_init_test.dart` | 59 | Play vitals: 9.35% slow cold starts. Notification setup (the time-zone database, the plugin, 14 days of reminders) moved from before `runApp` to… |
| `mobile/test/stories_paper_test.dart` | 590 | «القصص» — the paper-cut reader and shelf (2026-10, docs/STORIES_AUDIT.md). Pins: 1. A story opens on its own first leaf — no adhkar gate in front of… |
| `mobile/test/story_experiment_test.dart` | 297 | «صورة حيّة» experiment (features/stories/experiment/). Pins: 1. The arm: forced by the server's mode, else a stable 50/50 hash of the device id (same… |
| `mobile/test/story_models_test.dart` | 206 | اختبارات: story models |
| `mobile/test/support_test.dart` | 905 | «ادعم المربّي» — the two-sided gate, the app-wide purchase coordinator, the record-then-consume order, and the screens. The store is faked, but… |
| `mobile/test/svg_assets_test.dart` | 210 | «ورق مقصوص» — every SVG the app ships is one flutter_svg can draw. The art set is hand-written SVG (assets/svg/, rules in STYLE.md). A file… |
| `mobile/test/tafsir_provider_test.dart` | 301 | What the tafsir provider must not do, stated as tests. The feature exists to put an attributed explanation in front of a parent. Every failure mode… |
| `mobile/test/tasbeeh_store_test.dart` | 66 | No target means it can never read as complete. |
| `mobile/test/tasmee_screen_test.dart` | 164 | «تسميع مع الوالد» — the screen: marking a word, the kinds, the summary and saving. |
| `mobile/test/tasmee_store_test.dart` | 170 | «تسميع مع الوالد» — the device store: slips per child and passage, review dates, corrupt data. |
| `mobile/test/tg_client_session_test.dart` | 261 | Audit M12 / M13 / H5 (client side): one shared client, one session mint at a time, a 401 renews the session once and replays the request, and a reply… |
| `mobile/test/tg_client_test.dart` | 224 | Phase 2 unit tests — SSE parser & model decoders. We exercise the parser by pumping synthetic event streams into a fake http.Client. The parser is… |
| `mobile/test/today_cards_english_titles_test.dart` | 200 | Today's first-lesson card and «Continue your path» card follow the app language after it is switched — store captures of 1.0.73. The English store… |
| `mobile/test/today_focus_card_continue_test.dart` | 274 | «واصل مسارك» → «متابعة» opens the lesson that is due, not the path overview. The maintainer on 1.0.73: the card read «أوّل ما يعرفه قلبه: الله», 2/4, «2 دروس… |
| `mobile/test/today_focus_card_resumed_test.dart` | 126 | TodayFocusCard reads `NextLesson.resumed` — «أعطال اتلقت في الطريق». The endpoint says `resumed: true` only when the starter path is entirely done… |
| `mobile/test/today_mission_row_test.dart` | 160 | «مهمة اليوم» on Today for the parent — no handover (2026-11-08). |
| `mobile/test/today_three_blocks_test.dart` | 807 | «اليوم» — three blocks for the active child, then a divider, then the rest. The screen was cut down because «مش عارف أبدأ منين» was the first thing… |
| `mobile/test/tour_test.dart` | 370 | Invariants for the first-run guided tour. The load-bearing one is the first group: the tour is a full-screen veil that swallows taps, so if it ever… |
| `mobile/test/transient_retry_test.dart` | 124 | A read that meets the server mid-restart is tried again; a write never is, and the app's own 503s (JSON with a reason) are shown at once. |
| `mobile/test/update_available_card_test.dart` | 71 | بطاقة التحديث: اختيارية، مرة لكل بناء أحدث، لا تظهر على الأحدث |
| `mobile/test/ux1_accessibility_test.dart` | 246 | UX-1 accessibility baseline (UX_UI_ROADMAP §5): * custom tap targets are announced as buttons (DS9); * with "remove animations" on, looping… |
| `mobile/test/ux1_palette_test.dart` | 156 | DS5: the palette as a ThemeExtension, and a light/dark switch that reaches every widget — including the ones that read Dt.* without depending on… |
| `mobile/test/ux2_chat_lifecycle_test.dart` | 175 | UX-2 chat lifecycle (UX_UI_ROADMAP §2): token batching keeps what the reader saw, the thinking state reassures after 3 s, follow-up chips send, and a… |
| `mobile/test/ux2_sources_context_test.dart` | 191 | UX-2 rest (UX_UI_ROADMAP C6, C8 and §2.2): the "Sources (n)" disclosure under a grounded answer, and the behaviour-type field folded from a permanent… |
| `mobile/test/ux3_habits_test.dart` | 115 | UX-3 habits (UX_UI_ROADMAP §3.2–3.3): the 7-day strip, the streak with its weekly shield, and the capped milestone set. |
| `mobile/test/ux3_haptics_test.dart` | 41 | E5: one switch silences every haptic; the preference survives restarts. |
| `mobile/test/ux3_loading_test.dart` | 57 | E3/E4: skeleton loading with a slow-network hint at 8 s and Retry at 20 s. |
| `mobile/test/ux3_status_banner_test.dart` | 60 | E2: one app-wide line for offline and for "showing a saved copy". |
| `mobile/test/ux4_child_surface_test.dart` | 103 | UX-4 (UX_UI_ROADMAP §4.3): the child theme and the child-mode frame. |
| `mobile/test/week_lanterns_test.dart` | 363 | «قناديل الأسبوع» under ① on «اليوم» (نور والقناديل phase 3, MOBILE_API §12). Pinned here: the client hides everything on an older server (404) and on… |
| `mobile/test/weekly_plan_card_test.dart` | 177 | «خطة الأسبوع» on Today (MOBILE_API §9.5). Collapsed to the focus by default (Today promises three stops); expanded: three actions, the worship act,… |
| `mobile/test/weekly_plan_marks_test.dart` | 328 | «خطة أسبوع بتتعلّم عليها» (نور والقناديل phase 3, MOBILE_API §9.5.1). A step is ticked with one tap: the tick shows before the server answers, a… |
| `mobile/test/whats_new_test.dart` | 172 | The two ways a "what's new" card goes wrong, stated as tests. 1. It greets a brand-new user with a list of changes they have no "before" for. That is… |
| `mobile/test/widget_test.dart` | 83 | Phase 1+3 smoke test — verifies the app boots into the chat screen with the Arabic title, and the chat notifier (Riverpod) builds without error when… |
| `mobile/test/wird_notification_test.dart` | 122 | The wird reminder is back. These tests pin the three faults that killed it, so bringing it back does not bring them back with it. From the v1.0.39+84… |

### mobile/tool/ — أدوات التوليد والتدقيق

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/tool/audit_light_surfaces.dart` | 152 | Counts surfaces that still hard-code a light colour instead of reading the palette — the exact defect that shipped in 1.0.48+93. Dark mode was… |
| `mobile/tool/gen_story_narration.py` | 590 | «اسمعها من نور» — record a story, one file per page, with sentence timings. Run from the repo root: |
| `mobile/tool/real_recitation.py` | 226 | Real recitation for a ﴿verse﴾ quoted in a story — no TTS voice ever recites the Qur'an. The maintainer, 2026-10-18: «تلاوة حقيقية». A verse on a story page… |
| `mobile/tool/recitation_refs.json` |  | ملف بيانات/إعداد JSON |
| `mobile/tool/shelf_demo.dart` | 86 | بناء معاينة debug للرف وحده (بلا Firebase/حسابات) — لا يُشحن |
| `mobile/tool/story_alive_demo.dart` | 119 | A preview build of the story reader alone, every bundled story — to see the «صورة حيّة» sample (maryam_toys told with its original painted pages, the… |
| `mobile/tool/story_art.py` | 830 | «ورق مقصوص» — the story scenes' cut-paper pieces, written as SVG. Run from mobile/: python3 tool/story_art.py |
| `mobile/tool/test_gen_story_narration.py` | 489 | The narration check: a page passes only if its transcript is the page. Run from the repo root: python3 -m unittest discover -s mobile/tool |

### mobile/ — التهيئة والتوثيق وAndroid/iOS (ملفات نصية)

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/.gitignore` |  | استبعادات Flutter (يشمل key.properties و*.jks) |
| `mobile/.metadata` |  | بيانات تعريف Flutter |
| `mobile/README.md` | 17 | ملاحظة قصيرة للمجلد |
| `mobile/analysis_options.yaml` | 28 | قواعد flutter analyze |
| `mobile/android/app/build.gradle.kts` | 103 | إعداد بناء Android: applicationId com.alsaba.almorabbi، توقيع الإصدار من key.properties (خارج git)، R8/minify، versionCode من pubspec |
| `mobile/android/app/google-services.json` |  | إعداد Firebase للعميل (مفاتيح عميل عامة بالتصميم؛ ليست أسرارًا) |
| `mobile/android/app/proguard-rules.pro` |  | قواعد R8 المضيَّقة (الشاملة كانت تحبس التقليص؛ full mode يشيل constructor الـFirebase registrars) |
| `mobile/android/app/src/debug/AndroidManifest.xml` | 7 | بيان debug |
| `mobile/android/app/src/main/AndroidManifest.xml` | 115 | بيان التطبيق: الأذونات، الأنشطة، الروابط العميقة https://tg-api.alsaba.cloud/{go,l,p}، قنوات الإشعار |
| `mobile/android/app/src/main/kotlin/com/alsaba/almorabbi/MainActivity.kt` | 48 | النشاط الرئيسي (FlutterActivity وحيد — شرطٌ لمنع محرّك Flutter ثانٍ، راجع test/single_dart_entrypoint_test.dart) |
| `mobile/android/app/src/main/res/values-en/strings.xml` | 5 | سلاسل Android الإنجليزية |
| `mobile/android/app/src/main/res/values/strings.xml` | 14 | اسم التطبيق وسلاسل Android (عربي) |
| `mobile/android/app/src/main/res/xml/backup_rules.xml` | 49 | قواعد النسخ الاحتياطي (استبعاد الملفات المؤقتة/الحساسة) |
| `mobile/android/app/src/main/res/xml/data_extraction_rules.xml` | 32 | قواعد استخراج البيانات (Android 12+) |
| `mobile/android/app/src/main/res/xml/network_security_config.xml` | 24 | سياسة الشبكة (cleartext محظور في الإنتاج) |
| `mobile/android/app/src/profile/AndroidManifest.xml` | 7 | بيان profile |
| `mobile/android/build.gradle.kts` | 39 | بناء Gradle الجذر |
| `mobile/android/gradle.properties` | 12 | خصائص Gradle |
| `mobile/android/gradle/wrapper/gradle-wrapper.properties` | 5 | إصدار Gradle wrapper |
| `mobile/android/settings.gradle.kts` | 26 | إعدادات Gradle والإضافات |
| `mobile/docs/accessibility-audit-2026-10-08.md` | 59 | Accessibility audit — 8 October 2026 |
| `mobile/docs/firebase-google-signin-migration-2026-10-08.md` | 133 | Firebase and Google Sign-In major migration |
| `mobile/l10n.yaml` | 5 | إعداد توليد الترجمة (flutter gen-l10n من lib/l10n/*.arb) |
| `mobile/pubspec.lock` |  | قفل اعتماديات Flutter |
| `mobile/pubspec.yaml` | 201 | اعتماديات Flutter والأصول والإصدار 1.0.74+119 |

**مجموعات (ثنائية/كثيفة) داخل `mobile/`:**

| المجموعة | عدد الملفات | ما هي |
|---|---:|---|
| `mobile/test/fixtures/narration/` | 94 (json×94) | لقطات السرد الصوتي لاختبار «اسمعها من نور» (manifests/نصوص)؛ تشمل قصص السيرة الثماني (ar/en) |
| `mobile/assets/svg/stories/` | 88 (svg×88) | قطع «ورق مقصوص» لمشاهد القصص (SVG مكتوب بـmobile/tool/story_art.py) |
| `mobile/assets/svg/art/` | 20 (svg×20) | رسوم المشاهد الكبيرة (تهيئة/تلال/ركن الطفل…) |
| `mobile/assets/svg/icons/` | 17 (svg×17) | مجموعة BrandGlyph للأيقونات |
| `mobile/assets/svg/noor/` | 7 (svg×7) | وجوه نور الستة |
| `mobile/assets/svg/STYLE.md` | 1 (md×1) | دليل أسلوب «ورق مقصوص» (ألوان/قواعد) |
| `mobile/assets/content/` | 11 (json×11) | بنوك محتوى: أسئلة الألعاب (8: ar+en) + حزمة الأذكار (ar/en) + معالم رحلة الطفل (1) |
| `mobile/assets/audio/` | 5 (wav×5) | 5 أصوات واجهة ناعمة مولّدة بـops/tools/gen_sfx.py |
| `mobile/assets/images/` | 7 (webp×5, png×1, gitkeep×1) | شعار وصور قليلة (generated/ لم تعد تُحزَّم) |
| `mobile/assets/animations/` | 2 (json×2) | Lottie مولّدة بـops/tools/gen_lottie.py |
| `mobile/assets/google_fonts/` | 19 (ttf×16, txt×3) | خطوط Cairo/Tajawal/Amiri Quran مضمّنة (لا تنزيل وقت التشغيل) |
| `mobile/assets/data/` | 5 (json×5) | quran.json + stories(.en).json + offscreen_activities(.en).json |
| `mobile/android/ (موارد صور)` | 64 (png×49, xml×14, gitignore×1) | أيقونات/splash Android (mipmap/drawable) |
| `mobile/ios/ (موارد)` | 46 (png×24, plist×4, swift×3, xcconfig×2 — الـswift الثلاثة لها صفوف فردية في «mobile/ios/» أعلاه) | أصول iOS (الأيقونة/الإطلاق) — iOS غير منشور |

### mobile/ios/ — شيفرة Swift (iOS غير منشور؛ هيكل Flutter الافتراضي)

| الملف | أسطر | الدور |
|---|---:|---|
| `mobile/ios/Runner/AppDelegate.swift` | 16 | `@main` — `AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate`؛ يسجّل `GeneratedPluginRegistrant` عبر `didInitializeImplicitFlutterEngine` (محرك Flutter ضمني، بلا شيفرة أصلية خاصة بالمشروع) |
| `mobile/ios/Runner/SceneDelegate.swift` | 6 | `SceneDelegate: FlutterSceneDelegate` فارغ — دعم مشاهد iOS |
| `mobile/ios/RunnerTests/RunnerTests.swift` | 12 | قالب XCTest افتراضي (`testExample` فارغ) — لا اختبارات فعلية لـiOS |

## 5) العمليات — `ops/`


### ops/scripts/ — كرونات وتقارير تعمل على الـVPS داخل الحاوية

مُركَّبة read-only داخل الحاوية (`./ops/scripts:/app/ops/scripts:ro`): تعديلها يصل الإنتاج بـ`git reset` بلا rebuild.

| الملف | أسطر | الدور |
|---|---:|---|
| `ops/scripts/backup_user_data.sh` | 48 | كرون 03:30 UTC: نسخ احتياطي يومي لكل قواعد SQLite بـbackup API + integrity_check + gzip (احتفاظ 14 يومًا) |
| `ops/scripts/broadcast_push.py` | 79 | بثّ إشعار لكل جهاز له توكن FCM |
| `ops/scripts/campaign_report.py` | 487 | تقرير الحملات: أي قناة تأتي بأسر تبقى (نقرات/تثبيتات/إضافة طفل/نشاط D7-13) |
| `ops/scripts/cron_push_triggers.py` | 597 | كرون 17:00 UTC داخل الحاوية: إشعارات إعادة التفاعل (first_lesson_activation → day_two → streak_at_risk → win_back؛ حد 1/جهاز/يوم، سقوف لكل غياب، لغة الأسرة ar/en) + طيّ نقرات الإحالة + privacy housekeeping |
| `ops/scripts/delete_account.py` | 142 | تنفيذ طلب حذف وصل بالإيميل لمن بلا تطبيق |
| `ops/scripts/deploy_model.sh` | 132 | نشر نموذج Ollama المخصّص tg-tutor (قديم) |
| `ops/scripts/feature_usage_audit.py` | 692 | جرد قراءة فقط لاستعمال القدرات والجداول لمدة N يومًا (بلا PII)، قياس انحراف `age_group` عن `birth_month`، وفحص جاهزية مخطط الأسرة |
| `ops/scripts/launch_weekly_report.py` | 766 | تقرير الإطلاق الأسبوعي: كل قرار تسويقي مقابل الاحتفاظ لكل كود |
| `ops/scripts/migrate_schema_v27.sh` | 160 | دليل ترحيل v27 (مفتاح فريد للتحدي النشط فقط) |
| `ops/scripts/min_build.sh` | 168 | أداة قرار حدّ التحديث الإجباري: current / census / plan / apply بفحص أمان |
| `ops/scripts/podcast_to_reels.py` | 229 | قصّ البودكاست إلى ريلز 30–60 ثانية بنص عربي وعلامة مائية |
| `ops/scripts/pregen_stories.py` | 90 | كرون 02:30: توليد القصص مسبقًا للكاش (--max 20) |
| `ops/scripts/send_broadcast_stories_push.py` | 83 | بثّ متعدد عالي الأداء لإشعار القصص |
| `ops/scripts/send_update_push.py` | 116 | دفع لطيف لمن هم على بناء قديم (--below N، يرسل فقط مع --send) |
| `ops/scripts/set_feedback_webhook.py` | 124 | تسجيل/فحص/إزالة webhook بوت تلجرام الملاحظات |
| `ops/scripts/story_motion_verdict.py` | 86 | حكم نهاية الشهر لتجربة «صورة حيّة»: حركة مقابل ثابت |
| `ops/scripts/v2_gate_check.py` | 708 | فاحص قراءة فقط لبوابات الترقية إلى 2.0.0 الأربع (عناوين الإنتاج، فعل D7 + sustained، مفتاح الاستعادة/قفل الهوية وتوكنات pre-v37، وموتى الكتالوج `⚠️`) |
| `ops/scripts/warm_answer_cache.py` | 185 | كرون 03:00: تسخين كاش الإجابات بأسئلة الألم الشائعة |
| `ops/scripts/weekly_dashboard.py` | 414 | داشبورد أسبوعي (LLM + احتفاظ + DB) إلى تلجرام |
| `ops/scripts/weekly_funnel_report.py` | 934 | تقرير القمع والاحتفاظ الأسبوعي (السبت 07:00) إلى تلجرام — مجمّع فقط |
| `ops/scripts/weekly_kb_gap_report.py` | 519 | تقرير فجوات المعرفة الأسبوعي (السبت 06:00): أسئلة حقيقية ← استرجاع ← حكم LLM ← تلجرام |

### ops/tools/ — أدوات المعرفة والحرّاس والتقييم والتوليد

كل حرّاس المحتوى الشرعي هنا (مُركَّبة read-only كذلك). جزء منها يعمل في `.githooks/pre-commit` و CI.

| الملف | أسطر | الدور |
|---|---:|---|
| `ops/tools/add_coverage_units.py` | 237 | Add knowledge units for under-covered domains: ADHD, Autism, Gaming Disorder. Content is conservative, parent-facing, evidence-aligned (CDC / AAP /… |
| `ops/tools/add_knowledge_unit.py` | 200 | Add a new knowledge unit interactively. Prompts the user for all required fields, validates against the schema, and saves to knowledge_base/data/. |
| `ops/tools/adhkar_pack.py` | 100 | The parenting-content pack, as the three notification-content guards see it. The pack used to be a Dart `const` list, and each guard carried its own |
| `ops/tools/age_reach_probe.py` | 229 | Measure whether the hand-authored gap units are reachable — matched and unmatched age. The vector leg filters to the child's age band plus… |
| `ops/tools/anbiya_fidelity.py` | 261 | مراجعة أمانة قصة نبي جملةً جملة بعائلتي نماذج أخريين (Ollama Cloud)؛ `run`/`report`، و`--series sira_sahih` للسيرة؛ يدوي، يحتاج `OLLAMA_API_KEY` |
| `ops/tools/anbiya_sources.py` | 199 | توثيق قصة نبي من مصادرها (الآيات + الميسّر) إلى `ops/data/anbiya/<id>.sources.json`؛ جلب للقراءة فقط، يدوي |
| `ops/tools/balance_quiz_answer_positions.py` | 540 | Spread the correct answer across positions in every backend-served quiz. Why: a Play review caught it and the data confirmed it — in |
| `ops/tools/bare_mint_readiness.py` | 110 | هل آمن إغلاق السكّ العاري؟ أعداد فقط (أجهزة نشطة بمفتاح استعادة، جلسات حسب `mint_kind`) لقرار `SESSION_MINT_ENFORCE`/`IDENTITY_CROSS_DEVICE`؛ يدوي |
| `ops/tools/build_commandr_trainset.py` | 75 | Format the premium QA corpus into chat-messages JSONL for fine-tuning. Model-agnostic: emits {"messages":[system,user,assistant]} so the training |
| `ops/tools/build_final_corpus.py` | 158 | build_final_corpus — تنظيف + دمج + تقرير جودة للكوربوس النهائي. يدمج الـpremium (DeepSeek، 25k) مع qa_dataset_clean (الأقدم) بعد تنظيف صارم |
| `ops/tools/build_golden_set.py` | 280 | Build the golden evaluation set for answer-quality benchmarking. Generates realistic parent questions from KB units via Azure DeepSeek |
| `ops/tools/build_hadith_index.py` | 300 | Build the two hadith indexes the content guards match against. ops/data/hadith_index.json.gz — Sahih al-Bukhari + Sahih Muslim. |
| `ops/tools/build_real_eval_set.py` | 310 | build_real_eval_set.py — Extracts a balanced, representative, and strictly anonymized eval set of ~100 real parent questions from production database. |
| `ops/tools/build_vector_db.py` | 70 | Build / rebuild ChromaDB vector index for knowledge_base/units/*.json. Uses the ONNX embedder built into ChromaDB (no external model download… |
| `ops/tools/candidate_smoke.py` | 315 | Fast smoke of a candidate backend image — the in-image gate of every deploy. The full suite does not run in the image. It runs on GitHub-hosted… |
| `ops/tools/candidate_smoke.sh` | 52 | Run the in-image smoke (ops/tools/candidate_smoke.py) against a candidate |
| `ops/tools/check_adhkar_integrity.py` | 171 | Guard the daily-notification content against padding and blanket attribution. Written after 2026-08-13, when the file claimed "exactly 730 unique… |
| `ops/tools/check_anbiya_stories.py` | 604 | 🛡️ حارس «قصص الأنبياء من القرآن»: لا حوار بين «»، لا اسم/رقم ليس في المصادر، كل جملة «مدعومة» عند عائلتين؛ pre-commit + CI (`backend.yml`)؛ exit 2 = اختباراته الذاتية انكسرت |
| `ops/tools/check_curriculum_schema.py` | 283 | فحص: ملفات المنهج تطابق مخطّطاتها — عربيها وإنجليزيها |
| `ops/tools/check_deploy_drift.py` | 198 | Alert when main has deploy-relevant commits that production is not running. The Deploy workflow's own failure alert covers a run that failed. It… |
| `ops/tools/check_hadith_citations.py` | 473 | Verify every hadith in the app against Sahih al-Bukhari and Sahih Muslim. Only the two Sahihs. That is the whole point: their authenticity is settled… |
| `ops/tools/check_infographic_language.py` | 223 | فحص: الإنفوجراف الإنجليزي مكتوب بالإنجليزية فعلًا |
| `ops/tools/check_kb_fidelity.py` | 900 | check_kb_fidelity.py — هل ملخّص وحدة المعرفة أمينٌ لمصدرها؟ وهل الحجر صامد؟ |
| `ops/tools/check_kb_integrity.py` | 332 | Knowledge-Base Integrity Guard — حارس سلامة قاعدة المعرفة The tutor-guardian analog of analytics-platform's schema-drift detector. |
| `ops/tools/check_path_video_coverage.py` | 102 | فحص: تغطية فيديو المسارات تُقاس على المنهج لا على الخريطة |
| `ops/tools/check_programs.py` | 769 | فحص: برامج الأسرة (رمضان · رحلة الصلاة · المراحل) سليمة المراجع ومتطابقة اللغتين |
| `ops/tools/check_quoted_texts.py` | 232 | فاحص النصوص الشرعية المقتبسة — بلاغ لا تصحيح |
| `ops/tools/check_quran_citations.py` | 173 | Verify every Qur'an citation in the app against the mushaf text. Verses quoted anywhere else in the app (﴿…﴾, «قال تعالى: …») are checked by |
| `ops/tools/check_quran_rendering.py` | 199 | فحص: القرآن لا يُترجَم — وأي معنًى بالإنجليزية يُعلَن أنه تفسير |
| `ops/tools/check_scholar_quotes.py` | 367 | check_scholar_quotes.py — «قال ابن القيم…»: هل لهذه النسبة سندٌ نراه؟ (كتاب العالم نفسه، أو اسمه في نص المصدر، أو موضع مسجَّل من turath.io)؛ `check` بلا شبكة، `verify` يسأل تراث |
| `ops/tools/check_scripture_coverage.py` | 199 | Every quoted ayah and hadith the app ships — not just the ones in one file. Why this guard exists (2026-10-04) |
| `ops/tools/check_served_assets.py` | 259 | Verify that what lesson_index.json promises is what this host can serve. Two production incidents motivate this, both invisible until a human noticed: |
| `ops/tools/check_sira_stories.py` | 665 | 🛡️ حارس «من السيرة النبوية»: كل «» حرفي برقمه من الصحيحين، قائمة منع لتفاصيل غير صحيحة، دعم عائلتين؛ pre-commit + CI |
| `ops/tools/chroma_recall_capture.py` | 261 | Build disposable indexes from frozen real vectors; never migrate a database. Only the CLI's experiment modes import ML/Chroma. The comparator remains… |
| `ops/tools/chroma_recall_probe.py` | 232 | Compare captured retrieval IDs. Never opens Chroma, models, or the network. COMPARISON_COMPLETE describes supplied report coverage, never an upgrade… |
| `ops/tools/chroma_runtime_probe.py` | 398 | Hosted, copied-index runtime proof. Never run against a production volume. Build uses the application's index_seed entry point. Candidate uses real |
| `ops/tools/content_surfaces.py` | 341 | Every text the app ships to a parent or a child — as the scripture guards see it. Why one enumerator |
| `ops/tools/deepen_paths.py` | 1091 | تعميق المسارات بالطلب — دروس مكتوبة من الوحدات، وطعنٌ من عائلة نماذج أخرى |
| `ops/tools/deploy_gate.py` | 360 | Deploy gate — production only gets a commit whose hosted tests passed. deploy.yml runs this on a GitHub-hosted runner, as a job the production job |
| `ops/tools/eval_answers.py` | 396 | Answer-quality evaluation harness. Runs every golden-set question through the real pipeline (in-process |
| `ops/tools/eval_ollama_compare.py` | 410 | Judge + rule-check a head-to-head run from eval_ollama_models.py. python ops/tools/eval_ollama_compare.py ops/eval/runs/<label>_<ts>.jsonl --a… |
| `ops/tools/eval_ollama_direct.py` | 71 | Direct (no pipeline, no retrieval) head-to-head — the July v3/v4/v5 method. Each question goes to Ollama /api/generate as-is, with the model's own |
| `ops/tools/eval_ollama_models.py` | 224 | Head-to-head of local Ollama models through the real /assistant/draft pipeline. Every golden-set question goes through the pipeline once per model,… |
| `ops/tools/export_real_parent_corpus.py` | 440 | export_real_parent_corpus.py — Pure-Python, zero-model exporter that prepares the anonymized Real Parent Questions & Knowledge Base bundle for Google… |
| `ops/tools/extract_app_content.py` | 681 | Move the app's hard-coded Arabic content out of Dart and into JSON assets. Why this exists as a tool rather than a one-off edit |
| `ops/tools/fal_common.py` | 125 | fal_common — الهوية البصرية الموحّدة + سجل موديلات fal.ai المشترك بين gen_visuals.py وgen_launch.py. |
| `ops/tools/feedback_digest.py` | 59 | feedback_digest — تقرير قرارات قابل للقراءة من تحليل الفيدباك الذكي. التشغيل (من جذر المشروع، مع DEEPSEEK_API_KEY مضبوط): |
| `ops/tools/fix_arabic_encoding.py` | 126 | Fix Arabic encoding issues in knowledge units by regenerating text_simplified using a local LLM (qwen2.5:3b) that handles Arabic well. |
| `ops/tools/fix_arabic_encoding_v2.py` | 131 | Fix Arabic encoding issues by regenerating text_simplified from behavior_type + domain + reference_info using qwen2.5:3b (local, good for Arabic).… |
| `ops/tools/fix_translation_defects.py` | 341 | إصلاح ملاحظات المراجع على الترجمة الإنجليزية — بثلاث بوابات لا بثقة |
| `ops/tools/fonts/Cairo-Bold.ttf` |  | خط |
| `ops/tools/fonts/Cairo-Regular.ttf` |  | خط |
| `ops/tools/gen_launch.py` | 142 | gen_launch — أصول إطلاق + هيرو صفحة الهبوط (نفس هوية gen_visuals، بلا نص). الموديل الافتراضي: Recraft V3. (جُرّب Flux 2 Pro ونانو بنانا برو ورُفضا… |
| `ops/tools/gen_lottie.py` | 273 | gen_lottie — generate lightweight, brand-aligned Lottie animations for Tutor Guardian celebrations. |
| `ops/tools/gen_print_qr.py` | 51 | gen_print_qr — the QR code printed at the foot of every printable sheet. Writes frontend/assets/print/qr_<CODE>.svg. |
| `ops/tools/gen_sfx.py` | 293 | gen_sfx — synthesise the app's five interface sounds from code. The owner's decision is «أصوات ناعمة بلا موسيقى»: soft sounds, no music. So |
| `ops/tools/gen_visuals.py` | 271 | gen_visuals — توليد المحتوى البصري المخصّص لـ«المربّي» بأسلوب موحّد محتشم. الموديل الافتراضي: Recraft V3 (~$0.04/صورة). جُرّب الترقية لـFlux 2 Pro… |
| `ops/tools/generate_dataset_v2.py` | 349 | Fine-tune dataset v2 generator — Azure DeepSeek backed. Produces ~4k instruction/output pairs in the Phase-3 structured answer |
| `ops/tools/generate_qa_dataset.py` | 266 | Generate QA dataset for Tutor Guardian fine-tuning. Reads knowledge units from the KB and uses an LLM to generate realistic parent questions +… |
| `ops/tools/generate_real_gap_kb_units.py` | 870 | generate_real_gap_kb_units.py — Generates 25 schema-validated Knowledge Base units covering the top real-parent KB gaps discovered by `Gemma 4 31B`… |
| `ops/tools/generate_tip_cards.py` | 369 | generate_tip_cards.py — توليد كروت نصائح يومية مربعة (1080x1080) مطابقة لتصميم ShareableMomentCard الفاخر والمعتمد في كود تطبيق المربّي الذكي. يستخدم… |
| `ops/tools/generate_veo_assets.py` | 141 | Tutor Guardian - Google Veo Video Generation Tool This tool generates high-quality camera zoom-in/fly-through video clips |
| `ops/tools/golden_ci.py` | 303 | Nonblocking golden reports; offline retrieval is never answer quality. Full mode delegates generation and judging to eval_answers, only after an |
| `ops/tools/golden_ci.sh` | 26 | Hosted candidate only. No .env, production volume, or provider credential. |
| `ops/tools/ingest_pdf.py` | 537 | Unified PDF-to-knowledge-units ingest pipeline. Batch-processes PDFs from raw_sources/<domain>/ and generates knowledge unit |
| `ops/tools/ingest_source.py` | 263 | Pipeline to ingest a source document (PDF or TXT) and convert to knowledge units. Flow: |
| `ops/tools/ingest_tarbiya_alwan.py` | 205 | يسحب وحدات معرفة من ملف Tarbiya_Al_Awlad_Alwan.txt - ينظف OCR (يزيل الأسطر القصيرة والرموز) - يقسم حسب العناوين (الباب، الفصل، إلخ) مع fallback لـ… |
| `ops/tools/kb_gap_judge.py` | 303 | Judge each (question, retrieved unit) pair for topical relevance. The judge applies a narrow rubric. A model judging a model's retrieval is only |
| `ops/tools/language_rank_probe.py` | 139 | قياس ترتيب اللغة: ماذا كسبت العربية، وماذا خسرت الإنجليزية |
| `ops/tools/llm_stats.py` | 202 | LLM Call Stats — تقرير من sessions.db Reads the ops/sessions.db (llm_calls table) and prints summary stats. |
| `ops/tools/media_index.py` | 69 | تسجيل الميديا في docs/lesson_index.json — إدراج أو استبدال، لا إسناد |
| `ops/tools/normalize_units.py` | 153 | One-time data normalizer — تنظيف قيم enum المتسخة في وحدات المعرفة Repairs whitespace, typos, and garbage values in the `severity` and |
| `ops/tools/ocr_pdf.py` | 85 | OCR extraction for Arabic/English PDFs using Tesseract + pdf2image. Saves extracted text as .txt sidecar files for use by ingest_source.py. |
| `ops/tools/process_collected_questions.py` | 213 | Process collected real-world parent questions through the RAG pipeline. Reads collected_questions.json, generates RAG-grounded answers for each… |
| `ops/tools/push_kaggle_v6_dpo_kernel.py` | 385 | Push Phase 2 DPO Alignment Kernel (`tg-tutor-v6-dpo`) to Kaggle `GpuT4x2`. Trains Direct Preference Optimization (DPO) on top of… |
| `ops/tools/push_kaggle_v6_kernel.py` | 486 | push_kaggle_v6_kernel.py — Publishes the v6 dataset to the private Kaggle dataset (`YOUR_KAGGLE_USER/tg-qa-dataset`) and pushes the automated v6 GPU… |
| `ops/tools/refresh_source_map.py` | 169 | إعادة بناء source_to_lesson.json من الحالة الحيّة للدفتر |
| `ops/tools/repair_device_twins.py` | 316 | Re-attach families whose install split into device twins — one-off repair. From 1.0.58 to 1.0.67 every app process ran main() twice, and on a fresh |
| `ops/tools/retrieval_probe.py` | 129 | Measure retrieval precision locally — never against the production index. Runs the real pipeline (classify → rewrite → retrieve_hybrid) over realistic |
| `ops/tools/revalidate_translations.py` | 266 | إعادة تحقّق من ترجمات المنهج الإنجليزية — عدّ حقيقي بدل سجلات بائتة |
| `ops/tools/review_en_parity.py` | 2549 | بوابة المحتوى الإنجليزي — مراجعة آلية بنموذجين من عائلتين، ثم ختم موثَّق |
| `ops/tools/run_gemma4_31b_real_questions_teacher.py` | 448 | run_gemma4_31b_real_questions_teacher.py — Runs `gemma4:31b` on Ollama Cloud (pure HTTP API, zero local models) over real parent questions to: |
| `ops/tools/runtime_readiness_report.py` | 275 | Manual trusted-main diagnostic. Only ciphertext leaves the existing container. No application startup, schema migration, bootstrap, provider call or… |
| `ops/tools/scripture_scan.py` | 481 | Find quoted scripture inside free text, and say whether it is sound. The structured guards check an item that declares itself — `kind: hadith` with |
| `ops/tools/seed_vps_answer_cache_from_teacher.py` | 145 | seed_vps_answer_cache_from_teacher.py — Exports all clean, standalone `Gemma 4 31B` gold-standard answers (plus the 25 new KB gap units) into a… |
| `ops/tools/sira_sources.py` | 224 | توثيق قصة سيرة من مصادرها (البخاري/مسلم بطبعة مثبّتة + الآيات) إلى `ops/data/sira/`؛ يدوي |
| `ops/tools/social_media_autoposter.py` | 402 | social_media_autoposter.py — أداة النشر التلقائي لمنشورات التسويق والتربية اليومية. تقرأ النصائح من knowledge_base/curriculum/daily_tips/*.json مع… |
| `ops/tools/test_post_infographic.py` | 55 | test_post_infographic.py — سكربت اختبار سريع لنشر أحد الانفوجرافات المائية على جميع الحسابات (تليجرام وبفر) فوراً. |
| `ops/tools/tests/test_bare_mint_readiness.py` | 60 | `bare_mint_readiness.py`: أعداد فقط، قراءة فقط، لا معرّف جهاز |
| `ops/tools/tests/test_runtime_readiness_report.py` | 301 | Offline privacy, read-only and encryption contracts; no production access. |
| `ops/tools/tests/test_social_media_autoposter.py` | 202 | Offline regression tests: importing/selecting/dry-running must never publish. |
| `ops/tools/translate_curriculum.py` | 476 | ترجمة المنهج إلى الإنجليزية — خط إنتاج بمراجعة عدائية |
| `ops/tools/translate_knowledge_base.py` | 261 | ترجمة قاعدة المعرفة إلى الإنجليزية — وحدات جديدة، لا استبدال |
| `ops/tools/translate_stories.py` | 445 | ترجمة قصص الأطفال إلى الإنجليزية — نفس خط الإنتاج بمراجعة عدائية |
| `ops/tools/upload_ultra_bundle_to_hf.py` | 63 | upload_ultra_bundle_to_hf.py — Uploads the anonymized & Teacher-distilled Google Colab Ultra bundle (`tg_colab_ultra_bundle.zip` + individual… |
| `ops/tools/validate_age_groups.py` | 42 | Validate that every age_group in knowledge_base/units/*.json maps to a canonical value. Exits with code 1 if any unknown age_group is found without a… |
| `ops/tools/validate_knowledge_units.py` | 69 | التحقق من ملفات وحدات المعرفة مقابل JSON schema (يُذكر في README) |
| `ops/tools/watermark_infographics.py` | 86 | watermark_infographics.py — سكربت لإضافة لوجو التطبيق تلقائياً وعلامة مائية على الانفوجرافات المولدة مسبقاً وتصديرها لمجلد التسويق لتكون جاهزة للنشر. |
| `ops/tools/write_infographic_prompts.py` | 319 | كتابة بلوكات برومبت الإنفوجراف للدروس التي لا تملك واحدًا |

### ops/ — بقية الملفات النصية (kaggle/colab/eval/ollama/تقارير)

| الملف | أسطر | الدور |
|---|---:|---|
| `ops/ARTEMIS_CANDIDATE.md` | 44 | ARTEMIS — أتمتة أندرويد للمربّي (مرشح مسجّل، مش متبنّى بعد) |
| `ops/FINE_TUNING.md` | 182 | دليل النموذج وتوليد بيانات التدريب (Fine-Tuning) |
| `ops/FIQH_GUARD.md` | 167 | الفقه الحارس — Guard rules for fiqh/aqeedah answers (Almorabbi assistant) |
| `ops/FIQH_GUARD_EXECUTION_LOG.md` | 32 | FIQH_GUARD v3 — ملخص التنفيذ (2026-09-10) |
| `ops/RELEASE_v1.0.61.md` | 171 | Release v1.0.61 (build 106) — backend schema v27 + audit hardening |
| `ops/colab/finetune_gemma4_ultra.ipynb` |  | دفتر Colab لضبط Gemma4 (تاريخي) |
| `ops/colab/finetune_tg.ipynb` |  | دفتر Colab لضبط نموذج المربّي (تاريخي) |
| `ops/eval/golden_set.jsonl` |  | المجموعة الذهبية لتقييم جودة الإجابات (تستعملها golden_ci/eval_answers) |
| `ops/eval/memory_set.jsonl` |  | مجموعة تقييم ذاكرة الطفل |
| `ops/evaluation/lora_eval_questions.json` |  | أسئلة تقييم LoRA مقابل tg-tutor:v4 |
| `ops/generate_units.py` | 272 | Generate 30 knowledge unit JSON files for Tutor Guardian. |
| `ops/kaggle/build_notebook.py` | 234 | Assemble the command-r Kaggle notebook (finetune_tg_kaggle.ipynb). Authoritative source for the cells. Incorporates the fixes proven on Kaggle: |
| `ops/kaggle/finetune_commandr_kaggle.py` | 138 | Kaggle T4 QLoRA fine-tune — المربّي / tg-tutor on command-r7b-arabic. Base model decided 2026-06-26 by head-to-head eval (beat qwen2.5:3b 3.75 vs… |
| `ops/kaggle/finetune_tg_kaggle.ipynb` |  | دفتر Kaggle مولَّد لضبط command-r7b-arabic |
| `ops/kaggle/kernel-metadata.json` |  | بيانات kernel Kaggle |
| `ops/ollama/Modelfile.tg-tutor` |  | Modelfile نموذج tg-tutor المحلي |
| `ops/reports/PLAY_REVIEW_REPLIES.md` | 80 | ردود تعليقات Google Play — مسوّدات جاهزة |
| `ops/reports/PODCAST_REGEN_TODO.md` | 107 | > **مغلق — 2026-08-10.** الصفر بودكاست تحت 2MB على القرص، فكل المدخلات المعلّمة **BAD |
| `ops/reports/QA-REPORT.md` | 312 | > **حالة المتابعة — 2026-08-10 (تحقُّق، لا افتراض).** كل البنود الستة إمّا أُصلحت أو لم تعد |
| `ops/reports/SCREEN_GUIDANCE_FIVE_ITEM_REVIEW_OCT7.md` | 27 | Screen guidance: five-item source and translation closeout |
| `ops/reports/SCREEN_GUIDANCE_REVISED_AAP_OCT7.md` | 88 | Revised AAP screen guidance — source correction, 2026-10-07 |
| `ops/reports/SCREEN_GUIDANCE_SOURCE_OCT7.md` | 67 | Screen guidance source correction — 2026-10-07 |
| `ops/reports/SOURCE_COMPLETION_CHANGED_PATHS_OCT7.txt` | 67 | ملف نصي |
| `ops/reports/SOURCE_COMPLETION_OCT7.md` | 118 | Source completion: six current approvals and two nonknowledge quarantines |
| `ops/reports/SOURCE_FINAL_SIX_OCT7.md` | 69 | Final six primary-source recoveries and canonical parity |
| `ops/reports/SOURCE_FOUR_B_EN_REVIEW_OCT7.json` |  | ملف بيانات/إعداد JSON |
| `ops/reports/SOURCE_FOUR_B_EN_REVIEW_OCT7.md` | 35 | Three real-source English parity reviews — 2026-10-07 |
| `ops/reports/SOURCE_FOUR_B_EN_VALIDATION_OCT7.json` |  | ملف بيانات/إعداد JSON |
| `ops/reports/SOURCE_JUSTICE_PLAY_RECOVERY_OCT7.md` | 25 | Three-unit primary-source recovery: justice and play |
| `ops/reports/SOURCE_JUSTICE_PLAY_TRANSLATION_REVIEW_OCT7.md` | 19 | Justice and play: actual translation-review closeout |
| `ops/reports/SOURCE_LAST_LASTB_OCT7.md` | 47 | Native last-three source recovery — 2026-10-07 |
| `ops/reports/SOURCE_LAST_LASTB_VALIDATION_OCT7.json` |  | ملف بيانات/إعداد JSON |
| `ops/reports/SOURCE_RECOVERY_FOUR_B_OCT7.md` | 30 | Four-unit native primary-source recovery B |
| `ops/reports/SOURCE_RECOVERY_NEXTBATCH_AUDIT_OCT7.md` | 107 | Six-pair source recovery and nonknowledge impact audit |
| `ops/reports/quoted_texts_audit.json` |  | ملف بيانات/إعداد JSON |
| `ops/reports/quoted_texts_audit_post_committees.json` |  | ملف بيانات/إعداد JSON |
| `ops/reports/sharia_review_2026-08-11.md` | 92 | تقرير المراجعة الشرعية — المنهج العربي |
| `ops/reports/sharia_review_final_2026-08-11.md` | 100 | تقرير المراجعة الشرعية الشاملة — العربي + الإنجليزي |
| `ops/tests/test_chroma_recall_capture.py` | 253 | Frozen-input and failure-report tests; no model downloads or live databases. |
| `ops/tests/test_chroma_recall_probe.py` | 152 | Report arithmetic/control-flow fixtures, never a real Chroma recall claim. |
| `ops/tests/test_chroma_recall_workflow.py` | 46 | Safety contract for the manually dispatched hosted experiment. |
| `ops/tests/test_chroma_runtime_probe.py` | 198 | Runtime harness contracts without model downloads or Chroma installs. |
| `ops/tests/test_chroma_runtime_workflow.py` | 43 | Manual hosted runtime experiment must never become a deployment gate. |
| `ops/tests/test_golden_ci.py` | 265 | Reporting/control-flow regressions; these are not answer-quality scores. |

### ops/data/ — سكربتات داخل مجلدات البيانات

| الملف | أسطر | الدور |
|---|---:|---|
| `ops/data/en_parity_pending/review-2026-10-07-held/evidence_consult.py` | 68 | تقديم أدلة النص الأولي لبند محجوز إلى عائلتي المراجعة (يستعمل نقل review_en_parity.post) |
| `ops/data/en_parity_pending/review-2026-10-07-held/run_review.py` | 66 | غلاف مسجِّل حول review_en_parity run (FRESH_CACHE، يتوقف عند 429) |
| `ops/data/en_parity_pending/review-2026-10-07/run_review.py` | 45 | غلاف مسجِّل يحفظ كل ردّ خام للنماذج كدليل حول review_en_parity run |

**`ops/data/` (بيانات تشغيلية متعقَّبة — راجع 04-data.md):**

| المجموعة | عدد الملفات | ما هي |
|---|---:|---|
| `ops/data/en_unpublished/` | 468 (json×468) | محتوى إنجليزي مترجم غير منشور (مصادر وحدات + MANIFEST) بانتظار بوابة المراجعة |
| `ops/data/quarantine_high_severity/` | 41 (json×40, md×1) | وحدات عالية الخطورة موضوعة في الحجر |
| `ops/data/deepen_paths/` | 36 (json×35, md×1) | مخرجات «تعميق المسارات» وبصمات النسخ الاحتياطية |
| `ops/data/kb_fidelity/` | 35 (json×33, md×2) | تقارير أمانة الوحدات لمصدرها + استرداد المصادر |
| `ops/data/en_parity_pending/` | 31 (json×24, log×3, md×2, txt×2 — الـpy الثلاثة لها صفوف فردية أعلاه) | طابور/سجلات مراجعة تكافؤ الإنجليزي؛ منها `parent-doubts-units/` (7 توائم إنجليزية جاهزة غير مخدومة + README) |
| `ops/data/adhkar_review/` | 7 (json×4, md×3) | مراجعة حزمة الأذكار |
| `ops/data/clinical_seed_safety/` | 6 (json×6) | مراجعة سلامة البذور السريرية |
| `ops/data/tip_reviews/ + program_reviews/` | 2 (json×2) | مراجعات النصائح والبرامج |
| `ops/data/anbiya/` | 20 (json×20) | لقطات مصادر قصص الأنبياء (آيات + الميسّر) — يكتبها `anbiya_sources.py` ويقرؤها `check_anbiya_stories.py` |
| `ops/data/sira/` | 8 (json×8) | لقطات مصادر قصص السيرة (`<id>.sources.json`) — يكتبها `sira_sources.py` ويقرؤها `check_sira_stories.py`؛ مسار يُطلق `backend.yml` |
| `ops/data/scholar_quotes/` | 1 (json×1) | `verified.json`: نِسب لأهل العلم وُجدت في كتبهم على turath.io بالكتاب والصفحة — يكتبه `check_scholar_quotes.py verify` ويقرؤه `check` |
| `ops/data/ (ملفات الجذر)` | 15 (json×10, gz×2, md×1, csv×1) | حالات الترجمة/البودكاست/الفيديو، أسئلة مجمّعة (collected_questions*), فهرس الأحاديث المضغوط، campaign_codes.md, campaign_spend.csv, qa_dataset_clean.jsonl |

## 6) السكربتات — `scripts/` (مولّدات المحتوى والنشر)


### scripts/

مولّدات دروس/وسائط NotebookLM، رفع Play، ريلز، كرونات توليد (تعمل غالبًا على اللابتوب/tg-home لا الإنتاج).

| الملف | أسطر | الدور |
|---|---:|---|
| `scripts/README_reels.md` | 77 | Reels Production Pipeline |
| `scripts/add_new_lesson_podcasts.py` | 141 | One-shot: register the 25 newly-authored lessons in the podcast pipeline. Uploads ONLY the new lesson markdown sources (knowledge_base/notebooklm/**/ |
| `scripts/adhkar_tips_en.py` | 794 | English wording for the 124 `tip` items in the family adhkar pack. Kept as a separate, reviewable table rather than generated at build time: these |
| `scripts/archive/audit_age_groups.py` | 35 | مدقّق age_group قديم (نُقل من `knowledge_base/units/` 2026-11-08؛ مسار نسبي للريبو) |
| `scripts/archive/cleanup_duplicate_podcasts.py` | 56 | أرشيف: حذف بودكاستات مكررة بالـmd5 |
| `scripts/archive/download_all_podcasts.py` | 53 | أرشيف: تنزيل كل البودكاستات من دفتر NotebookLM (مسارات مطلقة) |
| `scripts/archive/download_missing_podcasts.py` | 84 | Load missing lessons |
| `scripts/archive/download_missing_podcasts_v2.py` | 90 | Get all artifacts once |
| `scripts/archive/download_podcasts_final.py` | 58 | أرشيف: تنزيل بودكاستات (النسخة النهائية) |
| `scripts/archive/download_podcasts_v2.py` | 52 | أرشيف: تنزيل بودكاستات v2 |
| `scripts/archive/download_podcasts_v3.py` | 52 | أرشيف: تنزيل بودكاستات v3 |
| `scripts/archive/fix_missing_podcasts.py` | 60 | أرشيف: إصلاح البودكاستات الناقصة |
| `scripts/archive/gen_podcasts_cron.py` | 150 | Cron-safe podcast generator for the 48 new lessons (NotebookLM audio). Mirror of gen_path_videos_cron.py but for audio overviews. Idempotent (skips |
| `scripts/archive/generate_arabic_videos.py` | 182 | أرشيف: توليد فيديوهات عربية لدروس محددة |
| `scripts/archive/integrate_existing_podcasts.py` | 93 | أرشيف: دمج بودكاستات موجودة في lesson_index |
| `scripts/archive/integrate_videos.py` | 190 | Add video assets to lesson_index.json and create a video index. 8 golden lesson videos (English-language for now, Arabic version to be generated |
| `scripts/archive/match_missing_podcasts.py` | 67 | أرشيف: مطابقة دروس بلا بودكاست مع ملفات موجودة |
| `scripts/archive/poll_and_download.py` | 57 | Poll NotebookLM tasks and download completed podcasts automatically. |
| `scripts/archive/sync_podcasts.py` | 251 | Idempotent podcast generator for tutor-guardian. Reads production_registry.md to find sources that need podcasts. |
| `scripts/build_lesson_index.py` | 364 | Build unified lesson index from AI-generated assets. Combines: |
| `scripts/check_buffer_post_status.py` | 121 | Read the real outcome of Buffer posts — did the network actually publish? Buffer accepting a post only means it entered the queue. This asks Buffer… |
| `scripts/check_new_lessons.py` | 19 | فحص أصول الدروس الجديدة مقابل lesson_index |
| `scripts/clean_notebooklm_duplicates.py` | 173 | Regex to find lesson IDs, e.g. lesson_16-18_medical_adult_transition_03 or lesson_4-6_islamic_parenting_adab_01 |
| `scripts/cleanup_reports_and_indices.py` | 168 | Cleanup curriculum assets: 1. Strips LLM preamble and "Answer:" block from Markdown reports. 2. Translates English domain/topic names to Arabic in… |
| `scripts/complete_toddler_curriculum.py` | 158 | Complete the 2-3 ("toddler") age band: generate sourced lesson bodies from the user's NotebookLM "المربي" notebook and write proper curriculum lesson… |
| `scripts/compose_screenshots.py` | 85 | تركيب لقطات متجر Play (مسارات مطلقة) |
| `scripts/cron_gen_en_media.sh` | 477 | Daily English media generation — harvest first, then each medium on its own |
| `scripts/cron_gen_path_videos.sh` | 56 | Periodic NotebookLM path-video generation for the 12 new paths, until done. |
| `scripts/cron_gen_podcasts.sh` | 91 | Periodic NotebookLM podcast generation, one language per invocation. |
| `scripts/cron_regen_podcasts.sh` | 31 | Daily retry of NotebookLM podcast regeneration until all 53 placeholder |
| `scripts/demo_grounded_generation.py` | 82 | تجربة توليد مؤصّل من كتاب PDF عبر NotebookLM (معرّف دفتر مكتوب) |
| `scripts/demo_media_generation.py` | 107 | Configuration |
| `scripts/emulator_controller.py` | 82 | تحكم بالمحاكي عبر adb (مسار SDK مطلق) |
| `scripts/expand_lessons.py` | 275 | Expand the curriculum so every path has >=4 lessons (broad expansion across all ages, per the maintainer's choice). 25 hand-authored text lessons — NOT… |
| `scripts/export_to_notebooklm.py` | 234 | تحويل دروس المنهج إلى Markdown مجمّعة بالعمر لـNotebookLM |
| `scripts/extract_hero_frames.py` | 71 | Extract, resize, and compress video frames from Flow video for canvas scroll scrubbing. |
| `scripts/fill_all_lesson_media.py` | 198 | Fill missing lesson media so EVERY lesson in docs/lesson_index.json has both a podcast (edge-tts) and a video (PIL title card + ffmpeg). The index… |
| `scripts/fix_failed_assets.py` | 130 | A real section runs to thousands of characters. Anything shorter is a failed |
| `scripts/ga4_cohort_report.py` | 193 | Daily-cohort retention + acquisition report from GA4. Answers the two questions the Meta campaign decision hangs on: |
| `scripts/gen_aqeedah_infographics_batch.py` | 131 | Generate remaining aqeedah infographics one by one with per-lesson timeout. |
| `scripts/gen_flashcards_quizzes.py` | 180 | Generate flashcards + quizzes for the 25 new lessons (the _bNN ones) from their own text, using the local Ollama model with forced-JSON output. Saves… |
| `scripts/gen_lesson_videos.py` | 155 | Local video generator for the new lessons (NotebookLM is rate-limited). Builds a clean title-card (domain gradient + shaped Arabic title) and renders… |
| `scripts/gen_path_videos_cron.py` | 416 | Cron-safe path-video generator (NotebookLM video overviews), any language. python3 scripts/gen_path_videos_cron.py # Arabic (ar_eg) |
| `scripts/gen_podcasts_cron.py` | 484 | Cron-safe podcast generator (NotebookLM audio overviews), any language. Mirror of gen_path_videos_cron.py but for audio. Idempotent (skips lessons… |
| `scripts/gen_tts_podcasts.py` | 82 | Local-ish alternative to NotebookLM: narrate each new lesson as an MP3 using edge-tts (Microsoft free neural TTS, Arabic Egyptian voice). Reads only… |
| `scripts/generate_all_podcasts.py` | 172 | توليد بودكاست لكل الدروس عبر notebooklm CLI |
| `scripts/generate_all_podcasts_v2.py` | 212 | generate_all_podcasts_v2.py Upload missing lesson markdown files to NotebookLM, then trigger + poll + download podcasts. Handles both lessons with… |
| `scripts/generate_arabic_podcasts.py` | 159 | توليد بودكاستات عربية |
| `scripts/generate_clean_assets.py` | 2158 | Clean per-lesson interactive assets (flashcards + quiz), authored from each lesson's own content — replacing the broken NotebookLM batch. |
| `scripts/generate_gap_fill_units.py` | 355 | Gap-filling content generator — knowledge units for the top-9 repeated parent-question themes that retrieval failed to serve (2026-08-26 week, 215… |
| `scripts/generate_lesson_01_assets.py` | 183 | Configuration |
| `scripts/generate_missing_data_tables.py` | 332 | Generate missing data_table assets for lessons using NotebookLM ask. Outputs: |
| `scripts/generate_missing_infographics.py` | 696 | Generate missing infographic assets for lessons using NotebookLM. Trigger-then-harvest, like gen_podcasts_cron.py — NOT the old blocking |
| `scripts/generate_missing_path_videos.py` | 144 | توليد فيديوهات المسارات الناقصة |
| `scripts/generate_missing_podcasts.py` | 125 | Generate the NotebookLM episode for every lesson whose index entry has none. Reads docs/lesson_index.json, finds lessons with an empty `podcasts`… |
| `scripts/generate_missing_reports.py` | 323 | Generate missing report assets for lessons using NotebookLM ask. Reads scripts/missing_reports_full.json (output with source_id, lesson_id,… |
| `scripts/generate_new_lesson_md.py` | 67 | Generate NotebookLM markdown source files for the 25 newly-authored lessons (ids ending in _bNN) so the existing podcast pipeline can upload them as… |
| `scripts/generate_path_videos.py` | 145 | توليد فيديوهات المسارات |
| `scripts/generate_pending_text_assets.py` | 174 | Configuration |
| `scripts/generate_toddler_lessons.py` | 251 | Correct answer goes to a spread, deterministic slot — the same one |
| `scripts/infographic_prompts.md` | 1567 | Infographic Prompts for Tutor Guardian — 78 Missing Lessons |
| `scripts/infographic_prompts_lib.py` | 134 | infographic_prompts_lib — استخراج بلوكات البرومبت لكل درس من scripts/infographic_prompts.md، وحساب الدروس الناقصة فيها إنفوجرافيك. |
| `scripts/infographics_blocked.json` |  | ملف بيانات/إعداد JSON |
| `scripts/lib/nblm_session.sh` | 225 | shellcheck shell=bash |
| `scripts/link_lessons_to_units.py` | 60 | Link the 25 new hand-authored lessons (unit_ids == []) to the most relevant knowledge-base units, so the lesson screen stops showing "مرتبط بـ 0… |
| `scripts/make_youtube_short.py` | 185 | Convert a tutor-guardian path video into a YouTube Short (9:16) with captions and CTA. Usage: |
| `scripts/migrate_age_groups.py` | 39 | ترحيل age_group في lesson_index إلى القيم القانونية |
| `scripts/missing_data_tables.json` |  | ملف بيانات/إعداد JSON |
| `scripts/missing_reports.json` |  | ملف بيانات/إعداد JSON |
| `scripts/missing_reports_full.json` |  | ملف بيانات/إعداد JSON |
| `scripts/missing_reports_no_source.json` |  | ملف بيانات/إعداد JSON |
| `scripts/monitor_qa_v2.sh` | 49 | Monitor tutor-guardian v2 fine-tune dataset generation. |
| `scripts/nblm_failure.py` | 63 | تصنيف إخفاق NotebookLM: جلسة ميتة ≠ مهمة اختفت؛ يستعمله مولّدو البودكاست/الفيديو/الإنفوجراف (exit 3 = جلسة ميتة، 4 = حاول ولم يُنتج) |
| `scripts/parse_all_assets.py` | 250 | Parse markdown asset files -> JSON flashcards + slides Updates lesson_index.json and creates JSON files in docs/lesson_assets/ |
| `scripts/parse_generated_assets.py` | 138 | Output files |
| `scripts/play_listing_upload.py` | 267 | Google Play — store-listing refresh (text + graphics) for المربّي. One Play edit replaces, for each language in the listing folder: |
| `scripts/play_reviews.py` | 170 | تعليقات Google Play — قراءة والرد |
| `scripts/play_upload.py` | 312 | Google Play Store — رفع AAB تلقائي الاستخدام: |
| `scripts/podcast_prompt.txt` | 6 | ملف نصي |
| `scripts/podcast_source_map.json` |  | ملف بيانات/إعداد JSON |
| `scripts/podcast_to_reel.py` | 424 | podcast_to_reel.py — convert a tutor-guardian podcast into a 9:16 marketing Reel. Usage: |
| `scripts/prepare_play_assets.py` | 63 | 1. Copy App Icon |
| `scripts/publish_reels_to_buffer.py` | 279 | Publish generated tutor-guardian reels to Buffer (Instagram/TikTok/Facebook). Flow: |
| `scripts/reel` |  | اختصار bash لمصنع الريلز من أي مجلد |
| `scripts/reel_from_video.py` | 652 | مصنع الريلز — v2: يقصّ من فيديوهات المنهج بدل توليد صورة ثابتة |
| `scripts/reels_pipeline.py` | 51 | tutor_reels: generate reels. Publishing is a separate, deliberate step. It used to generate and publish in one run, which meant the first time anyone |
| `scripts/regen_podcasts.py` | 133 | Regenerate REAL NotebookLM audio for lessons whose local docs/ file is an edge-tts placeholder, then download + place it at the correct path. |
| `scripts/release_bundle.py` | 180 | Inspect unsigned hosted AABs and locally signed copies. Never signs or uploads. |
| `scripts/release_play_publish.py` | 163 | Publish the exact validated signed artifact at 100%; no build or signing. |
| `scripts/release_play_validate.py` | 130 | Validate a verified, locally signed AAB in our temporary Play edit. Never commits. |
| `scripts/remove_bad_podcasts.py` | 57 | Find all mp3 files created in the last 3 days (these are the bad ones) |
| `scripts/reports_blocked_broken_source.json` |  | ملف بيانات/إعداد JSON |
| `scripts/resume_infographics_cron.sh` | 42 | Resumable infographics batch driver (cron-friendly). |
| `scripts/seed_common_gap_units.py` | 152 | Seed high-quality knowledge units for the most common parenting concerns that were proven gaps in the KB (picky eating, tantrums, sleep, bedwetting,… |
| `scripts/seed_common_gap_units_2.py` | 126 | Batch 2 of curated knowledge units for common parenting gaps. Same approach as scripts/seed_common_gap_units.py: hand-authored (not |
| `scripts/seed_flashcards_quizzes.py` | 756 | Hand-authored flashcards + quizzes for the 25 new lessons (the maintainer asked me to write them, not the local model). Each lesson gets 3 flashcards… |
| `scripts/seed_infant_pregnancy_curriculum.py` | 433 | Seed script for Infant & Pregnancy (الحمل والرضع) Curriculum Content Canonical age_group: prenatal-1 |
| `scripts/seed_infant_pregnancy_curriculum_en.py` | 307 | Seed script for English Infant & Pregnancy (الحمل والرضع) Curriculum Content Writes: |
| `scripts/seed_prenatal_assets.py` | 240 | Seed hand-crafted, high-yield interactive assets (flashcards + quizzes) for the 5 lessons of the "prenatal-1" infant_pregnancy track. Wired into… |
| `scripts/sharia_review_en.py` | 347 | Independent Sharia review of English translations vs Arabic originals. v2: Proper Arabic word boundaries, distinguishes verb خلق from noun خُلق,… |
| `scripts/sharia_review_report.json` |  | ملف بيانات/إعداد JSON |
| `scripts/sync_index_with_curriculum.py` | 109 | Add published curriculum lessons that docs/lesson_index.json does not know. The index is what the API turns into lesson assets (curriculum_loader… |
| `scripts/test_app_flow.py` | 46 | اختبارات: app flow |
| `scripts/test_navigation.py` | 41 | اختبارات: navigation |
| `scripts/tests/test_landing_copy.py` | 34 | Focused copy guards; no server startup or external services. |
| `scripts/tests/test_play_listing_upload.py` | 339 | Store-listing refresh; fake Play client, no network, no credentials. |
| `scripts/tests/test_program_review_metadata.py` | 27 | Program reviewer metadata must describe model review without specialist approval. |
| `scripts/tests/test_release_bundle.py` | 287 | Offline synthetic ZIP tests; never compile, sign, or contact Play. |
| `scripts/tests/test_release_play_publish.py` | 209 | Exact-artifact production publication; fake Play transport, no signing/network. |
| `scripts/tests/test_release_play_validate.py` | 224 | Validate-only lifecycle tests with a fake Play service; no network or keys. |
| `scripts/tests/test_release_play_workflow.py` | 115 | Execute only the upload shell with a fake python; never build or upload. |
| `scripts/trigger_and_download_podcasts.py` | 442 | trigger_and_download_podcasts.py Trigger audio generation for all lessons that have source_id but no podcast, then poll and download. Skips upload… |
| `scripts/update_lesson_index.py` | 170 | Update lesson_index.json with newly generated flashcards and slides |
| `scripts/update_production_registry.py` | 96 | Update production_registry.md - robust table parsing |
| `scripts/upload_new_podcast_sources.py` | 71 | Efficient one-shot upload of the 48 new lesson md sources to NotebookLM. Unlike add_new_lesson_podcasts.py this lists sources ONCE up front and ONCE… |
| `scripts/upload_to_notebooklm.py` | 122 | List of possible method names and their call signatures |
| `scripts/validate_podcasts.py` | 161 | Guard against placeholder/broken lesson podcasts. Real NotebookLM podcasts are multi-minute (>= ~3 min, several MB). The old |
| `scripts/write_notebooklm_sources.py` | 97 | Write the NotebookLM markdown source for lessons that have none. The podcast pipeline is: curriculum lesson JSON → markdown source under |
| `scripts/write_path_source.py` | 66 | Write the NotebookLM path source a path video is generated from. Path videos (docs/path_videos/<path_id>_ar_eg.mp4) are NotebookLM video |

## 7) اختبارات E2E — `e2e/` (Maestro على المحاكي)


### e2e/

| الملف | أسطر | الدور |
|---|---:|---|
| `e2e/.gitignore` |  | استبعاد مخرجات E2E |
| `e2e/e2e_tool.py` | 1608 | Helpers for the emulator E2E gate (.github/workflows/mobile-e2e.yml). Subcommands, all stdlib-only so they run on a bare GitHub runner: |
| `e2e/flows/common/assert_today.yaml` | 32 | Today renders its primary blocks (origin/main layout, 1.0.67+112): |
| `e2e/flows/common/enter_pin.yaml` | 8 | Four digits on the child-mode keypad (child_mode_lock_screen.dart). |
| `e2e/flows/common/exit_child_mode.yaml` | 29 | Exit child mode cleanly back to Today using the PIN. |
| `e2e/flows/common/home.yaml` | 19 | Back to Today inside the running process — no cold start, so checkpoints that |
| `e2e/flows/common/mark_child.yaml` | 55 | Check this install is marked as test traffic: the CI APK creates the |
| `e2e/flows/common/onboard.yaml` | 79 | First run, as a new parent sees it: language → child's age band → start. |
| `e2e/flows/common/open_settings.yaml` | 21 | More tab → Settings (the last group of the hub, below the fold). |
| `e2e/flows/common/server_retry.yaml` | 43 | A 5xx from production is the server's moment, not this build's: a restart or |
| `e2e/flows/common/skip_tour.yaml` | 19 | The first-run coach-mark tour starts one frame after the root scaffold shows. |
| `e2e/flows/common/system_dialogs.yaml` | 15 | Fallback for a system "X isn't responding" dialog that is already up (run.sh |
| `e2e/flows/common/tap_field_end.yaml` | 19 | Tap a text field at its far end side, away from the text, so the caret lands |
| `e2e/flows/common/unlock_child_mode.yaml` | 30 | Unlock or set up child mode PIN (enter_pin.yaml). |
| `e2e/flows/fresh/01_onboarding.yaml` | 12 | Checkpoint 1 — fresh install of the PR head: onboarding creates the child |
| `e2e/flows/fresh/02_today_lesson.yaml` | 38 | Checkpoint 2 — Today's step opens the first lesson for the child's age, and |
| `e2e/flows/fresh/03_assistant.yaml` | 44 | Checkpoint 3 — the assistant streams an answer from the production API. |
| `e2e/flows/fresh/04_child_mode.yaml` | 67 | Checkpoint 4 — hand the device to the child through «باب التسليم», and take |
| `e2e/flows/fresh/05_dark_mode.yaml` | 28 | Checkpoint 5 — switch the app to dark (Settings → Appearance cycles |
| `e2e/flows/fresh/06_english.yaml` | 46 | Checkpoint 6 — switch the interface to English (Settings → Language) and walk |
| `e2e/flows/fresh/07_cold_start.yaml` | 17 | Checkpoint 7 — force-stop and cold start with real state on disk (a lesson in |
| `e2e/flows/fresh/08_child_survives_restart.yaml` | 13 | Checkpoint 8 — after that cold start the app still is the same family: the |
| `e2e/flows/fresh/09_programs.yaml` | 58 | Checkpoint 9 — «برامج الأسرة» (family programs, MOBILE_API §11). |
| `e2e/flows/fresh/10_child_corner.yaml` | 72 | Checkpoint 10 — «ركن الطفل»: through the hand-over gate into the child's |
| `e2e/flows/fresh/11_family_road.yaml` | 62 | Checkpoint 11 — «درب {الاسم}» and «على الأفق» (عالم الأسرة). |
| `e2e/flows/fresh/12_today_quests.yaml` | 36 | Checkpoint 12 — the family quests on Today (1.0.80), against the live server: today's mission marked by the parent, then the kind word. |
| `e2e/flows/fresh/13_tasmee.yaml` | 53 | Checkpoint 13 — «تسميع مع الوالد» (1.0.81), device-only: al-Fatiha, one word marked as dropped, saved, «موضع واحد للمراجعة». |
| `e2e/flows/fresh/14_mawqif.yaml` | 78 | Checkpoint 14 — «موقف بقرار» (1.0.81), against the live server: the card on Today → a response → the hadith → the step → «الليلة»; then the card leaves. |
| `e2e/flows/gallery/shoot.yaml` | 894 | One pass of the before/after gallery (Phase 0 of docs/NOOR_WAL_QANADIL_PLAN.md). |
| `e2e/flows/gallery/today_shot.yaml` | 23 | The gallery's own Today capture: common/assert_today.yaml's contract, but |
| `e2e/flows/rehearsal/expect.yaml` | 23 | Wait for PATTERN: a hard expectation on the PR head (TAG == 'after'), a |
| `e2e/flows/rehearsal/sound_after.yaml` | 15 | Sound × recitation, part 2: after the ticks the reader is still reciting — |
| `e2e/flows/rehearsal/sound_start.yaml` | 49 | Sound × recitation, part 1 (plan phase 2 gate: «الأصوات مابتوقفش التلاوة»). |
| `e2e/flows/rehearsal/stage.yaml` | 297 | One stage of the Ramadan rehearsal (docs/NOOR_WAL_QANADIL_PLAN.md, phase 5, |
| `e2e/flows/rehearsal/street_month.yaml` | 45 | The lantern street outside the month (Eid, after): every day the family |
| `e2e/flows/rehearsal/variant.yaml` | 86 | Set the app's language and theme for the next rehearsal pass, through |
| `e2e/flows/upgrade/01_baseline_onboarding.yaml` | 13 | Upgrade test, part 1 — on the BASELINE build (what users run today): onboard |
| `e2e/flows/upgrade/02_baseline_restart.yaml` | 20 | Upgrade test, control — restart the BASELINE before upgrading: does the live |
| `e2e/flows/upgrade/03_after_upgrade.yaml` | 20 | Upgrade test — the PR head installed over the baseline (`install -r`, data |
| `e2e/flows/upgrade/04_child_kept.yaml` | 11 | Upgrade test — the upgraded app still has the child the baseline created. |
| `e2e/install_system_image.sh` | 68 | Installs the emulator system image before reactivecircus/android-emulator-runner |
| `e2e/logcat_allowlist.txt` | 4 | ملف نصي |
| `e2e/rehearsal.sh` | 304 | The Ramadan rehearsal (gate G2) and the sound × recitation check, on the |
| `e2e/run.sh` | 271 | Runs the E2E journeys on the emulator that reactivecircus/android-emulator-runner |
| `e2e/test_e2e_tool.py` | 1454 | Tests for e2e/e2e_tool.py — run: python3 -m unittest discover -s e2e -v |
| `e2e/test_install_system_image.py` | 95 | install_system_image.sh against a stub sdkmanager: corrupt downloads are retried from scratch, and only a complete image counts as installed. |
| `e2e/test_rehearsal.py` | 174 | Exercise the real rehearsal runner (e2e/rehearsal.sh) with fake device, CLI and tool boundaries; no builds, no emulator, no server. |
| `e2e/test_run.py` | 138 | Exercise the real shell runner with fake device/CLI boundaries; no builds. |
| `e2e/test_workflow.py` | 525 | Parse the workflow and execute its final verdict without builds or devices. |
| `e2e/testdata/dumpsys_audio_run38722537691_after.txt` | 703 | ملف نصي |
| `e2e/testdata/dumpsys_audio_run38722537691_before.txt` | 702 | ملف نصي |

## 8) ريلز التسويق — `remotion-reels/` (Remotion)


### remotion-reels/ (شيفرة)

| الملف | أسطر | الدور |
|---|---:|---|
| `remotion-reels/.gitignore` |  | استبعاد node_modules والمخرجات |
| `remotion-reels/data/reel.json` |  | ملف بيانات/إعداد JSON |
| `remotion-reels/package-lock.json` |  | ملف بيانات/إعداد JSON |
| `remotion-reels/package.json` |  | اعتماديات Remotion |
| `remotion-reels/scripts/check_vo.py` | 75 | check_vo — an independent ear on the voice-over takes. A TTS take can say a different word than its line (a judge once heard |
| `remotion-reels/scripts/gen_teaser_qr.py` | 108 | gen_teaser_qr — the QR codes on the teaser's and the campaign reels' end cards. Writes src/noor/qr.ts: one module path per cut, in module units, so… |
| `remotion-reels/scripts/gen_teaser_sfx.py` | 243 | gen_teaser_sfx — the four soft sounds of the «نور» teaser, computed from code. The owner's rule is «أصوات ناعمة بلا موسيقى»: no music, no… |
| `remotion-reels/scripts/gen_vo.py` | 329 | gen_vo — the voice-over lines of the «المربّي» reels (teaser + five campaign reels). Reads src/noor/campaign/vo_script.json (reel -> lines with a… |
| `remotion-reels/scripts/make_campaign_sheet.py` | 57 | make_campaign_sheet — a contact sheet of the campaign reels, pulled from the rendered MP4s themselves (not from the source), so it shows what ships. |
| `remotion-reels/scripts/make_reel_data.py` | 53 | Generate Remotion data/reel.json from tutor-guardian path manifest. |
| `remotion-reels/scripts/make_round_logo.py` | 55 | make_round_logo — the app icon, cut to a circle, for the teaser and the campaign reels (end card + small corner mark). |
| `remotion-reels/scripts/render.sh` | 11 | رندر الريل العام (قديم) |
| `remotion-reels/scripts/render_noor_campaign.sh` | 52 | Render the six «المربّي» campaign reels (1080×1920, H.264, 30 fps), one |
| `remotion-reels/scripts/render_noor_teaser.sh` | 28 | Render the «نور» teaser: three MP4s (H.264, CRF 18) and six key stills of |
| `remotion-reels/scripts/render_noor_vo.sh` | 26 | Render the voice-over cuts (`_vo`): the Arabic teaser and the six campaign |
| `remotion-reels/scripts/sync_app_art.sh` | 16 | Copy the app's own «ورق مقصوص» art (mobile/assets/svg/stories + noor) into |
| `remotion-reels/scripts/verify_videos.py` | 118 | verify_videos — check rendered reels by their effect, not by the render's exit code. For every MP4 given (or every MP4 in the directories given): |
| `remotion-reels/src/Reel.tsx` | 285 | مكوّن الريل العام (قبل حملة «نور») من data/reel.json |
| `remotion-reels/src/Root.tsx` | 4 | جذر Remotion |
| `remotion-reels/src/index.tsx` | 70 | تسجيل التركيبات (compositions): ريل عام + تيزر نور + 6 ريلز حملة + نسخ VO |
| `remotion-reels/src/noor/DevSheet.tsx` | 35 | Dev aid: one still showing the teaser at several frames (contact sheet), |
| `remotion-reels/src/noor/NoorTeaser.tsx` | 638 | «المربّي» teaser — Noor peeks out of a paper-cut night and lights the way. |
| `remotion-reels/src/noor/art.tsx` | 279 | «ورق مقصوص» art, transcribed from the staged SVGs copied into public/noor/ |
| `remotion-reels/src/noor/campaign/TeaserWorld.tsx` | 74 | The Arabic teaser, refreshed with the app's new world. The teaser plays as |
| `remotion-reels/src/noor/campaign/V1Remember.tsx` | 305 | Reel 1 «نور يتذكّر» (v1_remember) — advice you heard and forgot; Noor |
| `remotion-reels/src/noor/campaign/V2Road.tsx` | 494 | Reel 2 «درب الأسرة» (v2_road) — don't know where to start? The family's |
| `remotion-reels/src/noor/campaign/V3Ask.tsx` | 282 | Reel 3 «اسأل المربّي» (v3_ask) — a real question is typed; Noor thinks, |
| `remotion-reels/src/noor/campaign/V4Handover.tsx` | 516 | Reel 4 «ركن الطفل» (v4_handover) — screen time with a purpose, and an |
| `remotion-reels/src/noor/campaign/V5Ramadan.tsx` | 317 | Reel 5 «شارع القناديل» (v5_ramadan) — this Ramadan is different: thirty |
| `remotion-reels/src/noor/campaign/V6Stories.tsx` | 268 | Reel 6 «حكاية مع نور» (v6_stories) — a bedtime story, told by Noor, on the |
| `remotion-reels/src/noor/campaign/VoReels.tsx` | 103 | Voice-over cuts of the Arabic teaser and the six campaign reels (`_vo`). |
| `remotion-reels/src/noor/campaign/copy.ts` | 112 | On-screen words of the five campaign reels, in one place for review. |
| `remotion-reels/src/noor/campaign/kit.tsx` | 623 | Shared parts of the five «المربّي» campaign reels (1080×1920 only). |
| `remotion-reels/src/noor/campaign/qr.ts` | 11 | Generated by scripts/gen_teaser_qr.py — do not edit by hand. |
| `remotion-reels/src/noor/campaign/reels.tsx` | 85 | The six campaign reels (1080×1920, 30 fps) and a dev contact sheet that |
| `remotion-reels/src/noor/campaign/sound.tsx` | 56 | The campaign reels' sound: the teaser's generated room sounds (no music, |
| `remotion-reels/src/noor/campaign/vo_lines.ts` | 428 | Generated by scripts/gen_vo.py — do not edit by hand. |
| `remotion-reels/src/noor/campaign/vo_script.json` |  | ملف بيانات/إعداد JSON |
| `remotion-reels/src/noor/campaign/world.tsx` | 397 | The app's new world, for the reels: the very pieces the app draws. |
| `remotion-reels/src/noor/copy.ts` | 36 | On-screen copy. Arabic is easy Modern Standard Arabic (no dialect). |
| `remotion-reels/src/noor/geometry.ts` | 142 | Small geometry helpers: smooth hill outlines and a tapered "paper road" |
| `remotion-reels/src/noor/layouts.ts` | 263 | Where everything sits, per frame size. Coordinates are in output pixels. |
| `remotion-reels/src/noor/mix.ts` | 6 | Shared by the teaser and the campaign reels: when a reel is played inside |
| `remotion-reels/src/noor/palette.ts` | 14 | «ورق مقصوص» palette — exactly the hexes in the style guide (STYLE.md). |
| `remotion-reels/src/noor/qr.ts` | 9 | Generated by scripts/gen_teaser_qr.py — do not edit by hand. |
| `remotion-reels/src/noor/sound.tsx` | 57 | Soft generated sounds only — no music, no instruments, no bells. |
| `remotion-reels/src/noor/timeline.ts` | 29 | ── timeline (frames @ 30 fps) ───────────────────────────────────────────── |
| `remotion-reels/tsconfig.json` |  | ملف بيانات/إعداد JSON |

| المجموعة | عدد الملفات | ما هي |
|---|---:|---|
| `remotion-reels/public/` | 66 (mp3×46, svg×9, wav×7, png×2) | أصوات VO/SFX وأصول ورق مقصوص منسوخة من التطبيق (sync_app_art.sh) وشعار |

## 9) الواجهة الويب — `frontend/`

ليست المنتج: هبوط سينمائي يُقدَّم عبر `routers/web.py` + صفحة اختبار. المنتج الفعلي هو تطبيق الموبايل.

### frontend/

| الملف | أسطر | الدور |
|---|---:|---|
| `frontend/cinematic.en.html` | 427 | قالب الهبوط السينمائي الإنجليزي |
| `frontend/cinematic.html` | 422 | قالب الهبوط السينمائي العربي (placeholders {{DOWNLOAD_URL}}…) يُقدَّم من routers/web.py |
| `frontend/engine.js` | 666 | ⚠️ محرك تمرير فيديو (scroll-world) — لا تشير إليه أي صفحة حاليًا (يُذكر في .agents skill فقط) |
| `frontend/icons/apple-touch-icon.png` |  | صورة/رسم |
| `frontend/icons/favicon-32.png` |  | صورة/رسم |
| `frontend/icons/icon-192.png` |  | صورة/رسم |
| `frontend/icons/icon-512.png` |  | صورة/رسم |
| `frontend/icons/icon-maskable-512.png` |  | صورة/رسم |
| `frontend/index.html` | 26 | تحويل احتياطي إلى /go (لدقيقة النشر فقط) |
| `frontend/manifest.json` |  | PWA manifest (start_url /go) |
| `frontend/style.css` | 1273 | ⚠️ أنماط قديمة لمحرك التمرير — غير مرتبطة بالقوالب الحالية |
| `frontend/sw.js` | 22 | ⚠️ service worker غير مسجَّل في أي صفحة (cache v2) |
| `frontend/test_ui.html` | 144 | عميل اختبار يدوي لـ/api/assistant/query |

| المجموعة | عدد الملفات | ما هي |
|---|---:|---|
| `frontend/assets/` | 172 (jpg×150, png×9, mp4×6, woff2×3, svg×2) | إطارات تمرير الفيديو (seq/*.jpg)، خطوط Cairo woff2، بانر، فيديوهات، و`print/qr_PR0{1,2}.svg` (رمز QR أسفل أوراق الطباعة — يكتبه `ops/tools/gen_print_qr.py`) |

## 10) CI/CD وخطافات git — `.github/` و `.githooks/`


### .github/ و .githooks/

| الملف | أسطر | الدور |
|---|---:|---|
| `.githooks/pre-commit` |  | حراس الالتزام: سلامة KB، مطابقة آيات المصحف، عرض القرآن بالإنجليزية، حرّاس الأذكار والأحاديث، قصص الأنبياء والسيرة (`check_anbiya_stories`/`check_sira_stories`)، تكافؤ الإنجليزي، تغطية النصوص الشرعية، ruff |
| `.githooks/pre-push` |  | حارس الموبايل قبل الدفع: flutter analyze --fatal-infos --fatal-warnings + flutter test (يتخطّى بـSKIP_MOBILE_CHECKS=1) |
| `.github/actions/backend-env/action.yml` | 176 | بيئة اختبار الباكند على GitHub (تثبيت مقفول) |
| `.github/actions/backend-image/action.yml` | 136 | بناء/فحص/نشر صورة الباكند (مشتركة بين deploy وcandidate-image) |
| `.github/ci/constraints-prod.txt` | 156 | إصدارات الإنتاج المجمّدة |
| `.github/ci/lock-backend-deps.py` | 226 | إعادة توليد requirements-prod.lock من constraints الإنتاج |
| `.github/ci/refresh-constraints-from-prod.sh` | 40 | تحديث constraints-prod.txt من حزم الحاوية الحية |
| `.github/ci/reject-broken-images.sh` | 40 | يكسر نسخة من الصورة ويطلب من الـsmoke رفضها |
| `.github/ci/requirements-dev.lock` |  | قفل اعتماديات الاختبار |
| `.github/ci/requirements-prod.lock` |  | قفل الاعتماديات المشفّر بالـhash لصورة الإنتاج |
| `.github/dependabot.yml` | 24 | تحديثات اعتماديات آلية |
| `.github/workflows/backend.yml` | 264 | Backend tests: pytest (+golden CI) + سلامة KB + ruff (بوابة النشر) |
| `.github/workflows/build-release-unsigned.yml` | 110 | بناء AAB غير موقَّع بمراجعة SHA محدد (التوقيع محلي) |
| `.github/workflows/candidate-image.yml` | 155 | فحص صورة الباكند المرشّحة (smoke + كسر الصورة ثلاث مرات ليرفضها) |
| `.github/workflows/chroma-1x-recall.yml` | 143 | تجربة يدوية: استدعاء Chroma 1.x مقابل 0.6 (غير بوابة نشر) |
| `.github/workflows/chroma-1x-runtime.yml` | 207 | تجربة يدوية: تشغيل/ترحيل فهرس Chroma 1.x (غير بوابة نشر) |
| `.github/workflows/ci.yml` | 22 | ⚠️ مُعطَّل عمدًا (يُبقى لاسم بوابة محمية)؛ البديل backend.yml |
| `.github/workflows/deploy.yml` | 512 | نشر الإنتاج: gate → image (GHCR) → deploy على VPS (runner ذاتي) مع تراجع تلقائي → alert |
| `.github/workflows/docker.yml` | 119 | بناء صورة Docker في PR (مكرر مع candidate-image؛ مطفأ عمليًا) |
| `.github/workflows/e2e-avd-cache.yml` | 107 | يحفظ لقطة المحاكي على main يوميًا لتسريع E2E |
| `.github/workflows/flutter.yml` | 90 | Flutter analyze + test على دفعات mobile/** |
| `.github/workflows/golden-full.yml` | 34 | تقييم ذهبي كامل (يدوي؛ بلا مفاتيح مزوّد => UNAVAILABLE) |
| `.github/workflows/mobile-e2e.yml` | 965 | بوابة الإصدار: APK release يُقاد بـMaestro على محاكي (13 رحلة fresh/upgrade + تجربة رمضان + معرض) |
| `.github/workflows/release-play.yml` | 180 | يدوي: بناء AAB موقَّع ورفعه إلى Google Play (internal/alpha/beta/production) |
| `.github/workflows/runtime-readiness.yml` | 91 | تشخيص جاهزية وقت التشغيل على main (runner الإنتاج، مخرجات مشفّرة) |

## 11) قاعدة المعرفة — `knowledge_base/` و `knowledge_base_markdown/`


### knowledge_base/units/ — (لا سكربتات؛ نُقل `audit_age_groups.py` إلى `scripts/archive/`)

| الملف | أسطر | الدور |
|---|---:|---|

### knowledge_base/ — مخطط ومرجع (ملفات فردية)

| الملف | أسطر | الدور |
|---|---:|---|
| `knowledge_base/curriculum/schema.md` | 264 | Curriculum Schema — `knowledge_base/curriculum/ |
| `knowledge_base/curriculum/schema/agreement_clauses.schema.json` |  | ملف بيانات/إعداد JSON |
| `knowledge_base/curriculum/schema/daily_tip.schema.json` |  | ملف بيانات/إعداد JSON |
| `knowledge_base/curriculum/schema/lesson.schema.json` |  | ملف بيانات/إعداد JSON |
| `knowledge_base/curriculum/schema/license_scenario.schema.json` |  | ملف بيانات/إعداد JSON |
| `knowledge_base/curriculum/schema/mission_bank.schema.json` |  | ملف بيانات/إعداد JSON |
| `knowledge_base/curriculum/schema/path.schema.json` |  | ملف بيانات/إعداد JSON |
| `knowledge_base/curriculum/schema/program_milestones.schema.json` |  | ملف بيانات/إعداد JSON |
| `knowledge_base/curriculum/schema/program_prayer_journey.schema.json` |  | ملف بيانات/إعداد JSON |
| `knowledge_base/curriculum/schema/program_ramadan_family.schema.json` |  | ملف بيانات/إعداد JSON |
| `knowledge_base/curriculum/schema/weekly_plan_bank.schema.json` |  | ملف بيانات/إعداد JSON |
| `knowledge_base/examples/sample_cyber_unit.json` |  | ملف بيانات/إعداد JSON |
| `knowledge_base/examples/sample_fiqh_unit.json` |  | ملف بيانات/إعداد JSON |
| `knowledge_base/examples/sample_medical_unit.json` |  | ملف بيانات/إعداد JSON |
| `knowledge_base/schema/knowledge_unit.schema.json` |  | ملف بيانات/إعداد JSON |
| `knowledge_base/schema/unit_schema.json` |  | ملف بيانات/إعداد JSON |
| `knowledge_base/units_index.json` |  | ملف بيانات/إعداد JSON |

| المجموعة | عدد الملفات | ما هي |
|---|---:|---|
| `knowledge_base/units/*.json` | 1420 (json×1420) | وحدات المعرفة الخام (UUID/seed-*/isl-*/med-*.json؛ `__en.json` = توأم إنجليزي: 1060 عربي + 360 إنجليزي). مصدر RAG |
| `knowledge_base/curriculum/paths/` | 43 (json×43) | المسارات التعليمية |
| `knowledge_base/curriculum/lessons/` | 250 (json×205, md×45) | الدروس |
| `knowledge_base/curriculum/daily_tips/` | 220 (json×220) | نصائح اليوم (مجمّع) |
| `knowledge_base/curriculum/mawaqif/mawaqif.json` |  | بنك «موقف بقرار»: 6 مواقف (واحد لكل عمر من 2-3 إلى 16-18)، كلٌّ بثلاثة ردود وحديث من الصحيحين وخطوة — سطح محروس في `content_surfaces.py` |
| `knowledge_base/curriculum/i18n/en/` | 486 (json×485, md×1) | ترجمة المنهج الإنجليزية (دروس/مسارات/نصائح/اتفاقيات/مواقف/…) + تقارير مراجعة |
| `knowledge_base/curriculum/{agreements,license,missions,programs,weekly_plan}` | 16 (json×16) | بنوك: بنود الاتفاقية، مواقف الرخصة، المهام، برامج الأسرة (رمضان/الصلاة/المراحل)، خطط الأسبوع |
| `knowledge_base/notebooklm/` | 198 (md×198) | مصادر NotebookLM لكل فئة عمرية ومسار |
| `knowledge_base/raw_sources/` | 9 (txt×5, log×2, json×1, part×1) | سجلات تنزيل المصادر الخام |
| `knowledge_base_markdown/` | 741 (md×741) | نسخة Markdown مقروءة من المنهج والوحدات (مولّدة) |

## 12) التوثيق والمحتوى — `docs/`, `plans/`, `prompts/`, …


### docs/ — مستندات نصية رئيسية (فردية)

| الملف | أسطر | الدور |
|---|---:|---|
| `docs/CHROMA_1X_FEASIBILITY.md` | 196 | Phase 4: Chroma 1.x feasibility and recall plan |
| `docs/CHROMA_1X_RUNTIME.md` | 100 | Chroma 0.6.3 → 1.5.9 runtime and persisted-index experiment |
| `docs/DB_SCHEMA_OWNERS.md` | 158 | DB schema owners (M17 inventory) |
| `docs/EN_CONTENT_STATUS.md` | 405 | المحتوى الإنجليزي — البوابة والحالة |
| `docs/EN_HANDOVER.md` | 173 | تسليم: إكمال المحتوى الإنجليزي |
| `docs/EN_MEDIA_GENERATION_BRIEF.md` | 151 | بريف: توليد الصوت والفيديو الإنجليزي |
| `docs/GOLDEN_CI.md` | 59 | Golden evaluation in CI |
| `docs/INFOGRAPHIC_PROMPTS.md` | 180 | إنفوجرافيك الدروس الجديدة — برومبتات للتوليد |
| `docs/INFOGRAPHIC_PROMPTS_REVIEW.md` | 46 | بلوكات الإنفوجراف — قائمة المراجعة البشرية |
| `docs/LLM_TELEMETRY_MIGRATIONS.md` | 61 | First Phase 3 migration slice: llm_calls |
| `docs/NOOR_WAL_QANADIL_PLAN.md` | 298 | «نور والقناديل» — تحويل المربّي لرحلة أسرة حيّة |
| `docs/OPS_RUNBOOK.md` | 516 | دليل التشغيل — المربي الذكي (Ops Runbook) |
| `docs/PLAN_CLOSEOUT_2026-10-07.md` | 41 | Plan closeout — 7 October 2026 |
| `docs/PLAY_STORE_LISTING.md` | 504 | المربّي الذكي — حزمة ASO كاملة (Play Console) |
| `docs/ROUTE_POLICY.md` | 134 | Route policy inventory — Phase 3, item 2 |
| `docs/RUNBOOK_lesson_progress_child_key.md` | 135 | Runbook — ترحيل `lesson_progress` إلى مفتاح لكل طفل |
| `docs/SOURCES_NEEDING_REVIEW.md` | 78 | وحدات معرفية تحتاج قرارًا بشريًا |
| `docs/STORIES_AUDIT.md` | 131 | مراجعة ميزة «القصص» — 2026-10-15 |
| `docs/USABILITY_RESCUE_BRIEF.md` | 142 | بريف: فجوة الفهم والاستخدام في تطبيق المربّي — تحقّق ثم خطة إنقاذ |
| `docs/USABILITY_RESCUE_PLAN.md` | 232 | خطة إنقاذ الاستخدام — المربّي 1.0.47+92 |
| `docs/VISUAL_ASSETS.md` | 113 | المربّي — دليل الأصول البصرية |
| `docs/arabic_video_prompts.md` | 80 | إعادة توليد فيديوهات الدروس بالعربية — حزمة البرومبتات الجاهزة |
| `docs/audio_registry.json` |  | ملف بيانات/إعداد JSON |
| `docs/content_reviews/medical-gaps-2026-10-07.md` | 15 | Medical gap units: source verification, 7 October 2026 |
| `docs/content_reviews/parent-doubts-units_REVIEW.md` | 188 | وحدات «أسئلة الأهل عن الشكوك والشبهات»: ما يراجعه العالِم (مسودة 2026-10-22) |
| `docs/content_reviews/parent-doubts-units_SCHOLAR_PACKAGE.md` | 433 | حزمة المراجعة الشرعية لسبع وحدات عن شكوك الأبناء |
| `docs/implementation_plan_bedtime_insights_covenant.md` | 61 | Bedtime Routine Flow Implementation Plan (Step 2) |
| `docs/lesson_index.json` |  | ملف بيانات/إعداد JSON |
| `docs/operations/curated-social-tips.md` | 69 | Curated social tips — 2026-10-07 |
| `docs/prenatal_notebooklm_prompts.md` | 57 | برومبتات توليد فيديوهات وإنفوجراف مسار الحمل والرضع في NotebookLM |
| `docs/privacy-policy.md` | 443 | سياسة الخصوصية — المربّي |
| `docs/production_registry.md` | 272 | سجل إنتاج الوسائط التربوية (Production Registry) |
| `docs/release/hosted-unsigned-aab.md` | 137 | Hosted unsigned AAB and local upload-key boundary |
| `docs/release/verified-play-publication.md` | 48 | Publish the verified bundle at 100% |
| `docs/release_notes/1.0.68+113.json` |  | ملف بيانات/إعداد JSON |
| `docs/release_notes/1.0.69+114.json` |  | ملف بيانات/إعداد JSON |
| `docs/release_notes/1.0.70+115.json` |  | ملف بيانات/إعداد JSON |
| `docs/release_notes/1.0.71+116.json` |  | ملف بيانات/إعداد JSON |
| `docs/release_notes/1.0.72+117.json` |  | ملف بيانات/إعداد JSON |
| `docs/release_notes/1.0.73+118.json` |  | ملف بيانات/إعداد JSON |
| `docs/release_notes/1.0.74+119.json` |  | ملف بيانات/إعداد JSON |
| `docs/release_notes/1.0.75+120.json` |  | ملاحظات إصدار 1.0.75+120 (ar/en) — يقرؤها «ما الجديد» |
| `docs/release_notes/1.0.76+121.json` |  | ملاحظات إصدار 1.0.76+121 (ar/en) — يقرؤها «ما الجديد» |
| `docs/release_notes/1.0.77+122.json` |  | ملاحظات إصدار 1.0.77+122 (ar/en) — يقرؤها «ما الجديد» |
| `docs/release_notes/1.0.78+123.json` |  | ملاحظات إصدار 1.0.78+123 (ar/en) — يقرؤها «ما الجديد» |
| `docs/release_notes/1.0.79+124.json` |  | ملاحظات إصدار 1.0.79+124 (ar/en) — يقرؤها «ما الجديد» |
| `docs/release_notes/1.0.80+125.json` |  | ملاحظات إصدار 1.0.80+125 (ar/en) — يقرؤها «ما الجديد» |
| `docs/release_notes/1.0.81+126.json` |  | ملاحظات إصدار 1.0.81+126 (ar/en) — يقرؤها «ما الجديد» |
| `docs/source_inventory.json` |  | ملف بيانات/إعداد JSON |
| `docs/stories.en.json` |  | ملف بيانات/إعداد JSON |
| `docs/stories.json` |  | ملف بيانات/إعداد JSON |
| `docs/task_bedtime_insights_covenant.md` | 10 | - [ ] Extend Coins system |
| `docs/walkthrough_bedtime_insights_covenant.md` | 75 | Walkthrough of Completed Parenting App Upgrades |

| المجموعة | عدد الملفات | ما هي |
|---|---:|---|
| `docs/lesson_assets/` | 912 (json×330, md×291, csv×291) | أصول الدروس المولَّدة: flashcards/slides/quizzes/reports/data tables (json/csv/md) حسب معرّف الدرس |
| `docs/stories/` | 302 (png×287, mp4×15) | رسوم وفيديوهات القصص (png/mp4) — أغلفة وصفحات؛ منها 168 png لقصص الأنبياء (`anbiya_*`) والسيرة (`sira_*`)، نسختا young/older لكل قصة |
| `docs/brand/` | 42 (png×31, svg×7, json×2, py×2 — الـpy الاثنان لهما صفّان فرديان في «docs/brand/tools/» أدناه) | الهوية البصرية: أيقونات/سِيَل/أدوات متجر |
| `docs/research/` | 24 (md×23, csv×1) | أبحاث تأسيسية (إطار تربوي، أوراق مراحل، ردود خام) |
| `docs/marketing/` | 9 (webp×5, png×2, jpg×1, json×1) | رسومات الإطلاق وmanifest الريلز |
| `docs/ (ملفات مخرجات الدروس)` | 102 (json×62, md×40) | `lesson_*_assets.md/_flashcards.json/_slides.json` و`*_assets.md`: مخرجات توليد الدروس المباشرة |
| `docs/MAWAQIF.md` | 62 | «موقف بقرار» — المواصفة (2026-11-09) |
| `docs/TASMEE_WITH_PARENT.md` | 71 | «تسميع مع الوالد» — المواصفة (2026-11-09) |

### docs/brand/tools/ — خط أنابيب الهوية البصرية (أدوات CLI بـargparse)

| الملف | أسطر | الدور |
|---|---:|---|
| `docs/brand/tools/brand_build.py` | 777 | خط الهوية: يشتق من SVG المصدر (`docs/brand/icon/icon_*.svg` ذات المجموعات background/foreground/monochrome) أوامر فرعية: `review` (لوحات مقارنة اتجاهات الأيقونة الثلاثة ← `docs/brand/review/`) · `android <a\|b\|c>` (أيقونة تكيّفية VectorDrawable + PNG قديمة تحت أسماء جديدة `ic_launcher_paper*` ولا تمسّ الأيقونة المنشورة) · `store` (feature graphic + إطارات لقطات فارغة + أيقونة Play 512 ← `docs/brand/store/`) · `web` (صورة og:image 1200×630 وأيقونات PWA/favicon ← `frontend/assets/`, `frontend/icons/`) · `frame` (تعبئة إطار بلقطة). يحتاج python3-gi (Rsvg/Pango) وpycairo وPillow؛ الخطوط من `mobile/assets/google_fonts/` عبر fontconfig خاص بالمستخدم (`~/.cache/tg-brand-fontconfig`) |
| `docs/brand/tools/store_listing.py` | 162 | مجموعة قائمة متجر Play لإصدار: لقطات مؤطَّرة 1080×1920 + `icon.png` 512 + `feature_graphic.png` 1024×500 لكل لغة (`ar/`,`en/`) بأمر `build --listing docs/brand/store/listing_<ver> --captures <run_id>=<dir>`؛ `manifest.json` هو الوصفة (يسجّل sha256 لكل لقطة CI، اللقطات نفسها لا تُكوميت)؛ و`contact` يكتب ورقة مراجعة. التعديل الوحيد على لقطة: قصّ لوحة المفاتيح وملء القص بلون خلفية التطبيق. يستورد `brand_build` |

### plans/ و prompts/ و scratch/ و reviews/ و notebooklm_sources/ و .well-known و .agents

| الملف | أسطر | الدور |
|---|---:|---|
| `.agents/skills/create-cinematic-webpage/SKILL.md` | 141 | --- |
| `.well-known/assetlinks.json` |  | ملف بيانات/إعداد JSON |
| `plans/assistant-questions-brief.md` | 183 | ١,٦١٦ سؤالًا من آباء حقيقيين — بريف الاستفادة منها |
| `plans/child-surface-handoff-2026-08-16.md` | 136 | واجهة الطفل — تسليم لجلسة جديدة |
| `plans/content-and-product-brief.md` | 225 | ما الذي يستحق أن يُبنى بعد ذلك — بريف محتوى ومنتج |
| `plans/growth-master-plan-2026-07.md` | 225 | المربي الذكي — الخطة الرئيسية للتطوير والنمو (يوليو 2026) |
| `plans/india-decision-analysis-2026-07.md` | 45 | §6.2 قرار الهند — تحليل تكلفة/أثر (2026-07-17) |
| `plans/lesson-completion-brief.md` | 249 | لماذا يترك أربعةٌ من كل خمسة الدرسَ قبل نهايته — بريف تحقيق |
| `plans/lora-eval-2026-07-17.md` | 29 | §6.5 تقييم tg-tutor-commandr-lora مقابل tg-tutor:v4 (2026-07-17) |
| `plans/next-session-prompt.md` | 19 | برومبت الجلسة الجاية — استكمال خطة نمو «المربي الذكي» |
| `plans/okf-integration-plan.md` | 335 | خطة دمج Open Knowledge Format (OKF) في مشروع المربّي الذكي |
| `plans/review-reply-agent-proposal.md` | 28 | اقتراح: وكيل PCC لمسودات الردود على مراجعات المتجر (§4.3/§6.1) |
| `plans/sharia-review-board-brief.md` | 206 | هيئة المراجعة الشرعية — بريف بدء |
| `plans/sprint3-internet-licence-spec.md` | 271 | سبرنت ٣ — رخصة الإنترنت · مواصفة تنفيذ |
| `prompts/audio_prompt.txt` | 1 | ملف نصي |
| `prompts/flashcards_prompt.txt` | 8 | ملف نصي |
| `prompts/slides_prompt.txt` | 8 | ملف نصي |
| `prompts/summary_prompt.txt` | 6 | ملف نصي |
| `reviews/sharia_review_16-18_committee4_report.json` |  | ملف بيانات/إعداد JSON |
| `scratch/path_video_failures.json` |  | ملف بيانات/إعداد JSON |
| `scratch/path_video_manifest.json` |  | ملف بيانات/إعداد JSON |
| `scratch/path_video_tasks.json` |  | ملف بيانات/إعداد JSON |

| المجموعة | عدد الملفات | ما هي |
|---|---:|---|
| `notebooklm_sources/` | 26 (md×26) | مصادر NotebookLM مبكرة لمساري 0-3 والحمل (مستبدلة ببنية knowledge_base/notebooklm) |

### ملفات الجذر

| الملف | أسطر | الدور |
|---|---:|---|
| `.dockerignore` |  | استبعادات بناء Docker (تشمل الميديا) |
| `.env.example` |  | قالب البيئة (أسماء فقط) |
| `.gitignore` |  | استبعادات git |
| `API.md` | 91 | عقد الـAPI العام (للفريق الذي يبني الموبايل) |
| `AUDIT_AND_ROADMAP.md` | 420 | تدقيق 2026-09 وخارطة الإصلاح |
| `MOBILE_API.md` | 1477 | عقد الموبايل v1+: المصادقة، enums، الجلسات، البث، ذاكرة الطفل §9، حذف الحساب §10، برامج الأسرة §11، القناديل §12 |
| `MOBILE_APP_PLAN.md` | 202 | خطة تطبيق الموبايل (تاريخية) |
| `PROGRAM_BUILD_PLAN.md` | 809 | خطة بناء البرامج (تاريخية) |
| `README.md` | 120 | تعريف المشروع، التشغيل المحلي/Docker، حارس سلامة المعرفة، CI/CD |
| `ROADMAP.md` | 24 | تتبّع الدين التقني (الطابور فارغ) |
| `UX_UI_ROADMAP.md` | 212 | خارطة UX/UI (DS/E/UX بنود) |
| `artifact_groups.json` |  | تجميعات الأصول (v1) للتوليد |
| `artifact_groups_v2.json` |  | تجميعات الأصول (v2) |
| `artifact_groups_v3.json` |  | تجميعات الأصول (v3) |
| `check.sh` | 21 | بوابة جودة محلية: check_kb_integrity (--full يضيف Chroma + الاختبارات) |
| `docker-compose.production.yml` | 112 | إنتاج: tg_backend (+binds) + tg_redis على شبكتين (internal + analytics-platform_production_network) |
| `docker-compose.yml` | 48 | تطوير محلي: tg_ollama + tg_backend |
| `hermes_agent_production_plan.md` | 136 | خطة وكيل Hermes الإنتاجية (تاريخية) |
| `pyproject.toml` |  | إعداد ruff/أدوات بايثون |
| `pytest.ini` |  | إعداد pytest |
| `remaining_lessons_queue.json` |  | طابور الدروس المتبقية للتوليد |
| `sharia_review_report_10-12_13-15.md` | 153 | تقرير مراجعة شرعية لشريحتي 10-12 و13-15 |
| `source_to_lesson.json` |  | خريطة المصدر→الدرس (تُعاد بنيتها بـrefresh_source_map.py) |

---
## قاعدة التغطية

- عدد الملفات المتعقَّبة (`git ls-files`): **7178**.
- مذكور بصف خاص: **1383** · داخل صف مجموعة: **5795** · غير مغطّى: **0** (تحقّق آلي: كل مسار في `git ls-tree -r ee7afcf1` إمّا مذكور حرفيًا بين backticks أو تحت مسار مجموعة مذكور).
- الأرقام أعلاه على الأساس `ee7afcf1`. شجرة فرع الكتالوج تعدّ **7189** لأنها تضيف 11 ملفًا هي `docs/catalog/*.md` نفسها (غير مُدرَجة في الجداول عمدًا).
- للتحقق عند التعديل: شغّل `git ls-files | wc -l` وقارنه بمجموع الصفوف؛ ملف جديد خارج المجموعات يجب أن يُضاف صفًّا هنا (Rule 2 في README).
