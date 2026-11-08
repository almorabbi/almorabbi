# 04 — البيانات: الجداول والملفات والتخزين

> مصدر الجداول: DDL الفعلي في `backend/app/db/init_db.py` + الخدمات + `docs/DB_SCHEMA_OWNERS.md` (جرد 2026-10-08). **أسماء أعمدة فقط — لا بيانات أسر.** البيانات الحساسة (أسماء أطفال، حقائق، إجابات، ملاحظات صوتية) موسومة 🔒.

## 1) قاعدتا SQLite في الإنتاج (volume `tg_sessions` ⇒ `/app/ops`)

| الملف | الإصدار | المحتوى | ملاحظات |
|---|---|---|---|
| `ops/conversations.db` (`CONVERSATIONS_DB`) | جدول `schema_version` = **37** (`SCHEMA_VERSION`)؛ `PRAGMA user_version` = 0 | بيانات المنتج والمستخدمين — **حرجة**، عليها النسخ اليومي | 54 جدولًا؛ 51 يملكها `init_db` (+32 دالة `_ensure_*`؛ v37 أضاف `device_restore_keys` و`merge_tombstones` وعمود `api_tokens.mint_kind`) |
| `ops/sessions.db` (مسار مكتوب في كل خدمة؛ `ANSWER_CACHE_DB` لواحدة) | سجلّ `schema_migrations` (مشغّل الترحيلات) | تيليمتري وكاشات وسجلات — قابلة نظريًا لإعادة البناء لكنها مصدر مقاييس التكلفة | الترحيلات المرقّمة تغطي 5 مالكين فقط |
| دفتر الميزانية السحابية (جداول داخل `ops/sessions.db` نفسه — `ai_gateway._ledger()` يمرّر `_TELEMETRY_DB` — + ملف مرساة `<db>.cloud-budget-anchor` بجانبه أو حيث يشير `CLOUD_BUDGET_ANCHOR_PATH`) | — | 9 جداول دفتر + 24 trigger (انظر §3.1) | تُنشأ **كسولًا** عند أول معاملة دفتر (`CloudBudget._create_schema`)؛ مسار الطلب لا يستدعي الدفتر إلا مع `CLOUD_BUDGET_ENFORCE` مفعّلًا (افتراضيًا مطفأ)، وCLI التهيئة `cloud_budget_bootstrap` يعمل على ملف قائم. غائبة في الإنتاج بحسب جرد `docs/DB_SCHEMA_OWNERS.md` (2026-10-08، البنود 17–18) — ولم يُعاد التحقق الحيّ منذئذ (يتوقف على قيمة العلم هناك) |

WAL + `busy_timeout` على الكل. لا تفتح الحيّة بأدوات كتابة من خارج الحاوية.

## 2) `conversations.db` — الجداول بحسب المجال

### المحادثة والهوية
| الجدول | الأعمدة الجوهرية | الغرض | حساس |
|---|---|---|---|
| `chat_sessions` | id, device_id, created_at, updated_at, metadata | جلسة محادثة لكل جهاز | |
| `chat_messages` | id, session_id, role, content, domain, severity, mode, needs_human_review, created_at (+model, guardrail_version: ⚠️ غائبتان في الإنتاج) | رسائل | 🔒 |
| `api_tokens` | token(hash), device_id, session_id, expires_at, created_at, mint_kind (v37: new/proof/restore/bare؛ NULL = قبل v37) | توكنات الجلسات (مجزّأة، انقضاء منزلق)؛ «العاري» يورَّث للتوكن المشتق منه | 🔒 |
| `device_restore_keys` | device_id, key_hash, created_at, last_used_at | مفتاح الاستعادة (v37، `services/restore_keys.py`): بصمة sha256 فقط؛ مفتاح واحد لكل جهاز وإعادة الإصدار تستبدله | 🔒 |
| `merge_tombstones` | device_id, kind (child/fact/memory), key_hash, created_at (مفتاح أساسي: الثلاثة الأولى) | شواهد الحذف (v37، `services/merge_tombstones.py`): ما حُذف لا يعود في دمج Google | |
| `user_feedback` | id, session_id, message_id*, rating, comment, created_at | تقييم 👍/👎 (*غير موجود في الإنتاج) | |
| `app_feedback` | id, message, contact, audio_file, device_id, app_version, created_at | ملاحظات التطبيق (نص/صوت) — مُنشأ من `routers/feedback.py` لا من init_db | 🔒 |
| `feedback_replies` | id, feedback_id, device_id, reply_text, created_at, delivered_at, read_at | ردود المسؤول | |
| `tg_updates_seen` | update_id, seen_at | تكرار تحديثات تلجرام | |
| `parent_identities`, `identity_links` | google_id, email, display_name · device_id, google_id, linked_at, confirmed | ربط Google اختياري | 🔒 |
| `device_aliases`, `device_fold_log` | canonical_device, folded_at · table_name,row_id,from_device,to_device,action,row_json | إصلاح توائم الجهاز + سجل الدمج | 🔒 |
| `erased_devices` | — | الحساب المحذوف يبقى محذوفًا | |
| `push_tokens`, `push_sends` | device_id, token, platform, app_version, build_number, token_since/vouched/first · device_id, kind, sent_at | توكنات FCM وسجل الإرسال (سقف 1/يوم) | 🔒 |
| `device_alerts` | device_id, old_token, queued_at, sent_at | تنبيه فقدان التوكن | |
| `device_proof_challenges/_sessions/_proofs` | token_hash, code_hash, push_token_hash, proven_at, first_proven_at | تحدّي إثبات الجهاز | 🔒 |

### الأطفال والتقدّم
| الجدول | الأعمدة | الغرض | حساس |
|---|---|---|---|
| `child_profiles` | id, device_id, name, age_group, gender, avatar_emoji, birth_month, created/updated_at | ملف الطفل | 🔒🔒 |
| `lesson_progress` | device_id, child_id, path_id, lesson_id, status, started/completed_at, score | تقدّم الدروس (فريد على device+child+lesson؛ ترحيل مدمّر في init_db) | |
| `coach_tips` | id, device_id, child_id, date, domain, text, source, lang, shown_at, tapped_at | نصيحة المرشد (مالكان: init_db وcoach_service — انحراف فهارس) | 🔒 |
| `child_challenges` (+`_v27`) | id, device_id, child_id, challenge_key, topic, domain, status, note, started/resolved_at | التحدّي الحالي (فريد للنشط فقط منذ v27) | 🔒 |
| `daily_login_streaks` | device_id, child_id, date | سلسلة الدخول | |
| `child_daily_routines`, `routine_events` | routine_date · event_type, started/ended_at, feed_type, amount_ml, side, diaper_type, notes | «حِساب اليوم» | 🔒 |
| `habits_value_events`, `habit_templates` | child_id, category, habit_name, status, submitted_by, device_timestamp · custom_name, is_active | «ميزان العادات» | 🔒 |

### سطح الطفل
| الجدول | الأعمدة | الغرض |
|---|---|---|
| `child_screen_sessions` | surface, local_date, tz_offset_minutes, started_at, last_heartbeat_at, ended_at, ended_reason, counted_seconds | فوترة وقت الشاشة بالنبض |
| `child_missions` | mission_key, local_date, status, assigned/claimed/confirmed_at, parent_note, source (`NULL`=بنك، `prayer_journey`) | المهمة اليومية + مهام الصلاة |
| `child_licences`, `child_scenario_answers` | level_key, status, granted_at, talked_at, next_review_date · scenario_key, choice_key, outcome, attempt, parent_alerted_at | رخصة الإنترنت (سجل إجابات لا يُعاد كتابته) |
| `family_agreements`, `agreement_clauses` | version, status, signed_by_parent_at, signed_by_child_at, next_review_date · applies_to, clause_key, text_ar, is_custom, acknowledged_at | الاتفاقية الأسرية |
| `child_web_claims` | code_hash, device_id, child_id, ttl_seconds, expires_at, used_at | رموز QR (120 ثانية، مرة واحدة) |

### الذاكرة والمرافقة
| الجدول | الأعمدة | الغرض | حساس |
|---|---|---|---|
| `child_facts` | child_id, category, fact, source, confidence, status, lang, times_seen | حقائق عن الطفل | 🔒🔒 |
| `child_memory_settings` | device_id, enabled, generation, tz_offset_minutes | مفتاح الذاكرة | |
| `followups` | strategy, topic, due_at, status, outcome, note, source, pushed_at, answered_at | «جرّبت النصيحة؟» | 🔒 |
| `weekly_plans`, `weekly_plan_marks` | iso_week, lang, plan_json, personal · item_id, marked_on | خطة الأسبوع | |

### برامج الأسرة
| الجدول | الأعمدة |
|---|---|
| `program_settings`, `program_children` | tz_offset_minutes, lang, ramadan_year/shift/days · reached_puberty |
| `ramadan_fasting`, `ramadan_marks` | hijri_year, step_key · day, mark, value |
| `prayer_journeys` | track, stage, status, started_on, stage_started_on, ended_on |
| `milestone_alerts` | alert_key, milestone_key, status, claimed_at, sent_at |

### النمو والدعم
| الجدول | الأعمدة | الغرض |
|---|---|---|
| `referral_codes`, `referrals` | device_id, code · referrer_device, referred_device, code, via(`code`/`auto`) | الدعوات + الحملات (`campaign#CODE`) |
| `referral_clicks`, `referral_click_days` | ip, user_agent, code, clicked_at (7 أيام) · day, code, clicks | نقرات خام ثم طيّ يومي 🔒(IP) |
| `donations` | token_hash, order_hash, product_id, amount_micros, currency, usd_cents, purchase_type, consumed, voided | دفتر «ادعم المربّي» (إعادة بناء مدمّرة إن اختلف الشكل) |
| `user_backups` | device_id, google_id, salt, nonce, payload, updated_at | نسخ ZK مشفّرة ⚠️ لا عميل |
| `story_cache` | theme, age_group, gender, hero_name, story, served_count | قصص مولّدة مسبقًا (أبطال قانونيون) |
| `story_events` | device_id, name, story_id, lang, variant, narration_on, reduce_motion, page_index, rating | تجربة «صورة حيّة» |
| `schema_version` | version | ختم إصدار |

## 3) `sessions.db` — تيليمتري وكاشات

| الجدول | الأعمدة | المالك | مدة الاحتفاظ |
|---|---|---|---|
| `llm_calls` | ts, provider, model, latency_ms, prompt/completion_tokens, streamed, ok, tier, route_reason, usage_estimated | `ai_gateway` (مشغّل `llm_telemetry` 0001+0002) | 90 يومًا |
| `sessions` | 11 عمودًا (INSERT موضعي) | `session_logger` (`sessions` 0001) | 90 |
| `tafsir_cache`, `bahouth_cache` | cache_key فريد + lookup | الخدمتان (ترحيل أساس) | `TAFSIR_CACHE_TTL_DAYS`, `BAHOUTH_CACHE_TTL_DAYS` |
| `query_rewrites` | question_hash, … , redacted | `query_rewriter` | 90 |
| `answer_cache` | qhash, question_norm, age_group, domain, severity, answer, embedding, hit_count, redacted, kb_revision | `answer_cache` | 45 يومًا 🔒 |
| `retrieval_log` | ts, question, final_ids, redacted | `retrieval` | 90 🔒 |
| `blocked_fiqh_log` | question, rule_id, created_at, redacted | `fiqh_guard` | 90 🔒 |
| `fiqh_intent_shadow` | baseline_blocked, proposed_blocked, intent, prompt_revision | `fiqh_intent` | غير موجود في الإنتاج |
| `llm_call_reservations` | call_id, reservation_id | `cloud_budget.record_call_reservations` (يُنشأ كسولًا مع أول حجز) | غائب في الإنتاج بحسب جرد 2026-10-08؛ لا يُنشأ إلا حين يحمل نداء حجوزات دفتر (⇒ `CLOUD_BUDGET_ENFORCE` مفعّل). باقي جداول الدفتر في §3.1 |

### 3.1) جداول دفتر الميزانية السحابية (`services/cloud_budget.py` → `_create_schema`)

كلها في `ops/sessions.db`، تُنشأ كسولًا، ولها 3 triggers لكل جدول مراقَب (INSERT/UPDATE/DELETE ⇒ 24 trigger) تُحدّث صف `cloud_budget_witness`؛ المرساة على القرص تعكس (التسلسل، المجاميع، بصمة المخطط) عند كل commit فيُكشف استرجاع لقطة قديمة أو حذف/تعديل صف أو إسقاط trigger. أعمدة فقط:

| الجدول | الأعمدة | الدور |
|---|---|---|
| `cloud_budget_months` | wallet, month, opening_tokens, blocked (PK wallet+month) | رصيد افتتاح الشهر وعلم الحجب لكل محفظة |
| `cloud_budget_attempts` | id, wallet, month, bound, charged_tokens, settled | حجز لكل محاولة سلكية مدفوعة: الحدّ الأعلى ثم المسوّى |
| `cloud_budget_carry` | wallet, month, attempt_id, charged_tokens | ما يُرحَّل من محاولات غير مسوّاة إلى الشهر التالي |
| `cloud_budget_activation` | wallet, month, receipt | إيصال cutover الصريح من المشغّل (`bootstrap`) |
| `cloud_budget_identity` | id (=1), db_identity | هوية ملف قاعدة البيانات (يكشف استبدال الملف أثناء المحاسبة) |
| `cloud_budget_attempts_archive` | id, wallet, month, bound, charged_tokens, settled, archived_in | محاولات مسوّاة مؤرشفة بعد الشهر |
| `cloud_budget_attempt_meta` | attempt_id, reserved_at, unknown_charge | وقت الحجز وشحنة غير معلومة (لتسوية اليتامى) |
| `cloud_budget_audit` | id, ts, action, attempt_id, wallet, month, old_charge, new_charge, policy, evidence | سجل تدقيق لكل تسوية يدوية (`--settle-orphans`) |
| `cloud_budget_witness` | id (=1), seq، + أعمدة مجاميع (attempts_n/charged/settled، carry_*، months_*، activation_n، identity_n، archive_*، meta_n، audit_n) | شاهد الاستمرارية الذي تُحدّثه الـtriggers |
| `llm_call_reservations` | call_id, reservation_id (PK مزدوج) | ربط صف `llm_calls` بالحجوزات؛ خارج الدفتر المراقَب عمدًا؛ يُنشأ بـ`record_call_reservations` |

### 3.2) جداول مرحلية مؤقتة داخل الترحيلات (`init_db.py`) — ليست جداول دائمة

| الجدول | أين | ماذا |
|---|---|---|
| `lesson_progress_new` | ترحيل مدمّر لـ`lesson_progress` (≈ سطر 785–864) | يُبنى بالمخطط الجديد ← يُنسخ إليه ← `DROP lesson_progress` ← `RENAME` إلى `lesson_progress`. يسبق ذلك `DROP TABLE IF EXISTS lesson_progress_new` لأن بقاءه بعد انقطاع جعل كل إعادة محاولة تفشل بـ«already exists» |
| `child_challenges_v27` | ترحيل v27 لـ`child_challenges` (≈ سطر 1053–1075) | نفس النمط داخل `BEGIN IMMEDIATE`؛ ينتهي بـ`RENAME` إلى `child_challenges` + إعادة فهرس `ix_child_challenges_device_child` (فريد للنشط فقط). **لا يبقى جدول بهذا الاسم بعد النجاح** |

⚠️ **فخ احتفاظ:** إن غاب عمود `redacted` من أحد الجداول الأربعة (`query_rewrites`, `answer_cache`, `blocked_fiqh_log`, `retrieval_log`) فإن `retention._purge(drop_unmarked=True)` **يحذف كل صفوفه** ثم يضيف العمود.

## 4) ملفات ومجلدات يقرؤها/يكتبها البرنامج

| المسار | يقرأ/يكتب | ما هو |
|---|---|---|
| `knowledge_base/units/*.json` | قراءة | وحدات المعرفة (1060 عربي + 360 `__en`)؛ شكلها في `knowledge_base/schema/knowledge_unit.schema.json` |
| `knowledge_base/units_index.json` | كتابة بـ`build_vector_db.py` | فهرس الوحدات بحسب المجال |
| `knowledge_base/chroma_db/` (volume `tg_chroma`) | قراءة/كتابة | فهرس Chroma الحي |
| `knowledge_base/chroma_seed/` | قراءة عند الإقلاع | فهرس مخبوز في الصورة، يُنسخ للـvolume إن اختلفت البصمة |
| `knowledge_base/curriculum/{paths,lessons,daily_tips}/*.json` + `i18n/en` | قراءة | المنهج (43/205/220) + ترجمة |
| `knowledge_base/curriculum/{agreements,license,missions,programs,weekly_plan}/` | قراءة | بنوك الاتفاقية/المواقف/المهام/البرامج/خطط الأسبوع |
| `backend/guardrails/*.yaml` | قراءة | سياسات الحواجز + بوابة سطح الطفل |
| `docs/lesson_index.json` | قراءة (وتحديث بسكربتات) | فهرس 179 درسًا بوسائطها (بودكاست/فيديو/إنفوجراف/تقرير/جدول/بطاقات/اختبارات) |
| `docs/*.mp3`, `docs/path_videos/`, `docs/lesson_videos/` | قراءة (bind read-only) | ميديا الدروس (~2GB) **ليست في git** — rsync إلى `/root/tutor-guardian/docs` |
| `docs/stories/` (png/mp4) | قراءة عبر `/docs` | صور/فيديو القصص (متعقَّبة في git؛ 302 ملفًا) |
| `docs/lesson_assets/` | قراءة عبر `/program/asset-content` | بطاقات/اختبارات/تقارير/جداول JSON/CSV/MD |
| `backend/app/data/quran.json` | قراءة | فهرس كلمات القرآن للتفسير |
| `backend/secrets/firebase-adminsdk.json` | قراءة (bind ro) | مفتاح Firebase Admin — **ملف سرّ خارج git**؛ يُقرأ أيضًا `FIREBASE_CREDENTIALS` (JSON خام) |
| `backend/secrets/play_service_account.json` (افتراضي `PLAY_SERVICE_ACCOUNT`) | قراءة | حساب خدمة Play لتحقق المشتريات (مقيَّد) |
| `/root/tg-backups/<تاريخ>/` | كتابة | نسخ SQLite يومية (14 يومًا) |
| `/var/log/tg-*.log` | كتابة | لوجات الكرون على الـVPS |
| `/root/tutor-guardian/.env` | قراءة | بيئة الإنتاج (600؛ خارج git) |
| `ops/data/anbiya/`, `ops/data/sira/` | كتابة بـ`anbiya_sources.py`/`sira_sources.py`، قراءة بالحارسين | لقطات مصادر قصص الأنبياء (20) والسيرة (8) — أساس حارسي pre-commit/CI |
| `ops/data/*` | قراءة/كتابة بالأدوات | حالات الترجمة/البودكاست، أسئلة مجمّعة، فهرس الأحاديث `hadith_index.json.gz` (1.2MB)، `campaign_codes.md`, `campaign_spend.csv`، قوائم الحجر والمراجعة |
| `ops/tools/autoposter_state.json` | كتابة | حالة النشر الاجتماعي (غير متعقَّب) |
| `source_to_lesson.json`, `artifact_groups*.json`, `remaining_lessons_queue.json` | قراءة/كتابة بالسكربتات | خرائط خط الوسائط |
| `scratch/path_video_*.json` | كتابة | مهام/إخفاقات فيديو المسارات |

## 5) تخزين الجهاز (Flutter)

| المخزن | المفاتيح (أمثلة) | ما فيه |
|---|---|---|
| **flutter_secure_storage** | `tg_device_id` (+`tg_device_id_backup`, `.claim`) · `tg_parent_auth_token` · `tg_child_session_token` · `tg_child_mode_pin_hash` · `tg_child_mode_active` · `tg_deletion_token` | هوية الجهاز وتوكنات الجلسة وPIN (مجزّأ) |
| **SharedPreferences** | `tg.ui_language` · `tg.theme_mode` · `tg.onboarding.completed` · `tg.active_child_*` · `tg.favorites.v1` · `tg.reflections.v1` · `tg.journey.v1` · `tg.memorization.v1` · `tg.tasbeeh.v1` · `tg.chat_snapshot` · `tg.story_motion_mode` · `cached_minimum_build_number` · `tg.notifications.asked_after_first_lesson` · `tg.last_seen_version` · `tg.whats_new.last_seen_build` · `tg.horizon.*` · `noor.full_moon.v1` · `prideInvite.lastActedStreak` · `tg.adhkar_*`/`tg.wird_*` · `tg.stories.finished` (رف الحكايات) · `tg.update.dismissed_build` (بطاقة التحديث) · `tg_device_restore_key` («<deviceId> tgr_…» — يدخل نسخ أندرويد الاحتياطية عمدًا لاستعادة العائلة بعد إعادة التثبيت) | تفضيلات وتقدّم محلي |
| **ملفات** | سرد صوت الأب (`narration_store`) · ملاحظة صوتية قيد الإرسال · صورة الاتفاقية قيد المشاركة | `core/local_only_files.dart`: لا تدخل النسخ الاحتياطي لأندرويد |
| **كاش المنهج** | `curriculum_cache.dart` | آخر منهج سليم للعمل دون شبكة |
| **Firebase** | Analytics / Crashlytics | أحداث بأسماء شاشات ثابتة (`Screens.*`) |

## 6) مجموعات المحتوى (قياس)

| المحتوى | العدد | القياس |
|---|---:|---|
| وحدات معرفة عربية / إنجليزية | 1060 / 360 | `ls knowledge_base/units` (`*__en.json` = إنجليزي) |
| المجالات في الوحدات العربية | islamic_parenting 380 · medical 297 · cyber 261 · development 94 · aqeedah 16 · app_help 12 | قراءة حقل `domain` |
| المسارات / الدروس / النصائح اليومية | 43 / 205 (+45 `.md`) / 220 | `git ls-files knowledge_base/curriculum/…` |
| دروس في `lesson_index.json` | 179 | `lessons` في الفهرس |
| قصص التطبيق | 47 = 19 حكاية + 20 «قصص الأنبياء من القرآن» (`anbiya_quran`) + 8 «من السيرة النبوية» (`sira_sahih`)؛ الـ28 الجديدة نسختا young/older لـ14 قصة | `mobile/assets/data/stories.json` (حقل `series`) |
| مفاتيح الترجمة | 1865 عربي = 1865 إنجليزي | `.arb` |
| ملفات اختبار الباكند (`test_*.py`) | 189 ملف / 2511 دالة اختبار | `git grep "def test_"` |
| ملفات اختبار الموبايل | 153 ملف / 1645 حالة | `git grep "testWidgets\|test("` |
