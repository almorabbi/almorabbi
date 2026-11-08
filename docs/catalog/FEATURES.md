# FEATURES — كتالوج قدرات «المربّي الذكي» (almorabbi)

> **الأهم في الكتالوج.** كل قدرة يراها مستخدم (أب/طفل/مراهق) أو مشغّل، بأين تعيش وحالتها **بحسب الأدلة في الشيفرة** (ربط بنقطة دخول؟ مُشار إليها؟ علم بيئي؟) لا بحسب الادّعاء.
> الأساس: `origin/main` في `almorabbi/almorabbi` عند `2652382` (تطبيق **1.0.79+124**، 2026-11-06). يشمل ما كان «فجوة» في كتالوج الأرشيف (1.0.75+120) وإصدارات 1.0.76–1.0.79. وإصلاحات الأرشيف 2026-10-28/29 المنقولة 2026-11-08 (`08-gotchas.md` §0).

**رموز الحالة:** ✅ يعمل ومربوط بنقطة دخول ويحمل اختبارات · 🟡 جزئي/مشروط (علم بيئي مطفأ افتراضيًا، أو مفعّل بخادم/بناء معيّن، أو قدرة بلا نصف) · ⚠️ غير موصول/ميت (شيفرة بلا مستهلك) · ❓ غير مُتحقَّق منه من الشيفرة وحدها (يتوقف على حالة الإنتاج الحيّة).

**ثوابت المنتج** (من `docs/OPS_RUNBOOK.md` §0): مجاني مدى الحياة، بلا إعلانات ولا اشتراكات؛ الرافعة الاقتصادية الوحيدة المسموحة هي خفض التكلفة. «ادعم المربّي» (مشتريات Play استهلاكية بلا مقابل) استثناء مُعلَن ومطفأ افتراضيًا.

---

## أ) المساعد والمحادثة (قلب المنتج)

مسار السؤال (`routers/assistant.py`): دعم القلق الذاتي ← حظر النوايا ← طوارئ ← حارس العقاب البدني ← حارس الفتوى ← تصنيف المجال ← إعادة صياغة ← استرجاع هجين ← LLM ← حواجز السلامة ← تسجيل. تفاصيل المخطط في `01-architecture.md` و`06-ai.md`.

| # | القدرة | ماذا تفعل للمستخدم | أين تعيش | الحالة |
|---|---|---|---|---|
| A1 | سؤال/جواب مؤصَّل ببث (SSE) | الأب يكتب سؤالًا تربويًا فيصله جواب يُبنى من وحدات المعرفة مع مصادر، قطعةً قطعة | `POST /api/assistant/stream` · `assistant.py` · `screens/chat_screen.dart` · `state/chat_notifier.dart` · `api/tg_client.dart` | ✅ |
| A2 | جواب كامل غير بثّي + مسودّة | نفس السلسلة بلا بث (للتقييم/الأدوات) | `POST /api/assistant/query` و`/draft` · `ops/tools/eval_ollama_models.py` يستعمل `/draft` | ✅ |
| A3 | جلسات المحادثة وتاريخها | إنشاء جلسة بتوكن، سرد الجلسات، استعادة التاريخ، لقطة محلية للمحادثة؛ منذ v37 كل توكن يُوسم بنوع سكّه (`mint_kind`) | `routers/chat.py` · `conversation_store.py` · `tg.chat_snapshot` في الجهاز · `POST /api/chat/restore-key` | ✅ |
| A4 | إيقاف الإجابة + إكمال البث بالخلفية | زر إيقاف؛ ترك التطبيق أثناء الإجابة لا يقتلها | `POST /api/chat/sessions/{id}/stop` · `StreamTracker` · `test/chat_background_stream_test.dart` | ✅ |
| A5 | الرد بلغة السؤال (ar/en/fr) | سؤال إنجليزي يُجاب إنجليزيًا (إصلاح 2026-08-21) | `intent_guard.detect_reply_language` · `llm_service` | ✅ |
| A6 | حظر النوايا الضارة، الطوارئ، الإساءة، الاختصارات الحوارية | يمنع الطلبات الخطرة قبل أي نموذج؛ يُصعِّد الطوارئ (أولويّتها فوق الفقه بعد إصلاح C1) | `services/intent_guard.py` (1408 سطرًا) | ✅ |
| A7 | دعم القلق الذاتي للأهل | يردّ برفق حين يتحدث الأب عن نفسه لا عن ابنه | أول مرحلة في `assistant.py` | ✅ |
| A8 | إحالة طبية بدل التشخيص | لا تشخيص ولا وصف أدوية؛ يوجّه لطبيب | `guardrails.is_medical_query/medical_referral_reply` · `policies.v1.yaml` | ✅ |
| A9 | حارس الفتوى/العقيدة | يحجب أسئلة الأحكام برد آمن ويسجّل في `blocked_fiqh_log` | `services/fiqh_guard.py` | ✅ |
| A10 | نيّة فقهية (ظلّي) | يقيس ما *كان* سيُحجب دون إنفاذ | `services/fiqh_intent.py` · `FIQH_INTENT_MODE=shadow` (الافتراضي off؛ الجدول غير موجود في الإنتاج) | 🟡 |
| A11 | حارس العقاب البدني | المربّي لا يوجّه أبدًا للضرب | `services/discipline_guard.py` | ✅ |
| A12 | مصنّف المجالات | يوجّه السؤال لـطبي/سيبراني/تربوي/تنموي/عقيدة/مساعدة-التطبيق؛ «لماذا خلق الله الشر؟» يذهب للعقيدة أولًا (2026-11) | `services/domain_classifier.py` (مسار سريع + كاش + LLM مساعد) · `test_evil_question_routing.py` | ✅ |
| A13 | إعادة صياغة العامّي | «ابني بيعض» → استعلام بحث أفضل (كاش 90 يومًا) | `services/query_rewriter.py` | ✅ |
| A14 | استرجاع هجين | متجه e5 + BM25 + RRF + Cross-Encoder مع فلترة العمر والمجال | `services/retrieval.py` · `bm25_index.py` · `reranker.py` | ✅ |
| A15 | دمج الساقين عبر المجالات | يمنع أن يطغى مجال على آخر في سؤال متعدّد المجالات | `RETRIEVAL_DOMAIN_FUSION` (global افتراضي؛ `per_domain` للتراجع) | ✅ |
| A16 | توجيه الجودة (سحابي/محلي) | أسئلة عالية الخطورة/مركّبة تذهب لنموذج أقوى | `services/tier_router.py` · `CLOUD_TIER_ENABLED` (افتراضي false) | 🟡 |
| A17 | سلسلة LLM بصمّام أمان | DeepSeek أساسي في الإنتاج؛ Ollama (tg-home) احتياطي؛ صمام شهري fail-closed | `ai_gateway.py` · `llm_config.py` · `LLM_PRIMARY_PROVIDER` | ✅ (الإنتاج على deepseek بحسب فحص 2026-08-11) |
| A18 | كاش الإجابات الدلالي | سؤال متكرر يُجاب فورًا بلا استدلال (أول سؤال في الجلسة فقط، TTL 45 يومًا) | `services/answer_cache.py` · `ANSWER_CACHE_ENABLED` (افتراضي false) · تسخين `warm_answer_cache.py` | ❓ (يتوقف على `.env` الإنتاج) |
| A19 | حصة AI يومية عادلة | 20 طلب/جهاز/يوم برفض لطيف «نستكمل غدًا بإذن الله» | `middleware/rate_limit.py` · `AI_DAILY_LIMIT` | ✅ |
| A20 | ميزانية سحابية دائمة | سقف توكنز شهري يُحجَز ويُسوّى لكل محاولة سلكية | `services/cloud_budget.py` · `CLOUD_BUDGET_ENFORCE` (افتراضي off؛ الجداول تُنشأ كسولًا عند أول معاملة دفتر؛ غائبة في الإنتاج بحسب جرد DB_SCHEMA_OWNERS 2026-10-08 (لم يُعاد التحقق الحيّ)؛ المخطط في `04` §3.1) | 🟡 |
| A21 | آيات وتفسير موثّق داخل الجواب | حين يذكر الأب آية، يُجلب تفسيرها الموثّق ويُدمج | `tafsir_service.resolve_ayah_reference/fetch_tafsir` → Tafsir MCP | ✅ |
| A22 | «مخصّص لـ<الاسم>» | الجواب يستعمل ما يعرفه المربّي عن الطفل (بإخفاء الاسم قبل النموذج) | `child_memory.py` · `privacy.py` · `widgets/personalised_chip.dart` · `CHILD_MEMORY_MIN_BUILD` | ✅ |
| A23 | شريط السلامة | لافتة فوق الرد تعتمد على حقول بنيوية فقط (لا على النص) | `widgets/safety_banner.dart` · حقول `AssistantReply` | ✅ |
| A24 | «سأجرّبها مع …» | خطوة واحدة يعد بها الأب من الجواب فتتحوّل لمتابعة | `features/companion/logic/answer_step.dart` · `noor_assistant_test.dart` | ✅ |
| A25 | تقييم الجواب 👍/👎 | يربط التقييم بالجلسة المملوكة للجهاز (إصلاح ملكية 2026-10) | `POST /api/feedback` · `routers/feedback.py` | ✅ |
| A26 | رؤى تربوية | تحليل نمط الطفل/الأسبوع بنص مولّد | `GET /api/insights/parenting` · `parenting_insights_screen.dart` | ✅ |
| A27 | مجال app_help الداخلي | أسئلة «كيف أستعمل التطبيق» تذهب لوحدات مساعدة لا تُكشف للعميل | `test_app_help_routing.py` · `test_app_help_stays_internal.py` | ✅ |
| A28 | نسخ/مشاركة إجابة نور | زرّان تحت الإجابة المكتملة: نسخ نص عادي (بلا Markdown) ومشاركة النص مع رابط التثبيت وكود الدعوة (1.0.76) | `widgets/message_bubble.dart` · `share/share_service.dart` (`plainAnswer`/`shareAnswer`) · `test/answer_share_test.dart` | ✅ |

---

## ب) المنهج والتعلّم

بيانات: `knowledge_base/curriculum/` — **43 مسارًا · 205 دروس · 220 نصيحة يومية** (+485 ملف ترجمة إنجليزية)، فوق **1060 وحدة معرفة عربية + 360 توأمًا إنجليزيًا**. وسائط الدروس خارج git (rsync).

| # | القدرة | ماذا تفعل للمستخدم | أين تعيش | الحالة |
|---|---|---|---|---|
| B1 | المسارات | قائمة مسارات تربوية بفئات عمرية (0-3…16-18 + 2-3 + الحمل) ومجالات | `GET /api/program/paths` · `paths_screen.dart` | ✅ |
| B2 | تفاصيل المسار «درب المسار» | الدروس بترتيب زجزاج مع تقدّم | `GET /program/paths/{id}` · `path_detail_screen.dart` | ✅ |
| B3 | الدرس | قراءة درس ≈5 دقائق + «جرّب هذا» + تأمّل + تحذيرات | `GET /program/lessons/{id}` · `lesson_screen.dart` (1191 سطرًا) | ✅ |
| B4 | «الدرس التالي»/متابعة | زر واحد يفتح الدرس الذي عليه الدور (رفع فتح أول درس 39%→54%) | `GET /program/next-lesson` · `TodayFocusCard` | ✅ |
| B5 | بودكاست الدرس | مشغّل صوت (179 عربي / 135 إنجليزي) | `GET /program/lesson-assets/{id}` · `podcast_player_screen.dart` | ✅ |
| B6 | فيديو | فيديو المسارات (وليس الدروس: الفهرس بلا فيديو دروس) | `video_player_screen.dart` · `docs/path_videos` | 🟡 |
| B7 | إنفوجراف | عرض مكبَّر قابل للتدوير والتنزيل (165 عربي / 47 إنجليزي) | `infographic_screen.dart` | ✅ |
| B8 | تقرير + جدول بيانات | تقرير Markdown وجدول CSV للدرس (160 عربي، **0 إنجليزي**) | `report_screen.dart` · `data_table_screen.dart` | 🟡 |
| B9 | بطاقات فلاش + اختبارات | مراجعة تفاعلية لـ165 درسًا | `GET /program/asset-content/{id}` · `flashcards_screen.dart` · `quiz_screen.dart` | ✅ |
| B10 | كويز «اختبر معلوماتك» | أسئلة عشوائية بمؤقّت ونقاط (مواضع الإجابة موزّعة) | `GET /program/quiz` · `quiz_game_screen.dart` · `quiz_data.py` | ✅ |
| B11 | بحث في المنهج | بحث نصّي بالدروس والمسارات والنصائح | `GET /program/search` · `search_screen.dart` | ✅ |
| B12 | تقدّم الدرس | in_progress/completed لكل طفل | `PATCH /program/lessons/{id}/progress` · `lesson_progress` (مفتاح لكل طفل) | ✅ |
| B13 | المفضلة | حفظ دروس ونصائح محليًا | `favorites_*` · `tg.favorites.v1` | ✅ |
| B14 | الشارات | شارات تُحسب من التقدّم ولا تُخزَّن | `program/data/badges.dart` · `badges_screen.dart` | ✅ |
| B15 | ملاحظات التأمّل | ملاحظة لكل درس (محلية) | `features/reflections/` · `tg.reflections.v1` | ✅ |
| B16 | العمل بلا شبكة | نسخة آخر منهج سليمة + شريط «نسخة محفوظة» | `curriculum_cache.dart` · `app_status_banner.dart` | ✅ |
| B17 | نصيحة اليوم (HTTP) | نصيحة حتمية يوميًا من مجموعة 220 | `GET /api/program/daily-tip` | ⚠️ لا عميل (بطاقتها حُذفت من التطبيق 2026-10-05) |
| B18 | المرشد الاستباقي | بطاقة نصيحة مخصّصة لطفل اليوم تتدهور رشيقًا لنصيحة عادية؛ ضغطة خفيفة تُسجَّل | `GET /program/coach-tip` + `POST …/{id}/tap` · `coach_service.py` · `coach_tip_card.dart` · `COACH_TIP_ENABLED` | 🟡 (افتراضي false؛ الإنتاج مفعّل بحسب ذاكرة 2026-06) |
| B19 | تحدّي الطفل الحالي | الأب يحدد تحديًا (عدواني، نوم…) فتتكيّف النصائح | `GET/PUT/DELETE /children/{id}/challenge` · `journey/data/challenges.dart` | ✅ |
| B20 | تقرير شهري | تقرير تقدّم شهري للطفل | `GET /api/program/monthly-report/{child_id}` | ⚠️ لا عميل في التطبيق |
| B21 | المحتوى الإنجليزي | 818 سجلًا مختومًا (دروس/وحدات/نصائح/قصص/مسارات) وفق بوابة تكافؤ بنموذجين | `ops/tools/review_en_parity.py` · `curriculum/i18n/en` · `docs/EN_CONTENT_STATUS.md` | ✅ (مراجعة آلية لا بشرية) |
| B22 | 4 ألعاب تعليمية | Data Defender · Emotion Maze · Healthy Hero · Tree of Deeds (Flame) بمستويات وسقف وقت؛ منذ 1.0.78 تظهر الألعاب بالإنجليزية في ركن الطفل أيضًا، ومواضع الإجابة الصحيحة موزّعة في حزم الألعاب (`balance_quiz_answer_positions.py`) | `features/games/` · `games_screen.dart` · `assets/content/games/*.json` (ar+en) | ✅ |
| B23 | مكتبة القصص «رف الحكايات» | رف كتب ليلي برف لكل سلسلة (الأنبياء · السيرة · الحكايات) — 47 قصة؛ الكتاب التالي غير المقروء يواجه القارئ ويتوهّج، ونجمة على المنتهي (1.0.76)؛ وقارئ بصفحات | `story_bookshelf_screen.dart` → `stories/shelf/magic_shelf.dart` · `read_stories.dart` (`tg.stories.finished`) · `story_reader_screen.dart` · `mobile/assets/data/stories(.en).json` · `test/magic_shelf_test.dart` | ✅ |
| B24 | «صورة حيّة» | لوحات القصص القديمة تتحرك (14 قصة) مع تجربة A/B ثابت/متحرك؛ والقصص الـ28 الجديدة لها لوحات ومشاهد (young/older) في `living_picture_catalog.dart`/`story_scene_catalog.dart` | `features/stories/living/` · `experiment/` · `POST /api/stories/events` · `STORY_MOTION_MODE` (افتراضي ab) | ✅ |
| B25 | «اسمعها من نور» | سرد صوتي صفحة-صفحة مع تظليل الجملة؛ أرقام الأحاديث بين قوسين تُعرض ولا تُقرأ (`word_cues.unspokenRanges`) | `features/stories/narration/` · `mobile/tool/gen_story_narration.py` | ✅ |
| B26 | روتين النوم | ثلاثة أذكار قبل النوم (لم تعد بوابة إجبارية أمام القصة)؛ مع نطق لاتيني ومعنى إنجليزي لكل ذكر (1.0.78) | `bedtime_routine_screen.dart` | ✅ |
| B27 | مولّد القصص المخصّصة | قصة قيمية بطلها الطفل — تُنفق عملات (توليد ذكاء اصطناعي) | `POST /api/program/story` · `coins/story_screen.dart` · كاش `story_cache` | ✅ (`STORY_AUTH_ENFORCE` مطفأ ⇒ هوية اختيارية) |
| B28 | المصحف + ورد | 114 سورة، ورد يومي، أخذ مكان آخر قراءة | `features/quran/` · `assets/data/quran.json` | ✅ |
| B29 | استماع آية-آية | 4 قرّاء (الحصري، المنشاوي، المعيقلي، الغامدي) من everyayah.com | `quran/models/reciters.dart` | ✅ (تبعية خارجية) |
| B30 | تفسير الآية | ورقة تفسير موثّق عند الضغط على آية | `quran/widgets/tafsir_sheet.dart` · `GET /api/tafsir/{surah}/{ayah}` (+`/nuzool`) | ✅ |
| B31 | تتبّع حفظ القرآن | قائمة 114 سورة لكل طفل | `journey/screens/quran_memorization_screen.dart` | ✅ |
| B32 | أذكار/محتوى الأسرة | 281 عنصرًا (142 آية، 124 نصيحة، 15 حديثًا) تصفّح + إشعار يومي واحد؛ ومعنى إنجليزي ومصدر إنجليزي تحت النص العربي، والبحث يشملهما (1.0.78) | `features/adhkar/` · `assets/content/adhkar/*.json` | ✅ |
| B33 | مسبحة | عدّاد محلي بهدف يُحفظ | `tools/screens/tasbeeh_screen.dart` | ✅ |
| B34 | محوّل هجري↔ميلادي | حساب جدولي محلي | `tools/screens/hijri_converter_screen.dart` | ✅ |
| B35 | بدائل بلا شاشة | أنشطة بديلة يُحال إليها الطفل عند منع الشاشة؛ شرائح العمر مترجمة | `offscreen/offscreen_activities_screen.dart` · `assets/data/offscreen_activities*.json` | ✅ |
| B36 | بحوث قرآنية لغوية (API) | جذور/آيات الجذر/مواضيع/قراءات | `/api/quranic-linguistics/*` · `quranic_linguistics_service.py` (Bahouth MCP) | 🟡 API عام بلا عميل (اختبارات للخدمة لا للراوتر) |
| B37 | بحث التفسير (API) | `search` و`search-tafsir` و`sources` | `/api/tafsir/{search,search-tafsir,sources}` | ⚠️ بلا عميل |
| B38 | «قصص الأنبياء من القرآن» | 20 قصة (10 قصص × young/older): يونس، سليمان والنمل، نوح، إبراهيم والنار، البيت، تابوت موسى، البحر، يوسف، أيوب، زكريا — لا يُقال عن نبي إلا ما قاله القرآن، بلا تصوير أشخاص | سلسلة `anbiya_quran` في `stories.json` · `story_models.dart` (`kAnbiyaSeries`) · `docs/stories/anbiya_*` · حارس `check_anbiya_stories.py` · `/methodology#prophets` | ✅ (بلا مراجع بشري — مُعلَن في المنهجية) |
| B39 | «من السيرة النبوية» (الموسم الثاني) | 8 قصص (4 × young/older): الغار، المسجد، الجذع، أبو عمير — القرآن والصحيحان فقط، والحديث حرفيًا برقمه | سلسلة `sira_sahih` · `kSiraSeries` · `docs/stories/sira_*` · حارس `check_sira_stories.py` · `/methodology#seerah` · `test/seerah_stories_test.dart` | ✅ |

---

## ج) الأطفال ووضع الطفل (سطح الطفل)

| # | القدرة | ماذا تفعل للمستخدم | أين تعيش | الحالة |
|---|---|---|---|---|
| C1 | ملفات أطفال متعدّدة | إضافة/تعديل/حذف/تبديل الطفل النشط، أفاتار | `children.py` · `children_list_screen.dart` · `add/edit_child_screen.dart` | ✅ |
| C2 | تصفير التقدّم/حذف الطفل | يمسح كل ما يخص الطفل (P3 review) | `DELETE /children/{id}[/progress]` | ✅ |
| C3 | شهر الميلاد الاختياري | يضبط توقيت المراحل دون يوم | `widgets/birth_month_field.dart` · `child_profiles.birth_month` | ✅ |
| C4 | «حِساب اليوم» (0–6) | تسجيل رضاعة/نوم/حفاض + ملخّص | `daily_routine.py` · `daily_routine_screen.dart` | ✅ |
| C5 | «ميزان العادات» (7–18) | عادات حسب العمر + قوالب مخصّصة + سلسلة + شريط 7 أيام | `value_tracking.py` · `habit_templates.py` · `habit_customize_screen.dart` | ✅ |
| C6 | وضع الطفل + PIN | يسلّم الأب الجهاز لطفل في واجهة بسيطة؛ الخروج بـPIN محلي | `routine/screens/child_mode_lock_screen.dart` · `child_mode_secure_storage.dart` | ✅ |
| C7 | ميزانية وقت الشاشة (خادم) | حدّ يومي يُحسب من النبض لا من ساعة الجهاز، مع أرضية 24 ساعة | `services/child_budget.py` · `POST /value-tracking/child-mode/{heartbeat,session-end}` | ✅ (`CHILD_SURFACE_ENABLED` مفتاح قتل) |
| C8 | بوابة العمر للأسطح | أي أسطح يراها كل فئة عمرية — يُنفَّذ بالخادم وتُطابقه نسخة العميل | `guardrails/child_surface.v1.yaml` · `child_surface_policy.dart` | ✅ |
| C9 | باب التسليم + شاشة العودة | مكان واحد يسلّم فيه الأب الجهاز وينتهي عنده كل سطح | `features/handover/` | ✅ |
| C10 | ركن الطفل | مشهد ورق مقصوص: قصة وحدة ولعبة واحدة اليوم + «شمعة وقتك» | `features/child_corner/` | ✅ |
| C11 | بطاقة المهمة بعيدًا عن الشاشة | 60 ثانية شاشة مقابل 15 دقيقة نشاط؛ لا تكرار 3 أسابيع؛ بطاقة واحدة اليوم | `child_missions.py` · `missions/child_mission_screen.dart` · `curriculum/missions/*.json` | ✅ |
| C12 | تأكيد المساء + كلمة طيبة | الأب يؤكد مهام الطفل مرة واحدة مساءً ويرسل كلمة طيبة | `missions/pending_missions_screen.dart` · `GET/POST /children/missions/{pending,confirm}` · `praise_header.dart` | ✅ |
| C13 | ملخّص المساء | إشعار واحد 21:00 للأب | `services/mission_digest.py` (في حلقة `main.py`) | ✅ |
| C14 | الاتفاقية الأسرية للإعلام | بنود مزدوجة أهل/طفل، توقيع لكل بند ثم لكل شخص، تصدير كصورة | `family_agreement.py` · `features/agreement/` · `AGREEMENT_REQUIRED` (إلزامها مطفأ) | 🟡 (موجودة، وإلزام التوقيع مطفأ) |
| C15 | رخصة الإنترنت (مستوى 1) | مواقف تدريبية (غريب على الإنترنت…) ثم «حديث الأسرة» ثم منح (لا صلاحية فعلية) | `child_license.py` · `features/license/` · `curriculum/license/*.json` · إشعار `license_alert` | ✅ |
| C16 | صفحة المراهق عبر QR | الأب يولّد رمزًا (120ث، مرة واحدة) فيفتح المراهق صفحة ويب بلا تطبيق | `child_mode_web.py` · `backend/static/child_mode/` · `child_web_claims` | ✅ (إصلاح `?claim=` 2026-10-18) |
| C17 | يوم الأب/يوم الطفل | ما يراه الأب عن اليوم (شاشة ≠ استماع كصفّين) | `features/parent_day/` · `GET /children/{id}/today` | ✅ |
| C18 | استماع بشاشة مطفأة | تشغيل صوت دون شاشة (يحلّ التوتر بين وقت الشاشة والاستماع) | `features/screen_off/` | 🟡 يتوقف عند خلفية Android (مقصود بعد سحب `just_audio_background`) |
| C19 | تسجيل صوت الأب لقصة | يسجّل الأب قصة بصوته ويحتفظ بها على الجهاز | `screen_off/record_narration_screen.dart` · `narration_store.dart` | ✅ |

---

## د) برامج الأسرة والمرافقة («نور والقناديل»)

| # | القدرة | ماذا تفعل للمستخدم | أين تعيش | الحالة |
|---|---|---|---|---|
| D1 | «نور يتذكّر» | جملة واحدة حقيقية كل فتحة من بيانات الأسرة (مهمة تنتظر، متابعة، مناسبة) بعقل حتمي | `features/companion/` · `companion_brain.dart` | ✅ |
| D2 | درب اليوم + سماء | ثلاث محطات تحت سماء تتغيّر مع الوقت (فجر/نهار/مغرب/ليل) | `home/widgets/today_road.dart` · `sky_band.dart` | ✅ |
| D3 | قناديل الأسبوع | قنديل يُضاء لكل فعل تربوي حقيقي (عدّاد صادق، لا «فاتك») + ورقة الأفعال | `GET /api/family/week` · `family_actions.py` · `features/lanterns/` | ✅ |
| D4 | حصاد الجمعة | بطاقة نور الجمعة تُشارَك كصورة | `lanterns/widgets/friday_harvest.dart` | ✅ |
| D5 | درب الأسرة + «على الأفق» | طريق الأسرة مع الطفل والبوابات القادمة وما أضأتموه | `features/family_road/` | ✅ |
| D6 | المتابعات «جرّبت النصيحة؟» | سؤال متابعة مسائي 19:00 بتوقيت الأسرة + «ذكّرني غدًا» | `followups` · `followup_push.py` · `child_memory/widgets/followup_sheet.dart` | ✅ |
| D7 | خطة الأسبوع | تركيز واحد + 3 أفعال + عمل عبادة، علامات إنجاز | `GET /children/{id}/weekly-plan` · `PUT`/`DELETE /children/{id}/weekly-plan/marks` · `weekly_plan.py` | ✅ |
| D8 | ذاكرة الطفل | حقائق عن الطفل يعدّلها الأب ويحذفها؛ مفتاح تشغيل/إيقاف للجهاز | `child_memory.py` · `child_memory_screen.dart` · `memory_switch_tile.dart` | ✅ (يتطلب إثبات الجهاز) |
| D9 | «رمضان العائلة» | يوم رمضان، علامات «تمّ» الأسرية، بطاقة «رمضان عائلتنا» | `ramadan_program.py` · `features/programs/screens/ramadan_*.dart` | ✅ (الموعد الصلب ≈ 8 فبراير 2027) |
| D10 | سلّم الصيام | تدرّج صيام الطفل مع إرشاد سلامة ظاهر دائمًا | `fasting_ladder_screen.dart` · `ramadan_fasting` | ✅ |
| D11 | رحلة الصلاة | مراحل تدريب الطفل على الصلاة بمهام يومية (بلا عقاب ولا رجوع مُسجَّل) | `prayer_journey.py` · `prayer_journey_screen.dart` · `child_prayer_card.dart` | ✅ |
| D12 | المراحل الاستباقية | «ابنك هيكمّل ٧ سنين الشهر الجاي» + إشعار قبل شهر 20:00 | `milestones.py` · `milestone_push.py` · `milestones_screen.dart` | 🟡 الإشعار مشروط بـ`MILESTONES_MIN_BUILD` (غير مضبوط افتراضيًا) |
| D13 | لحظة العيد + لحظة اكتمال البدر + لحظة مرحلة الصلاة | لحظات احتفال هادئة | `eid_moment.dart` · `full_moon_moment.dart` · `prayer_stage_moment.dart` | ✅ |
| D14 | رحلة الطفل | سجل معالم روحية محلي لكل طفل (شهادات/صور شارات) | `features/journey/` · `tg.journey.v1` | ✅ |
| D15 | العملات والعهود والشارات الحصرية | عملة محلية؛ العهد = مكافأة واقعية يتفق عليها الأهل خارج الشاشة؛ الشارات تُكتسب لا تُشترى | `features/coins/` | ✅ |
| D16 | هدية اليوم + احتفالات | لحظة فرح عند أول درس/شارة/عملة بمستويين صوتًا | `daily_gift_moment.dart` · `celebration_overlay.dart` | ✅ |
| D17 | جولة أول تشغيل | تسليط ضوء على التبويبات (يدوية) | `features/tour/` | ✅ |
| D18 | التهيئة السريعة | عمر + اسم الطفل في <90 ثانية | `onboarding_screen.dart` (1286) | ✅ |
| D19 | الشاشة الرئيسية «اليوم» (`HomeScreen`، تبويب الرئيسية) | ثلاث محطات للطفل النشط: ① خطوة اليوم (`TodayFocusCard` تفتح الدرس التالي) ② اسأل المربّي (نصيحة المرشد + مدخل سؤال دائم) ③ مهمة الطفل أو «يوم الطفل»؛ بينها بطاقة خطة الأسبوع/المتابعة وتحت ③ بطاقة برامج الأسرة (إن قدّمها الخادم)؛ وتحت الفاصل بقية الاختصارات | `mobile/lib/screens/home_screen.dart` (510) · `features/home/` · `features/companion/widgets/noor_today_header.dart` · `today_three_blocks_test.dart` | ✅ |
| D20 | تبويب «المزيد» (`HubScreen`) | فهرس مسطّح مجمَّع بأيقونات لكل ما خارج الحلقة اليومية (الطفل · الألعاب · الإنجازات · المكتبة · الأدوات · المساعدة) مع زر مساعدة سياقي؛ المجموعات والعناصر من كتالوج بيانات واحد تُخفى عناصره بحسب العمر/توفّر البرامج | `features/hub/screens/hub_screen.dart` · `features/hub/data/hub_catalog.dart` · `widgets/hub_group_card.dart` · `widgets/help_sheet.dart` · `test/hub_catalog_test.dart` | ✅ |

---

## هـ) النمو والتوزيع

| # | القدرة | ماذا تفعل | أين تعيش | الحالة |
|---|---|---|---|---|
| E1 | كود دعوة شخصي + مطالبة | كل أب يدعو بكوده؛ يُحسب «أثر دعوتك» | `routers/referral.py` · `invite_screen.dart` | ✅ |
| E2 | أكواد الحملات | `/go?ref=DA01` (حرفان+رقمان) تُقرأ كحملة وتُسجَّل `campaign#CODE` | `attribution.py` · `ops/data/campaign_codes.md` · OPS_RUNBOOK §6.5 | ✅ |
| E3 | إسناد التثبيت | Play referrer + مطابقة IP خلال 24 ساعة (`via=auto`) | `services/attribution.py` · `referral_service.dart` | ✅ |
| E4 | صفحة الهبوط | عربي/إنجليزي سينمائي، أزرار تنقل `utm_*` إلى Google Play | `routers/web.py` · `frontend/cinematic*.html` | ✅ |
| E5 | صفحات مشاركة الدرس/المسار | `/l/{id}` `/p/{id}` بـOG — بالعربية أو الإنجليزية حسب لغة الزائر (1.0.78، `Vary: Accept-Language`) | `web.py` | ✅ |
| E6 | صفحات SEO + منهجية | أسئلة الألم الشائعة + «منهجيتنا ومصادرنا» على alsaba.cloud؛ والمنهجية تشرح قصص الأنبياء والسيرة (`#prophets`، `#seerah`) | `seo.py` · `methodology.py` | ✅ (عبر وكيل analytics_nginx) |
| E7 | روابط تطبيق Android | `https://tg-api.alsaba.cloud/{go,l,p}` تفتح التطبيق | `.well-known/assetlinks.json` · `deep_link_handler.dart` | ✅ |
| E8 | بطاقات المشاركة | تحويل أي لحظة إلى صورة PNG | `features/share/` | ✅ |
| E9 | بطاقة «ادعُ صديقًا» | تظهر عند لحظات الفخر فقط (سلسلة ≥7 أيام) | `referral/pride_invite_card.dart` | ✅ |
| E10 | «يربّون بثقة معنا» | عدّاد مجتمع عام | `GET /api/stats/community` · `community_proof_card.dart` | 🟡 الرقم منفوخ (يعدّ كل جهاز سجّل طفلًا؛ الإصلاح مؤجّل ≈2026-11-21) |
| E11 | طلب تقييم المتجر | مرة واحدة بعد لحظات إيجابية | `program/data/review_prompt.dart` | ✅ |
| E12 | «الجديد في التحديث» + شاشة إيه الجديد؟ | تُخبر من لديهم التطبيق بما تغيّر (بدل دفع الجميع) | `whats_new/` · `update_splash_screen.dart` | ✅ |
| E13 | التحديث الإجباري | `minimum_build_number` من الخادم؛ تُغلق بوابة التطبيق على بناء أقدم | `GET /api/app-config` · `main.dart ForceUpdateScreen` · `ops/scripts/min_build.sh` | ✅ (الحدّ يُقرَّر بالتعداد) |
| E14 | دفع لطيف للتحديث | إشعار لمن هم تحت بناء معيّن | `ops/scripts/send_update_push.py` | ✅ |
| E15 | روابط «تابعنا» | قنوات التطبيق الرسمية (حسابات المربّي الرسمية؛ YouTube وX مضافان) | `program/widgets/follow_us_row.dart` · `core/social_links.dart` | ✅ |
| E16 | تقارير النمو | حملات، قمع، فجوات معرفة، GA4 cohorts | `ops/scripts/*report*.py` · `scripts/ga4_cohort_report.py` | ✅ |
| E17 | ردود تعليقات Play | مسودات ردود للتعليقات | `scripts/play_reviews.py` · `ops/reports/PLAY_REVIEW_REPLIES.md` | ✅ |
| E18 | بطاقة «نسخة جديدة متاحة» | بطاقة اختيارية قابلة للإغلاق في «اليوم» لمن بناؤه أقدم من آخر بناء — لا جدار إجباري؛ تُغلق مرة لكل بناء | `whats_new/widgets/update_available_card.dart` · `home_screen.dart` · `latest_build_number` في `GET /api/app-config` ← `LATEST_BUILD_NUMBER` | 🟡 (افتراضي 0 = لا تظهر؛ تتوقف على قيمة المتغير في الإنتاج) |
| E19 | إشعارات إعادة التفاعل | أول درس (2–36 ساعة) → اليوم الثاني (18–42 ساعة) → «السلسلة في خطر» (36 ساعة–7 أيام) → «اشتقنا لك» (7–60 يومًا)؛ سقوف لكل غياب وفاصل 7 أيام، بلغة الأسرة (ar/en) — توقف إزعاج الأجهزة المنقطعة (2026-11-06) | `ops/scripts/cron_push_triggers.py` (كرون 17:00 UTC) · `test_cron_push_triggers.py` | ✅ |

---

## و) الحساب والخصوصية والأمان

| # | القدرة | ماذا تفعل | أين تعيش | الحالة |
|---|---|---|---|---|
| F1 | هوية مجهولة بجهاز | لا حسابات؛ `device_id` يُمنح جلسة بتوكن مُجزَّأ ينقضي منزلقًا؛ منذ v37 يُسجَّل نوع السكّ (new/proof/restore/bare)، و«العاري» يورَّث | `chat.py` · `conversation_store.py` · `tg_client.dart` | ✅ |
| F2 | إثبات الجهاز (FCM) | تحدّي صامت يثبت أن الجلسة تحمل الهاتف قبل مسارات الذاكرة/الحذف | `device_proof.py` · `core/proof.py` · `device_proof_service.dart` | ✅ (15 مسارًا؛ `SESSION_MINT_ENFORCE` مطفأ افتراضيًا — مع تفعيله يصبح السكّ العاري جهازًا جديدًا فارغًا للبنايات ≥117 و401 لما قبلها) |
| F3 | ربط Google اختياري | «احفظ تقدّمك» — المدخل أُخفي في 1.0.76 (لا عميل OAuth لمفتاح توقيع Play) وعاد في 1.0.77؛ التأكيد يرفض الجلسة «العارية» ويتطلب وصولًا لا رجعة فيه | `identity.py` · `identity_screen.dart` · `identity/identity_entry.dart` (`kGoogleAccountEntryEnabled = true`) · `test/google_account_entry_test.dart` | ✅ |
| F4 | دمج عائلات عبر الأجهزة | دمج عائلة الجهاز القديم في الحساب؛ صار يحترم شواهد الحذف (ما حذفه الوالد لا يعود) ومفتاح ذاكرة الجهاز الهدف | `IDENTITY_CROSS_DEVICE` · `services/merge_tombstones.py` · `ops/tools/bare_mint_readiness.py` (قرار التفعيل) | 🟡 مطفأ (يُفعَّل مع `SESSION_MINT_ENFORCE` بعد أن يقول مقياس الجاهزية ذلك) |
| F5 | إخفاء أسماء الأطفال | تُستبدل بعناصر نائبة قبل أي نص يغادر لنموذج | `services/privacy.py` | ✅ |
| F6 | حذف ذاكرة الأطفال | زر «انسَ كل شيء عن أطفالي» | `DELETE /api/privacy/memory` | ✅ |
| F7 | حذف الحساب داخل التطبيق | حذف كامل + مسح محلي + إنهاء التطبيق (شرط Play) | `DELETE /api/privacy/account?confirm=true` · `account_deletion_screen.dart` · `/delete-account` | ✅ |
| F8 | حذف بالبريد | لمن بلا تطبيق | `ops/scripts/delete_account.py` | ✅ |
| F9 | سياسة الاحتفاظ | تنفيذ يومي: 90 يومًا لسجلات البحث، 45 للكاش، 7 لنقرات الإحالة… | `services/retention.py` (ضمن `cron_push_triggers.py`) | ✅ |
| F10 | إصلاح «توائم الجهاز» | معرّفان لتثبيت واحد (محرّكا Flutter) تُدمج صفوفهما | `device_twins.py` · `ops/tools/repair_device_twins.py` | ✅ |
| F11 | سجل الأجهزة المحذوفة | الحساب المحذوف يبقى محذوفًا | `erased_devices.py` | ✅ |
| F12 | نسخ/استعادة محلي | تصدير واستيراد JSON لبيانات الجهاز | `program/data/backup_service.dart` · settings | ✅ |
| F13 | مزامنة Zero-Knowledge | رفع/تنزيل نسخة مشفّرة (AES-GCM/Scrypt) | `routers/sync.py` · `crypto_sync.py` | ⚠️ لا عميل في التطبيق؛ `crypto_sync.py` بلا مستورد؛ ونسخة جهاز آخر لا تُعاد إلا مع `IDENTITY_CROSS_DEVICE` ورابط مؤكَّد |
| F14 | ادعم المربّي | شراء Play استهلاكي لا يفتح شيئًا + صفحة شفافية بالتكلفة | `donations.py` · `support.py` · `features/support/` | 🟡 `DONATIONS_ENABLED` مطفأ (بانتظار ملف التاجر/المنتجات/حساب خدمة مقيّد) |
| F15 | ملاحظات المستخدم | نص أو صوت (8MB) → تلجرام؛ ردّ تلجرام يصل داخل التطبيق | `feedback.py` · `feedback_screen.dart` · `feedback_replies_section.dart` | ✅ |
| F16 | إشعارات | تسجيل FCM + قنوات + إشعار محلي يومي + تنبيه فقدان التوكن؛ تغيّر التوكن بلا إثبات يُلغي تأكيد روابط Google | `push.py` · `push_service.dart` · `device_alerts.py` | ✅ |
| F17 | مقاييس تشغيل | p95، توكنز/مزوّد، نسبة الكاش، استهلاك الصمام | `GET /api/stats/ops-llm` (`X-Ops-Token`) | ✅ |
| F18 | إرسال إشعار يدوي | لجهاز واحد | `POST /api/admin/send-push` (`X-Admin-Key`) | ✅ |
| F19 | مفتاح الاستعادة | بعد إعادة التثبيت من نسخة أندرويد الاحتياطية يثبت الجهاز هويته بمفتاح `tgr_…` (الخادم يحفظ بصمته فقط) فتعود العائلة دون فتح «السكّ العاري» (1.0.77) | `POST /api/chat/restore-key` · `services/restore_keys.py` · `device_restore_keys` · `tg_client.dart` (`ensureRestoreKey`، ترويسة `X-Device-Restore`) · `backup_rules.xml` · `test_bare_mint_closure.py` · `test/restore_key_test.dart` | ✅ |

---

## ز) خطوط المحتوى والتشغيل (للمشغّل — خارج مسار المستخدم)

| # | القدرة | ما تفعله | أين تعيش | الحالة |
|---|---|---|---|---|
| G1 | حارس سلامة قاعدة المعرفة | يقارن الوحدات ↔ schema ↔ taxonomy ↔ Chroma | `ops/tools/check_kb_integrity.py` · `check.sh` · pre-commit · CI | ✅ |
| G2 | حرّاس المحتوى الشرعي | مطابقة الآيات بالمصحف، الأحاديث بالصحيحين، منع ترجمة القرآن، تغطية كل نص شرعي، أصالة الأذكار | `check_quran_*`, `check_hadith_citations`, `check_scripture_coverage`, `check_adhkar_integrity`, `scripture_scan` | ✅ (لا تُعطَّل self-tests) |
| G3 | بوابة تكافؤ الإنجليزي | ترجمة بنموذج + مراجعة عدائية بنموذج من عائلة أخرى + ختم | `review_en_parity.py` (2545 سطرًا) · `translate_*.py` | ✅ |
| G4 | أمانة الوحدات لمصدرها | يكشف الوحدات المنحرفة عن مصدرها ويحجرها (210 وحدة حُجرت 2026-10-04) | `check_kb_fidelity.py` · `ops/data/kb_fidelity/` | ✅ |
| G5 | تعميق المسارات | دروس مكتوبة من الوحدات بمراجعة عائلة نموذج أخرى | `ops/tools/deepen_paths.py` | ✅ |
| G6 | خط وسائط الدروس | تحويل الدروس إلى NotebookLM ثم بودكاست/فيديو/إنفوجراف/تقرير/جدول | `scripts/*podcast*`, `generate_missing_*`, `cron_gen_*.sh`, `lib/nblm_session.sh` | ✅ (حصص يومية؛ جلسة تنتهي) |
| G7 | مصنع الريلز | قصّ بودكاست/فيديو إلى 9:16 + نشر Buffer؛ ريلز حملة «نور» بـRemotion | `scripts/reel_from_video.py`, `podcast_to_reel.py`, `publish_reels_to_buffer.py`, `remotion-reels/` | ✅ |
| G8 | نشر اجتماعي آلي | نصائح + صور إلى Buffer وقناة تلجرام | `ops/tools/social_media_autoposter.py` | ✅ |
| G9 | رفع Google Play | AAB موقَّع، قائمة المتجر، التحقق والنشر 100%، ردود التعليقات | `scripts/play_upload.py`, `release_play_*.py`, `play_listing_upload.py`, `release-play.yml` | ✅ (`play_upload.py` يرفع مقطّعًا CHUNK_BYTES بعد إصلاح مهلة الحزم الكبيرة) |
| G10 | نشر الباكند | gate→image→deploy على VPS (runner `vps-tg`) مع تراجع تلقائي؛ الصورة `ghcr.io/almorabbi/almorabbi-backend` تُسحب بتوكن المهمة؛ الـgate لا يعمل إلا في `almorabbi/almorabbi` مع `vars.CUTOVER_DONE == true` (مضبوط) | `.github/workflows/deploy.yml` | ✅ |
| G11 | تقارير تلجرام الأسبوعية | داشبورد + قمع + فجوات معرفة | `ops/scripts/weekly_*.py` | ✅ |
| G12 | نسخ احتياطي يومي | sqlite online backup + integrity_check | `ops/scripts/backup_user_data.sh` | ✅ |
| G13 | E2E على المحاكي | رحلات Maestro fresh/upgrade + تجربة رمضان + معرض لقطات | `e2e/` · `mobile-e2e.yml` | ✅ |
| G14 | تقييم جودة الإجابات | مجموعة ذهبية، تقييم نماذج، تقرير CI غير حاجب | `ops/tools/golden_ci.py`, `eval_answers.py`, `build_golden_set.py` | ✅ |
| G15 | ضبط/تقطير نموذج | بيانات QA، Kaggle/Colab LoRA لـcommand-r7b-arabic | `ops/kaggle/`, `ops/colab/`, `ops/tools/push_kaggle_v6_*.py` | ❓ تاريخي (الإنتاج على DeepSeek) |
| G16 | تجارب Chroma 1.x | قياس استدعاء/تشغيل/ترحيل فهرس Chroma 1.x | `ops/tools/chroma_*_probe.py` · workflows `chroma-1x-*` | 🟡 تجارب يدوية (الإنتاج مثبّت على <1) |
| G17 | تشخيص جاهزية وقت التشغيل | تقرير مشفّر يُقرأ فقط | `runtime_readiness_report.py` · `runtime-readiness.yml` | ✅ |
| G18 | إثراء الوحدات القديم | سكربتات `enrich_*` بمسارات مطلقة | `ops/tools/enrich_*.py`, `fix_one_unit.py` | ⚠️ ميتة/تاريخية |
| G19 | حارسا قصص الأنبياء والسيرة | يمنعان الالتزام/الدمج إن خالفت قصة مصادرها: حوار مخترع، اسم/رقم غير موجود، حديث غير حرفي، جملة لم تدعمها عائلتا نماذج | `ops/tools/check_anbiya_stories.py` · `check_sira_stories.py` · `.githooks/pre-commit` · `backend.yml` | ✅ (exit 2 = اختباراته الذاتية) |
| G20 | توثيق المصادر ومراجعة الأمانة للقصص | جلب الآيات/الميسّر/أحاديث الصحيحين إلى `ops/data/{anbiya,sira}/`، ثم حكم جملةً جملة بعائلتين | `anbiya_sources.py` · `sira_sources.py` · `anbiya_fidelity.py` | ✅ يدوي (يحتاج `OLLAMA_API_KEY` للحكم) |
| G21 | مقياس جاهزية إغلاق السكّ العاري | أعداد فقط: أجهزة نشطة بمفتاح استعادة، وجلسات يومية حسب `mint_kind` | `ops/tools/bare_mint_readiness.py` | ✅ يدوي |

---

## ملخّص الحالات

- **✅ يعمل:** الأغلبية الساحقة من سطح المنتج (المساعد، المنهج، سطح الطفل، البرامج، النمو، الخصوصية).
- **🟡 مشروط بعلم/نشر:** A10 A16 A20 B6 B8 B18 B36 C14 C18 D12 E10 E18 F4 F14 G16.
- **⚠️ غير موصول/ميت:** B17 B20 B37 F13 G18 + ملفات ميتة موثّقة في `08-gotchas.md` §3 (`crypto_sync.py`، `frontend/engine.js`… — الملفات الميتة الثلاثة و`.bak` حُذفت 2026-11-08).
- **❓ يتوقف على الحيّ:** A18 G15 (+ قيم الأعلام الفعلية على VPS).
