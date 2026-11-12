# 03 — الواجهات ونقاط الدخول

> كل نقطة دخول للبرنامج: مسارات HTTP، بوت/ويب-هوك، كرون/مؤقّتات، سكربتات/CLI، سير CI، خطافات git، وشاشات/روابط التطبيق.
> جدول المسارات مولَّد بتحليل AST لـ`backend/app/routers/*.py` (ليس بالتخمين)، وعمود «المصادقة» مشتق من منطق `middleware/auth.py::_is_protected` الفعلي.

## 1) ملخص قياسي

| البند | العدد | كيف قيس |
|---|---:|---|
| مسارات الـAPI المعرَّفة في routers | 167 | AST على `@router.<verb>` في 30 ملف router (+4 منذ `2652382`: `program/mawaqif`، `mission/today` و`…/done`، `/print/ramadan`) |
| مسار إضافي في `main.py` | 1 | `POST /api/admin/send-push` |
| روتر مركَّب في `main.py` | 31 استدعاء `include_router` (30 وحدة؛ privacy مرتين) | قراءة `main.py` |
| تركيبات static | 5 | `/docs` `/ui` `/assets` `/child-mode/web` `/.well-known` |
| مسارات بمصادقة جهاز (Bearer) | 99 | |
| مسارات الطفل (Child-Bearer) | 15 | |
| مسارات عامة (بينها 7 بحراسة سرّ/مفتاح داخل المعالج) | 52 | |
| ناعم (جهاز اختياري) | 1 | `/api/program/story` |
| مسارات بتبعية إثبات الجهاز (FCM) | 15 | `dependencies=[Depends(require_device_proof*)]` |

## 2) مسارات HTTP

**المصادقة:** `عام` بلا توكن · `جهاز` = `Authorization: Bearer <token>` من `POST /api/chat/sessions` · `طفل` = `Child-Bearer` (توكن HMAC مُوقَّع بـ`CHILD_MODE_SECRET`، بلا device_id) · `ناعم` = يربط الهوية إن وُجد التوكن ولا يرفض (STORY_AUTH_ENFORCE يجعله إلزاميًا) · `إثبات جهاز` = تبعية إضافية (تحدّي FCM) · `X-Admin-Key` = `FEEDBACK_ADMIN_KEY` · `X-Ops-Token` = `OPS_METRICS_TOKEN`.
البادئة `/api` تأتي من `main.py`؛ الأعمدة هنا تعرض المسار الكامل. حدود المعدّل في §3.


### `assistant.py` — assistant — المساعد (قلب المنتج)

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| POST | `/api/assistant/draft` | جهاز | `draft_reply` |  |
| POST | `/api/assistant/query` | جهاز | `query_reply` | Alias for /draft — used by external clients. |
| POST | `/api/assistant/stream` | جهاز | `stream_reply` | SSE streaming variant of /draft (mobile-ready). |

### `chat.py` — chat — الجلسات

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| POST | `/api/chat/sessions` | عام | `create_session` | Create a new session and return an auth token. |
| GET | `/api/chat/sessions` | جهاز | `list_sessions` | List the authenticated device's past conversations (newest first), |
| GET | `/api/chat/sessions/{session_id}` | جهاز | `get_session` | Get full session with message history. Requires auth token. |
| POST | `/api/chat/sessions/{session_id}/stop` | جهاز | `stop_answer` | Stop the answer this session is generating — the parent pressed Stop. |
| POST | `/api/chat/restore-key` | جهاز (يُرفض 403 `restore_key_unavailable` لجلسة سُكّت عارية) | `issue_restore_key` | مفتاح استعادة هذا الجهاز (`tgr_…`)، يُعرض مرة؛ الطلب مجددًا يستبدله — `services/restore_keys.py` |

### `child_memory.py` — child_memory — ذاكرة الطفل والمتابعات وخطة الأسبوع

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| GET | `/api/children/memory/settings` | جهاز | `get_memory_settings` | Is child memory on for this device? (no proof needed) |
| PUT | `/api/children/memory/settings` | جهاز | `put_memory_settings` | Turn child memory on or off for this device |
| GET | `/api/children/followups/due` | جهاز + إثبات جهاز | `followups_due` | Follow-ups whose time has come, across all children |
| GET | `/api/children/followups/{followup_id}` | جهاز + إثبات جهاز | `get_followup` | One follow-up — what the /followup/{id} deep link opens |
| POST | `/api/children/followups/{followup_id}/answer` | جهاز + إثبات جهاز | `answer_followup` | Did the advice work? Records it as an outcome fact |
| POST | `/api/children/followups/{followup_id}/dismiss` | جهاز + إثبات جهاز | `dismiss_followup` | Stop asking about this follow-up |
| GET | `/api/children/{child_id}/followups` | جهاز + إثبات جهاز | `child_followups` | A child's follow-ups (pending by default) |
| POST | `/api/children/{child_id}/followups` | جهاز + إثبات جهاز | `open_promise` | A promise becomes a follow-up: `source` = `lesson` (default) or `mawqif` («موقف بقرار») |
| GET | `/api/children/{child_id}/memory` | جهاز + إثبات جهاز | `list_memory` | What the assistant remembers about this child |
| POST | `/api/children/{child_id}/memory` | جهاز + إثبات جهاز | `add_memory` | Add a fact the parent typed |
| PATCH | `/api/children/{child_id}/memory/{fact_id}` | جهاز + إثبات جهاز | `patch_memory` | Edit, confirm (active) or reject a fact |
| DELETE | `/api/children/{child_id}/memory/{fact_id}` | جهاز + إثبات جهاز | `delete_memory_fact` | Forget one fact |
| DELETE | `/api/children/{child_id}/memory` | جهاز + إثبات جهاز | `delete_child_memory` | Forget everything about this child |
| GET | `/api/children/{child_id}/weekly-plan` | جهاز | `get_weekly_plan` | This week's plan for the child (built once per ISO week) |
| PUT | `/api/children/{child_id}/weekly-plan/marks` | جهاز | `put_weekly_plan_mark` | Tick one step of the week's plan (idempotent) |
| DELETE | `/api/children/{child_id}/weekly-plan/marks` | جهاز | `delete_weekly_plan_mark` | Un-tick one step of the week's plan (idempotent) |

### `child_mode.py` — child_mode — وضع الطفل (Child-Bearer)

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| POST | `/api/value-tracking/child-web-claims` | جهاز | `create_child_web_claim` | Parent endpoint: create a one-time QR claim code for web teen access. |
| POST | `/api/value-tracking/child-sessions` | جهاز | `create_child_session` | Parent endpoint: issue a short-lived child-mode token for a child. |
| POST | `/api/value-tracking/child-mode/heartbeat` | طفل | `child_heartbeat` | Bill the time since the last beat and report what is left. |
| POST | `/api/value-tracking/child-mode/session-end` | طفل | `child_session_end` | Close a session from the child's side, after the exit ritual. |
| GET | `/api/value-tracking/child-mode/today` | طفل | `child_get_today` | Child endpoint: fetch today's merged habit list (read-only). |
| POST | `/api/value-tracking/child-mode/events` | طفل | `child_record_event` | Child endpoint: submit today's status for one habit (submit-only). |
| GET | `/api/value-tracking/child-mode/agreement` | طفل | `child_read_agreement` | What the child is being asked to agree to. |
| POST | `/api/value-tracking/child-mode/agreement/acknowledge` | طفل | `child_acknowledge_clause` | The child says they understood one clause. One at a time, on purpose. |
| POST | `/api/value-tracking/child-mode/agreement/sign` | طفل | `child_sign_agreement` |  |
| GET | `/api/value-tracking/child-mode/mission/today` | طفل | `child_mission_today` | One card. The same card all day, however often it is opened. |
| POST | `/api/value-tracking/child-mode/mission/claim` | طفل | `child_mission_claim` | «خلّصتها» — recorded and done. The child does not wait for a parent. |
| GET | `/api/value-tracking/child-mode/license/today` | طفل | `child_license_today` | The next situation to think about, or None when this level is done. |
| POST | `/api/value-tracking/child-mode/license/answer` | طفل | `child_license_answer` | Record the child's choice, and alert the parent when the situation |

### `child_mode_web.py` — child_mode_web — تطبيق QR للمراهقين

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| POST | `/api/child-web/claim-session` | عام (كود QR) | `claim_session` | Redeem a one-time QR claim code for a long-lived web child token. |
| GET | `/api/child-web/me` | طفل | `web_child_profile` | Return minimal profile info for the currently authenticated web child. |
| POST | `/api/child-web/refresh` | طفل | `refresh_web_session` | Refresh an existing web child token using its stored child_id/device_id. |

### `children.py` — children — الأطفال والتقدّم والاتفاقية والرخصة

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| POST | `/api/children` | جهاز | `create_child` | Create a child profile for the current device |
| GET | `/api/children/{child_id}/progress` | جهاز | `get_child_progress` | Fetch lesson_progress for a child (must belong to this device) |
| GET | `/api/children/{child_id}/challenge` | جهاز | `get_challenge` | Get the child's active current-challenge (or null) |
| GET | `/api/children/{child_id}/screen-usage` | جهاز | `get_screen_usage` | What the child's screen and listening time looked like on a day |
| PUT | `/api/children/{child_id}/challenge` | جهاز | `set_challenge` | Set/replace the child's current challenge |
| DELETE | `/api/children/{child_id}/challenge` | جهاز | `clear_challenge` | Resolve (clear) the child's current challenge |
| GET | `/api/children` | جهاز | `list_children` | List the children profiles owned by the current device |
| PATCH | `/api/children/{child_id}` | جهاز | `update_child` | Update name / age_group / gender / avatar_emoji of a child |
| DELETE | `/api/children/{child_id}/progress` | جهاز + إثبات جهاز عند التسجيل | `reset_child_progress` | Reset all lesson_progress rows for the given child |
| DELETE | `/api/children/{child_id}` | جهاز + إثبات جهاز عند التسجيل | `delete_child` | Delete a child profile |
| GET | `/api/children/{child_id}/agreement/clauses/suggested` | جهاز | `suggested_agreement_clauses` | Suggested clause pairs for the child's age band |
| GET | `/api/children/{child_id}/agreement` | جهاز | `get_agreement` | The child's agreement |
| POST | `/api/children/{child_id}/agreement` | جهاز | `put_agreement_draft` | Create or replace the draft |
| POST | `/api/children/{child_id}/agreement/sign` | جهاز | `sign_agreement_as_parent` | Parent signs the draft |
| GET | `/api/children/missions/pending` | جهاز | `pending_missions` | Every mission across every child that is waiting on the parent |
| POST | `/api/children/missions/confirm` | جهاز | `confirm_missions` | Settle several missions at once |
| GET | `/api/children/{child_id}/mission/today` | جهاز | `parent_mission_today` | Today's mission card for the parent — shows it without writing a row (no handover) |
| POST | `/api/children/{child_id}/mission/today/done` | جهاز | `parent_mission_done` | The parent marks today's mission done, with an optional kind word |
| GET | `/api/children/{child_id}/today` | جهاز | `child_day_summary` | The parent's one-screen view of a child's day |
| GET | `/api/children/{child_id}/license` | جهاز | `child_license_summary` | Where a child is on the internet licence |
| POST | `/api/children/{child_id}/license/talked` | جهاز | `child_license_talked` | Record that the parent and child talked about this level |
| POST | `/api/children/{child_id}/license/grant` | جهاز | `child_license_grant` | Grant a level |

### `daily_routine.py` — daily_routine — «حِساب اليوم»

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| GET | `/api/daily-routine/today` | جهاز | `get_today` | Fetch today's routine events for a child. |
| POST | `/api/daily-routine/events` | جهاز | `create_event` | Record a new routine event for a child today. |
| PATCH | `/api/daily-routine/events/{event_id}` | جهاز | `update_event` | Partially update an existing event (must belong to the caller's device/child). |
| DELETE | `/api/daily-routine/events/{event_id}` | جهاز | `delete_event` | Delete an event. |
| GET | `/api/daily-routine/summary` | جهاز | `get_summary` | Aggregated routine summary for the last N days. |

### `device_proof.py` — device_proof — إثبات الجهاز

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| GET | `/api/device-proof` | جهاز | `proof_status` | Is this session proven to hold its phone? |
| POST | `/api/device-proof/start` | جهاز | `proof_start` | Send a one-time code to this device's current push token |
| POST | `/api/device-proof/complete` | جهاز | `proof_complete` | Post the code back; this session is then proven |

### `family.py` — family — قناديل الأسبوع

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| GET | `/api/family/week` | جهاز | `family_week` | This week's lanterns: the family's parenting acts |

### `family_programs.py` — family_programs — رمضان/الصلاة/المراحل

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| GET | `/api/programs` | جهاز | `programs_overview` | Which family programs apply to each child today |
| GET | `/api/children/{child_id}/ramadan/today` | جهاز | `ramadan_today` | The Ramadan program for this child on the family's date |
| GET | `/api/children/{child_id}/ramadan/days/{day}` | جهاز | `ramadan_day` | Any day of the month for this child: a preview, or a past day to tick |
| GET | `/api/children/{child_id}/ramadan/fasting` | جهاز | `ramadan_fasting` | The child's fasting ladder, with the safety guidance |
| PUT | `/api/children/{child_id}/ramadan/fasting` | جهاز | `ramadan_set_fasting` | Set the child's fasting step and/or mark puberty |
| POST | `/api/children/{child_id}/ramadan/fasting/practice` | جهاز | `ramadan_practice` | The child practised their fasting step today (or on a past day) |
| POST | `/api/programs/ramadan/marks` | جهاز | `ramadan_mark` | Tick or untick a family «تمّ» mark |
| PUT | `/api/programs/ramadan/settings` | جهاز | `ramadan_settings` | The family's own moon sighting for this season |
| GET | `/api/programs/ramadan/recap` | جهاز | `ramadan_recap` | «رمضان عائلتنا» — the family's card |
| GET | `/api/children/{child_id}/prayer-journey` | جهاز | `prayer_view` | The Prayer Journey for this child: track, stage, tasks |
| POST | `/api/children/{child_id}/prayer-journey/enrol` | جهاز | `prayer_enrol` | Start (or restart) the child on a track |
| PUT | `/api/children/{child_id}/prayer-journey/stage` | جهاز | `prayer_stage` | Move to the next stage, or back to an earlier one |
| POST | `/api/children/{child_id}/prayer-journey/graduate` | جهاز | `prayer_graduate` | Graduate from the Journey to «صلاتي مسؤوليتي» |
| DELETE | `/api/children/{child_id}/prayer-journey` | جهاز | `prayer_end` | Stop the journey |
| GET | `/api/children/{child_id}/milestones` | جهاز | `milestones_list` | Due, upcoming and library milestone cards for this child |
| GET | `/api/children/{child_id}/milestones/{key}` | جهاز | `milestone_one` | One milestone card (the push's deep link) |
| GET | `/api/value-tracking/child-mode/prayer/today` | طفل | `child_prayer_today` | Child mode: today's prayer tasks |
| POST | `/api/value-tracking/child-mode/prayer/claim` | طفل | `child_prayer_claim` | Child mode: «صلّيتها» — record a prayer task |

### `feedback.py` — feedback — الملاحظات والتقييم وبوت تلجرام

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| POST | `/api/feedback/app` | عام | `submit_app_feedback` | General in-app feedback (text and/or a voice note) — reaches the maintainer. |
| GET | `/api/feedback/app` | عام + مفتاح admin | `list_app_feedback` | Maintainer-only: list submitted feedback. Voice notes (has_audio=true) are |
| GET | `/api/feedback/digest` | عام + مفتاح admin | `feedback_digest` | Maintainer-only: ملخّص قرارات ذكي ومرتّب بالأولوية لكل الفيدباك. |
| GET | `/api/feedback/app/{feedback_id}/audio` | عام + مفتاح admin | `get_app_feedback_audio` | Maintainer-only: download a feedback voice note as audio/mp4. |
| POST | `/api/feedback/app/{feedback_id}/reply` | عام + مفتاح admin | `admin_reply` | Maintainer-only: answer a parent without going through Telegram. |
| POST | `/api/feedback/telegram/webhook` | عام + سرّ تلجرام | `telegram_webhook` | Receive a Telegram reply and route it back to the user who wrote in. |
| GET | `/api/feedback/replies` | جهاز | `list_my_replies` | Replies waiting for this device. |
| POST | `/api/feedback/replies/{reply_id}/read` | جهاز | `mark_reply_read` | Mark a reply as seen. Scoped to the caller's own device. |
| POST | `/api/feedback` | جهاز | `submit_feedback` | Record 👍/👎 feedback. |

### `habit_templates.py` — habit_templates

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| POST | `/api/habit-templates` | جهاز | `create_template` | Add a parent-defined habit template for a child. |
| GET | `/api/habit-templates` | جهاز | `list_templates` | List custom habit templates for a child. |
| PATCH | `/api/habit-templates/{template_id}` | جهاز | `update_template` | Activate or archive (soft-delete) a custom habit template. |

### `health.py` — health — الصحة وإعداد التطبيق

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| GET | `/health` | عام | `health_check` | Deep health check — verifies SQLite and ChromaDB readiness. |
| GET | `/api/health` | عام | `api_health_check` |  |
| GET | `/api/app-config` | عام | `get_app_config` | `minimum_build_number` (بوابة إجبارية) + `latest_build_number` (بطاقة تحديث اختيارية، `LATEST_BUILD_NUMBER`، 0 = لا شيء) + store_url + STORY_MOTION_MODE |

### `identity.py` — identity — Google Sign-In

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| POST | `/api/identity/link-google` | جهاز | `link_google_identity` |  |
| GET | `/api/identity/me` | جهاز | `get_identity` |  |

### `insights.py` — insights

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| GET | `/api/insights/parenting` | جهاز | `get_parenting_insights` |  |

### `methodology.py` — methodology — صفحة عامة

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| GET | `/methodology` | عام | `methodology_page` | Our methodology and sources — public page for parents and reviewers. (مخفي من OpenAPI) |

### `print_pack.py` — print — أوراق الطباعة (خارج `/api`، خارج المخطط)

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| GET | `/print/ramadan` | عام | `ramadan_sheets` | «رمضان العائلة» 12 ورقة A4 للطباعة (`?lang=en`)، تُولَّد من البرنامج نفسه؛ رمز QR بكود حملة `PR01`/`PR02` |

### `privacy.py` — privacy — الخصوصية والحذف

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| DELETE | `/api/privacy/memory` | جهاز + إثبات جهاز | `delete_my_memory` | Forget everything about my children |
| GET | `/privacy-policy` | عام | `get_privacy_policy` | Serve the privacy policy as plain text/markdown. (مخفي من OpenAPI) |
| GET | `/delete-account` | عام | `delete_account_page` | How to delete an account — in the app, or by email without it. (مخفي من OpenAPI) |
| DELETE | `/api/privacy/account` | جهاز + إثبات جهاز (لا رجعة) | `delete_my_account` | Delete my account and all its data |

### `program.py` — program — المنهج والقصص والنصائح

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| GET | `/api/program/mawaqif` | عام | `get_mawaqif` | «موقف بقرار»: مواقف الفئة العمرية (`age_group`، `lang`) — `{age_group, items}`؛ عمر بلا مواقف = قائمة فارغة، عمر غير معروف = 422 |
| GET | `/api/program/paths` | عام | `list_paths` | قائمة المسارات المنشورة، قابلة للفلترة. |
| GET | `/api/program/paths/{path_id}` | عام | `get_path_detail` | تفاصيل مسار واحد. لو include=lessons، يرجع الدروس بالترتيب. |
| GET | `/api/program/next-lesson` | عام | `get_next_lesson` | The single lesson to put in front of this parent right now. |
| GET | `/api/program/lessons/{lesson_id}` | عام | `get_lesson_detail` | تفاصيل درس واحد. يرجع الـ unit_ids لكن لا يحمّل الـ units الكاملة — |
| GET | `/api/program/lesson-assets/{lesson_id}` | عام | `get_lesson_assets` | استرجاع أصول الدرس التفاعلية (البودكاست، الفلاش كاردز، الاختبارات، إلخ). |
| GET | `/api/program/asset-content/{asset_id}` | عام | `get_asset_content` | محتوى أصل تفاعلي (فلاش كاردز / اختبار) بالكامل — additive v1 endpoint. |
| GET | `/api/program/search` | عام | `search_curriculum` | بحث نصّي في الدروس والمسارات والنصائح — additive v1 endpoint. |
| GET | `/api/program/daily-tip` | عام | `get_daily_tip` | نصيحة يومية واحدة. الافتراضي: deterministic per-day selection من pool. |
| GET | `/api/program/coach-tip` | جهاز | `get_coach_tip` | نصيحة تربوية استباقية مخصّصة للطفل اليوم. |
| POST | `/api/program/coach-tip/{tip_id}/tap` | جهاز | `tap_coach_tip` | تسجيل تفاعل خفيف: الأب ضغط على النصيحة. |
| PATCH | `/api/program/lessons/{lesson_id}/progress` | جهاز | `patch_lesson_progress` | Upsert the (device_id, lesson_id) progress row. Idempotent. |
| GET | `/api/program/quiz` | عام | `get_quiz` | Return random quiz questions, optionally filtered by domain. |
| POST | `/api/program/story` | ناعم (جهاز اختياري) | `generate_story` | Generate a short, safe, value-teaching Arabic children's story |
| GET | `/api/program/story-themes` | عام | `story_themes` | The catalogue of story values (key → Arabic label) for the UI. |
| GET | `/api/program/monthly-report/{child_id}` | جهاز | `monthly_report` | Generate a monthly progress report for a child (auth-required). |

### `push.py` — push

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| POST | `/api/push/register` | جهاز | `register_push_token` |  |
| GET | `/api/push/token` | جهاز | `get_push_token` | For health/checks — returns whether we have a stored token. |

### `quranic_linguistics.py` — quranic_linguistics — بحوث (Bahouth MCP)

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| POST | `/api/quranic-linguistics/find-root` | عام | `post_find_root` | جذر كلمة مع تكرارها في القرآن (normalize تلقائي للتشكيل). |
| POST | `/api/quranic-linguistics/root-verses` | عام | `post_root_verses` | آيات جذر معين — pagination بالـoffset (50+43=103 لصبر ✓). |
| GET | `/api/quranic-linguistics/topics/{topic_id}/verses` | عام | `get_topic_verses` | آيات موضوع معين (topic_id رقمي — متحقق منه على السيرفر). |
| GET | `/api/quranic-linguistics/verses/{verse_key}/qiraat` | عام | `get_verse_qiraat` | قراءات آية — verse_key بصيغة «2-255» بشرطة. |
| GET | `/api/quranic-linguistics/verses/{verse_key}` | عام | `get_single_verse` | آية واحدة بالرسم العثماني — verse_key بصيغة «2-255» بشرطة. |

### `referral.py` — referral

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| GET | `/api/referral/me` | جهاز | `my_referral` | This device's code + how many installs it has driven. |
| POST | `/api/referral/claim` | جهاز | `claim_referral` | Record that this (new) device was referred by `body.code`. |

### `seo.py` — seo — صفحات SEO

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| GET | `/seo/{slug}` | عام | `seo_page` | SEO page for a specific pain-point question. (مخفي من OpenAPI) |
| GET | `/seo/` | عام | `seo_index` | Index of all SEO pages. (مخفي من OpenAPI) |

### `stats.py` — stats — إحصاء المجتمع ومراقبة OMAR

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| GET | `/api/stats/community` | عام | `community_stats` | Aggregate, non-PII social-proof counts for the Home surface. |
| GET | `/api/stats/ops-llm` | عام + X-Ops-Token | `ops_llm_metrics` | Aggregate LLM cost/latency metrics for external monitoring (OMAR). |

### `story_events.py` — story_events

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| POST | `/api/stories/events` | جهاز | `record_story_events` |  |

### `support.py` — support — ادعم المربّي

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| GET | `/api/support/transparency` | عام | `get_transparency` |  |
| POST | `/api/support/verify` | جهاز | `verify_purchase` |  |

### `sync.py` — sync — مزامنة Zero-Knowledge

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| POST | `/api/sync/upload` | جهاز | `upload_backup` | Upload an encrypted database payload. |
| GET | `/api/sync/download` | جهاز | `download_backup` | Download the latest encrypted database payload. |

### `tafsir.py` — tafsir — Tafsir MCP

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| GET | `/api/tafsir/{surah}/{ayah}` | عام | `get_tafsir` | جلب تفسير آية من مصدر أو أكثر. |
| GET | `/api/tafsir/{surah}/{ayah}/ayah-text` | عام | `get_ayah_text` | جلب نص آية قرآنية بالرسم العثماني فقط. |
| GET | `/api/tafsir/{surah}/{ayah}/nuzool` | عام | `get_nuzool_reason` | جلب سبب نزول آية. |
| GET | `/api/tafsir/sources` | عام | `get_sources` | فهرس مصادر التفسير المتاحة. |
| POST | `/api/tafsir/search` | عام | `search` | بحث نصي في آيات القرآن. |
| POST | `/api/tafsir/search-tafsir` | عام | `search_tafsir` | بحث LIKE داخل تفسير معين. |

### `value_tracking.py` — value_tracking — «ميزان العادات»

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| GET | `/api/value-tracking/today` | جهاز | `get_today` | Fetch today's habit events for a child, merged with default + custom templates. |
| POST | `/api/value-tracking/events` | جهاز | `create_event` | Record a new habit evaluation for a child today. |
| DELETE | `/api/value-tracking/events/{event_id}` | جهاز | `delete_event` | Delete a habit event. |
| GET | `/api/value-tracking/summary` | جهاز | `get_summary` | Aggregated habit summary for the last N days. |

### `web.py` — web — الصفحات العامة

| Method | المسار | المصادقة | المعالج | الغرض |
|---|---|---|---|---|
| GET | `/` | عام | `landing` | Share/install landing — where shared cards, referral and campaign links arrive. |
| GET | `/go` | عام | `landing` | Share/install landing — where shared cards, referral and campaign links arrive. |
| GET | `/ui/` | عام | `landing` | Share/install landing — where shared cards, referral and campaign links arrive. (مخفي من OpenAPI) |
| GET | `/ui/index.html` | عام | `landing` | Share/install landing — where shared cards, referral and campaign links arrive. (مخفي من OpenAPI) |
| GET | `/ui/cinematic.html` | عام | `landing` | Share/install landing — where shared cards, referral and campaign links arrive. (مخفي من OpenAPI) |
| GET | `/ui/cinematic.en.html` | عام | `landing` | Share/install landing — where shared cards, referral and campaign links arrive. (مخفي من OpenAPI) |
| GET | `/l/{lesson_id}` | عام | `lesson_page` |  |
| GET | `/p/{path_id}` | عام | `path_page` |  |
| GET | `/sitemap.xml` | عام | `sitemap` |  |
| GET | `/robots.txt` | عام | `robots` |  |

### `main.py` — مسار إداري وملحقات

| Method | المسار | المصادقة | الغرض |
|---|---|---|---|
| POST | `/api/admin/send-push` | `X-Admin-Key` = `TG_ADMIN_KEY` (يفشل مغلقًا 403 إن لم يُضبط) | إرسال إشعار يدوي لجهاز `{device_id,title,body,data?}` |

**تركيبات static (`app.mount`):**

| المسار | المصدر | ملاحظة |
|---|---|---|
| `/docs` | مجلد `docs/` كله | يخدم الميديا (بودكاست/فيديو/صور القصص) — الميديا نفسها ليست في git ✅ تُنقل rsync |
| `/ui` | `frontend/` | صفحات الهبوط الخام + `/ui/icons`, `/ui/assets` (لكن `/ui/` نفسه يُقدَّم من `web.py`) |
| `/assets` | `mobile/assets/` | شعار/أيقونات لصفحات الهبوط |
| `/child-mode/web` | `backend/static/child_mode/` | صفحة المراهق عبر QR |
| `/.well-known` | `.well-known/` | `assetlinks.json` لروابط تطبيق Android (verified App Links) |

ملاحظة: Swagger UI الافتراضي يبقى على `/docs` (مسار إطار العمل مُسجَّل قبل الـmount فيغلب)، أما الـmount فيخدم `/docs/<ملف>`. وقائمة العامّ في auth تذكر `/api/docs|/api/openapi.json|/api/redoc` وهي مسارات لا يعرّفها التطبيق فعليًا (بقايا).

## 3) المصادقة والحدود (ملخّص)

- **الجلسة:** `POST /api/chat/sessions` (عام) يُنشئ جلسة ويُصدر Bearer؛ الهوية تُثبَت بتوكن سابق أو بمفتاح الاستعادة (ترويسة `X-Device-Restore`)، ويُسجَّل `api_tokens.mint_kind` (new/proof/restore/bare؛ «العاري» يورَّث، ونافذة «سباق الميلاد» 120ث لا تُحسب عارية)؛ مع `SESSION_MINT_ENFORCE` يصبح الجهاز المعروف بلا إثبات **جهازًا جديدًا فارغًا** (بناء ≥117) أو 401 (أقدم). الجلسة العارية لا تحصل على مفتاح استعادة ولا تؤكّد ربط Google. التوكنات مُجزَّأة (hash) بانقضاء منزلق (schema v28).
- **حدود المعدّل** (`middleware/rate_limit.py`): نطاق `ai` (`/api/assistant`, `/api/program/story`, `/api/insights`) = `RATE_LIMIT_PER_MINUTE` (30) + حصة يومية `AI_DAILY_LIMIT` (20/هوية/يوم UTC)؛ النطاق العام = `RATE_LIMIT_GENERAL_PER_MINUTE` (120)؛ `feedback/app` = `RATE_LIMIT_FEEDBACK_PER_MINUTE` (5)؛ إنشاء الجلسة = `RATE_LIMIT_SESSION_PER_MINUTE` (30)؛ `support/verify` = `RATE_LIMIT_SUPPORT_VERIFY_PER_MINUTE` (5). الهوية: device ← hash التوكن ← IP.
- **ترتيب الـmiddleware (من الخارج للداخل):** ClientIP → RateLimit → Auth → CORS.
- **أبواب بيئية (flags) تغيّر سلوك مسارات:** `CHILD_SURFACE_ENABLED` (مفتاح قتل بوابة العمر/الميزانية)، `AGREEMENT_REQUIRED`، `COACH_TIP_ENABLED`، `DONATIONS_ENABLED`، `MILESTONES_MIN_BUILD`، `CHILD_MEMORY_MIN_BUILD`، `STORY_AUTH_ENFORCE`، `SESSION_MINT_ENFORCE`، `IDENTITY_CROSS_DEVICE`، `PROGRAMS_AS_OF_ENABLED`، `MINIMUM_BUILD_NUMBER`، `LATEST_BUILD_NUMBER`.

## 4) بوت/ويب-هوك تلجرام

| الكيان | أين | كيف يعمل |
|---|---|---|
| بوت الملاحظات (مخصّص) | `routers/feedback.py` + `ops/scripts/set_feedback_webhook.py` | ملاحظة من التطبيق → رسالة تلجرام (+صوت)؛ ردّ المسؤول على الرسالة من تلجرام → `POST /api/feedback/telegram/webhook` (سرّ `X-Telegram-Bot-Api-Secret-Token` + قائمة سماح chat_id + سقف حجم) → يُخزَّن في `feedback_replies` ويُدفع إشعار → يظهر أعلى شاشة الملاحظات (التطبيق يستطلع `GET /api/feedback/replies` عند كل فتح). يفشل مغلقًا بلا السرّ |
| تقارير تلجرام | `ops/scripts/{weekly_dashboard,weekly_funnel_report,weekly_kb_gap_report,campaign_report,launch_weekly_report}.py` | إرسال مجمّع إلى `TELEGRAM_CHAT_ID` عبر `TELEGRAM_BOT_TOKEN` |
| قناة المربّي | `ops/tools/social_media_autoposter.py` | نشر نصائح/إنفوجراف على قناة تلجرام + Buffer (اختبارات تمنع النشر عند الاستيراد/الجفاف) |
| تنبيه فشل النشر | `.github/workflows/deploy.yml` (job alert) | رسالة تلجرام حين يفشل أي job قبله |
| وكلاء PCC (خارج المستودع) | `publishing-center` على اللابتوب | `tutor_post` (12:00)، `tutor_reels` (11:00)، `tutor_podcasts` (كل ساعة :15)، `tutor_genvideos` (معطَّل 2026-07-15) — مرجعها `docs/OPS_RUNBOOK.md` §5.2 وpcc list |

لا يوجد بوت أوامر تفاعلي (commands/handlers) داخل هذا المستودع؛ كل تفاعل تلجرام هو إشعار أو webhook الردود.

## 5) الكرون والمؤقّتات

**VPS (crontab الـroot، UTC)** — المصدر: `docs/OPS_RUNBOOK.md` §5.1 (الحالة وقت 2026-07/08 — تحقق من crontab الحي):

| الوقت | الأمر | الغرض |
|---|---|---|
| `0 2 * * *` | `docker-cleanup.sh` | تنظيف صور Docker |
| `17 3 * * *` | certbot renew | تجديد الشهادات |
| `0 17 * * *` | `docker exec -w /app tg_backend python ops/scripts/cron_push_triggers.py` | إشعارات إعادة التفاعل (≤1/جهاز/يوم؛ first_lesson_activation → day_two → streak_at_risk → win_back، سقوف لكل غياب، لغة الأسرة) + طيّ نقرات الإحالة + `retention.run_housekeeping` |
| `30 2 * * *` | `pregen_stories.py --max 20` | توليد القصص مسبقًا |
| `0 3 * * *` | `warm_answer_cache.py` | تسخين كاش الإجابات |
| `30 3 * * *` | `ops/scripts/backup_user_data.sh` | نسخ احتياطي يومي إلى `/root/tg-backups` (14 يومًا) |
| أسبوعيًا 8:00 | `weekly_dashboard.py` | داشبورد أسبوعي |
| `0 6 * * 6` | `weekly_kb_gap_report.py` | فجوات المعرفة |
| `0 7 * * 6` | `weekly_funnel_report.py` | قمع التفعيل والاحتفاظ |
| systemd timer | `pcc-laptop-watchdog` | يراقب نبض اللابتوب (كوده في publishing-center) |

**داخل العملية (`main.py::_digest_loop`)** — كل `DIGEST_TICK_SECONDS` = 15 دقيقة، ينفّذ 4 وظائف تختار الأجهزة التي حانت ساعتها المحلية: `mission_digest.run_due_digests` (21:00 ملخص المهام)، `followup_push.run_due_followups` (19:00)، `device_alerts.run_due_alerts` (نهارًا، مرة/يوم)، `milestone_push.run_due_milestones` (20:00، يتطلب `MILESTONES_MIN_BUILD`). كل وظيفة تلتفّ بـtry/except كي لا تقتل الحلقة.

**GitHub:** `e2e-avd-cache.yml` يومي `23 4 * * *`؛ الباقي push/PR/dispatch (§7).

**اللابتوب/tg-home (توليد المحتوى، خارج الإنتاج):** `scripts/cron_gen_en_media.sh` (يومي)، `cron_gen_podcasts.sh`، `cron_gen_path_videos.sh`، `cron_regen_podcasts.sh`، `resume_infographics_cron.sh` — تعتمد جلسة NotebookLM (`scripts/lib/nblm_session.sh`) وحصصها (الصوت ~20/يوم، الإنفوجراف ~4–6/تشغيلة).

## 6) السكربتات وCLI

### 6.1 `ops/scripts/` — تعمل داخل الحاوية أو على الـVPS (مُركَّبة read-only)

| السكربت | يُستدعى بـ | الغرض |
|---|---|---|
| `ops/scripts/backup_user_data.sh` | كرون 03:30 | كرون 03:30 UTC: نسخ احتياطي يومي لكل قواعد SQLite بـbackup API + integrity_check + gzip (احتفاظ 14 يومًا) |
| `ops/scripts/broadcast_push.py` | يدوي | بثّ إشعار لكل جهاز له توكن FCM |
| `ops/scripts/campaign_report.py` | يدوي `--dry-run` | تقرير الحملات: أي قناة تأتي بأسر تبقى (نقرات/تثبيتات/إضافة طفل/نشاط D7-13) |
| `ops/scripts/cron_push_triggers.py` | كرون 17:00 (+`--dry-run`,`--force`,`--base-url`) | كرون 17:00 UTC داخل الحاوية: إشعارات إعادة التفاعل (حد 1/جهاز/يوم؛ أربعة محفّزات بسقوف لكل غياب) + طيّ نقرات الإحالة + privacy housekeeping |
| `ops/scripts/delete_account.py` | يدوي لطلب بريدي | تنفيذ طلب حذف وصل بالإيميل لمن بلا تطبيق |
| `ops/scripts/deploy_model.sh` | يدوي (قديم) | نشر نموذج Ollama المخصّص tg-tutor (قديم) |
| `ops/scripts/launch_weekly_report.py` | يدوي/تقرير الإطلاق | تقرير الإطلاق الأسبوعي: كل قرار تسويقي مقابل الاحتفاظ لكل كود |
| `ops/scripts/migrate_schema_v27.sh` | يدوي مرة واحدة | دليل ترحيل v27 (مفتاح فريد للتحدي النشط فقط) |
| `ops/scripts/min_build.sh` | يدوي على الـVPS: current، census، plan، apply | أداة قرار حدّ التحديث الإجباري: current / census / plan / apply بفحص أمان |
| `ops/scripts/podcast_to_reels.py` | يدوي | قصّ البودكاست إلى ريلز 30–60 ثانية بنص عربي وعلامة مائية |
| `ops/scripts/pregen_stories.py` | كرون 02:30 | كرون 02:30: توليد القصص مسبقًا للكاش (--max 20) |
| `ops/scripts/send_broadcast_stories_push.py` | يدوي | بثّ متعدد عالي الأداء لإشعار القصص |
| `ops/scripts/send_update_push.py` | يدوي `--below N [--send --limit]` | دفع لطيف لمن هم على بناء قديم (--below N، يرسل فقط مع --send) |
| `ops/scripts/set_feedback_webhook.py` | يدوي (`--status`) | تسجيل/فحص/إزالة webhook بوت تلجرام الملاحظات |
| `ops/scripts/story_motion_verdict.py` | يدوي نهاية الشهر | حكم نهاية الشهر لتجربة «صورة حيّة»: حركة مقابل ثابت |
| `ops/scripts/warm_answer_cache.py` | كرون 03:00 | كرون 03:00: تسخين كاش الإجابات بأسئلة الألم الشائعة |
| `ops/scripts/weekly_dashboard.py` | كرون أسبوعي | داشبورد أسبوعي (LLM + احتفاظ + DB) إلى تلجرام |
| `ops/scripts/weekly_funnel_report.py` | كرون السبت 07:00 | تقرير القمع والاحتفاظ الأسبوعي (السبت 07:00) إلى تلجرام — مجمّع فقط |
| `ops/scripts/weekly_kb_gap_report.py` | كرون السبت 06:00 (`--allow-unfiltered` للتجاوز) | تقرير فجوات المعرفة الأسبوعي (السبت 06:00): أسئلة حقيقية ← استرجاع ← حكم LLM ← تلجرام |

### 6.2 `ops/tools/` — أدوات؛ عمود «يُستدعى من» محسوب بـgrep على الخطافات وCI

| الأداة | يُستدعى من | الغرض |
|---|---|---|
| `ops/tools/add_coverage_units.py` | يدوي | Add knowledge units for under-covered domains: ADHD, Autism, Gaming Disorder. Content is conservative, parent-facing,… |
| `ops/tools/add_knowledge_unit.py` | يدوي | Add a new knowledge unit interactively. Prompts the user for all required fields, validates against the schema, |
| `ops/tools/adhkar_pack.py` | يدوي | The parenting-content pack, as the three notification-content guards see it. |
| `ops/tools/age_reach_probe.py` | يدوي | Measure whether the hand-authored gap units are reachable — matched and unmatched age. |
| `ops/tools/anbiya_fidelity.py` | يدوي (يذكره نص pre-commit عند الفشل) | حكم أمانة قصة جملةً جملة بعائلتين (`run`/`report`، `--series sira_sahih`) |
| `ops/tools/anbiya_sources.py` | يدوي (يذكره نص pre-commit عند الفشل) | جلب مصادر قصة نبي إلى `ops/data/anbiya/` (`fetch`/`show`) |
| `ops/tools/balance_quiz_answer_positions.py` | يدوي | Spread the correct answer across positions in every backend-served quiz. |
| `ops/tools/bare_mint_readiness.py` | يدوي | أعداد جاهزية إغلاق السكّ العاري (قراءة فقط) |
| `ops/tools/build_commandr_trainset.py` | يدوي | Format the premium QA corpus into chat-messages JSONL for fine-tuning. |
| `ops/tools/build_final_corpus.py` | يدوي | build_final_corpus — تنظيف + دمج + تقرير جودة للكوربوس النهائي. |
| `ops/tools/build_golden_set.py` | يدوي | Build the golden evaluation set for answer-quality benchmarking. |
| `ops/tools/build_hadith_index.py` | يدوي | Build the two hadith indexes the content guards match against. |
| `ops/tools/build_real_eval_set.py` | يدوي | build_real_eval_set.py — Extracts a balanced, representative, and strictly anonymized eval set of ~100 real parent questions from… |
| `ops/tools/build_vector_db.py` | خطّاف git | Build / rebuild ChromaDB vector index for knowledge_base/units/*.json. Uses the ONNX embedder built into ChromaDB (no external… |
| `ops/tools/candidate_smoke.py` | CI | Fast smoke of a candidate backend image — the in-image gate of every deploy. |
| `ops/tools/candidate_smoke.sh` | CI | Run the in-image smoke (ops/tools/candidate_smoke.py) against a candidate |
| `ops/tools/check_adhkar_integrity.py` | خطّاف git | Guard the daily-notification content against padding and blanket attribution. |
| `ops/tools/check_anbiya_stories.py` | pre-commit · CI (`backend.yml`) | حارس قصص الأنبياء ضد مصادرها |
| `ops/tools/check_curriculum_schema.py` | خطّاف git | فحص: ملفات المنهج تطابق مخطّطاتها — عربيها وإنجليزيها |
| `ops/tools/check_deploy_drift.py` | CI | Alert when main has deploy-relevant commits that production is not running. |
| `ops/tools/check_hadith_citations.py` | خطّاف git · CI | Verify every hadith in the app against Sahih al-Bukhari and Sahih Muslim. |
| `ops/tools/check_infographic_language.py` | يدوي | فحص: الإنفوجراف الإنجليزي مكتوب بالإنجليزية فعلًا |
| `ops/tools/check_kb_fidelity.py` | خطّاف git · CI | check_kb_fidelity.py — هل ملخّص وحدة المعرفة أمينٌ لمصدرها؟ وهل الحجر صامد؟ |
| `ops/tools/check_kb_integrity.py` | خطّاف git · CI · check.sh | Knowledge-Base Integrity Guard — حارس سلامة قاعدة المعرفة |
| `ops/tools/check_path_video_coverage.py` | يدوي | فحص: تغطية فيديو المسارات تُقاس على المنهج لا على الخريطة |
| `ops/tools/check_programs.py` | خطّاف git | فحص: برامج الأسرة (رمضان · رحلة الصلاة · المراحل) سليمة المراجع ومتطابقة اللغتين |
| `ops/tools/check_quoted_texts.py` | يدوي | فاحص النصوص الشرعية المقتبسة — بلاغ لا تصحيح |
| `ops/tools/check_quran_citations.py` | خطّاف git · CI | Verify every Qur'an citation in the app against the mushaf text. |
| `ops/tools/check_quran_rendering.py` | خطّاف git | فحص: القرآن لا يُترجَم — وأي معنًى بالإنجليزية يُعلَن أنه تفسير |
| `ops/tools/check_scholar_quotes.py` | خطّاف git · CI (`backend.yml`) | حارس نسبة الأقوال لأهل العلم (`check` بلا شبكة؛ `verify` يدوي يسأل turath.io بحدّ طلب كل 4 ثوانٍ) |
| `ops/tools/check_scripture_coverage.py` | خطّاف git · CI | Every quoted ayah and hadith the app ships — not just the ones in one file. |
| `ops/tools/check_served_assets.py` | CI | Verify that what lesson_index.json promises is what this host can serve. |
| `ops/tools/check_sira_stories.py` | pre-commit · CI (`backend.yml`) | حارس قصص السيرة ضد مصادرها |
| `ops/tools/chroma_recall_capture.py` | CI | Build disposable indexes from frozen real vectors; never migrate a database. |
| `ops/tools/chroma_recall_probe.py` | CI | Compare captured retrieval IDs. Never opens Chroma, models, or the network. |
| `ops/tools/chroma_runtime_probe.py` | CI | Hosted, copied-index runtime proof. Never run against a production volume. |
| `ops/tools/content_surfaces.py` | CI | Every text the app ships to a parent or a child — as the scripture guards see it. |
| `ops/tools/deepen_paths.py` | يدوي | تعميق المسارات بالطلب — دروس مكتوبة من الوحدات، وطعنٌ من عائلة نماذج أخرى |
| `ops/tools/deploy_gate.py` | CI | Deploy gate — production only gets a commit whose hosted tests passed. |
| `ops/tools/enrich_all.py` | يدوي | ⚠️ سكربت إثراء وحدات قديم (مسار نسبي، يكتب units_backup/) |
| `ops/tools/enrich_batch.py` | يدوي | ⚠️ سكربت إثراء دفعي قديم |
| `ops/tools/enrich_local.py` | يدوي | ⚠️ إثراء بـOllama المحلي — مسارات مطلقة ~/… |
| `ops/tools/enrich_local_fast.py` | يدوي | ⚠️ إثراء محلي سريع — مسارات مطلقة |
| `ops/tools/enrich_local_v3.py` | يدوي | ⚠️ إثراء محلي v3 — مسارات مطلقة |
| `ops/tools/eval_answers.py` | يدوي | Answer-quality evaluation harness. |
| `ops/tools/eval_ollama_compare.py` | يدوي | Judge + rule-check a head-to-head run from eval_ollama_models.py. |
| `ops/tools/eval_ollama_direct.py` | يدوي | Direct (no pipeline, no retrieval) head-to-head — the July v3/v4/v5 method. |
| `ops/tools/eval_ollama_models.py` | يدوي | Head-to-head of local Ollama models through the real /assistant/draft pipeline. |
| `ops/tools/export_real_parent_corpus.py` | يدوي | export_real_parent_corpus.py — Pure-Python, zero-model exporter that prepares the anonymized Real Parent Questions & Knowledge… |
| `ops/tools/extract_app_content.py` | يدوي | Move the app's hard-coded Arabic content out of Dart and into JSON assets. |
| `ops/tools/fal_common.py` | يدوي | fal_common — الهوية البصرية الموحّدة + سجل موديلات fal.ai المشترك بين gen_visuals.py وgen_launch.py. |
| `ops/tools/feedback_digest.py` | يدوي | feedback_digest — تقرير قرارات قابل للقراءة من تحليل الفيدباك الذكي. |
| `ops/tools/fix_arabic_encoding.py` | يدوي | Fix Arabic encoding issues in knowledge units by regenerating text_simplified using a local LLM (qwen2.5:3b) that handles Arabic… |
| `ops/tools/fix_arabic_encoding_v2.py` | يدوي | Fix Arabic encoding issues by regenerating text_simplified from behavior_type + domain + reference_info using qwen2.5:3b (local,… |
| `ops/tools/fix_one_unit.py` | يدوي | ⚠️ إصلاح لمرة واحدة لوحدة بمعرّف مكتوب في الكود |
| `ops/tools/fix_translation_defects.py` | يدوي | إصلاح ملاحظات المراجع على الترجمة الإنجليزية — بثلاث بوابات لا بثقة |
| `ops/tools/gen_launch.py` | يدوي | gen_launch — أصول إطلاق + هيرو صفحة الهبوط (نفس هوية gen_visuals، بلا نص). |
| `ops/tools/gen_lottie.py` | يدوي | gen_lottie — generate lightweight, brand-aligned Lottie animations for Tutor Guardian celebrations. |
| `ops/tools/gen_sfx.py` | يدوي | gen_sfx — synthesise the app's five interface sounds from code. |
| `ops/tools/gen_visuals.py` | يدوي | gen_visuals — توليد المحتوى البصري المخصّص لـ«المربّي» بأسلوب موحّد محتشم. |
| `ops/tools/generate_dataset_v2.py` | يدوي | Fine-tune dataset v2 generator — Azure DeepSeek backed. |
| `ops/tools/generate_qa_dataset.py` | يدوي | Generate QA dataset for Tutor Guardian fine-tuning. Reads knowledge units from the KB and uses an LLM to generate realistic |
| `ops/tools/generate_real_gap_kb_units.py` | يدوي | generate_real_gap_kb_units.py — Generates 25 schema-validated Knowledge Base units covering the top real-parent KB gaps… |
| `ops/tools/generate_tip_cards.py` | يدوي | generate_tip_cards.py — توليد كروت نصائح يومية مربعة (1080x1080) مطابقة لتصميم ShareableMomentCard الفاخر والمعتمد في كود تطبيق… |
| `ops/tools/generate_veo_assets.py` | يدوي | Tutor Guardian - Google Veo Video Generation Tool |
| `ops/tools/gen_print_qr.py` | يدوي | يولّد `frontend/assets/print/qr_<CODE>.svg` لأوراق الطباعة |
| `ops/tools/golden_ci.py` | CI | Nonblocking golden reports; offline retrieval is never answer quality. |
| `ops/tools/golden_ci.sh` | CI | Hosted candidate only. No .env, production volume, or provider credential. |
| `ops/tools/ingest_pdf.py` | يدوي | Unified PDF-to-knowledge-units ingest pipeline. |
| `ops/tools/ingest_source.py` | يدوي | Pipeline to ingest a source document (PDF or TXT) and convert to knowledge units. |
| `ops/tools/ingest_tarbiya_alwan.py` | يدوي | يسحب وحدات معرفة من ملف Tarbiya_Al_Awlad_Alwan.txt - ينظف OCR (يزيل الأسطر القصيرة والرموز) |
| `ops/tools/kb_gap_judge.py` | ops/scripts | Judge each (question, retrieved unit) pair for topical relevance. |
| `ops/tools/language_rank_probe.py` | يدوي | قياس ترتيب اللغة: ماذا كسبت العربية، وماذا خسرت الإنجليزية |
| `ops/tools/llm_stats.py` | يدوي | LLM Call Stats — تقرير من sessions.db |
| `ops/tools/media_index.py` | يدوي | تسجيل الميديا في docs/lesson_index.json — إدراج أو استبدال، لا إسناد |
| `ops/tools/normalize_units.py` | خطّاف git | One-time data normalizer — تنظيف قيم enum المتسخة في وحدات المعرفة |
| `ops/tools/ocr_pdf.py` | يدوي | OCR extraction for Arabic/English PDFs using Tesseract + pdf2image. Saves extracted text as .txt sidecar files for use by… |
| `ops/tools/process_collected_questions.py` | يدوي | Process collected real-world parent questions through the RAG pipeline. |
| `ops/tools/push_kaggle_v6_dpo_kernel.py` | يدوي | Push Phase 2 DPO Alignment Kernel (`tg-tutor-v6-dpo`) to Kaggle `GpuT4x2`. Trains Direct Preference Optimization (DPO) on top of… |
| `ops/tools/push_kaggle_v6_kernel.py` | يدوي | push_kaggle_v6_kernel.py — Publishes the v6 dataset to the private Kaggle dataset (`YOUR_KAGGLE_USER/tg-qa-dataset`) and pushes the… |
| `ops/tools/refresh_source_map.py` | يدوي | إعادة بناء source_to_lesson.json من الحالة الحيّة للدفتر |
| `ops/tools/repair_device_twins.py` | يدوي | Re-attach families whose install split into device twins — one-off repair. |
| `ops/tools/retrieval_probe.py` | ops/scripts | Measure retrieval precision locally — never against the production index. |
| `ops/tools/revalidate_translations.py` | يدوي | إعادة تحقّق من ترجمات المنهج الإنجليزية — عدّ حقيقي بدل سجلات بائتة |
| `ops/tools/review_en_parity.py` | خطّاف git · CI | بوابة المحتوى الإنجليزي — مراجعة آلية بنموذجين من عائلتين، ثم ختم موثَّق |
| `ops/tools/run_gemma4_31b_real_questions_teacher.py` | يدوي | run_gemma4_31b_real_questions_teacher.py — Runs `gemma4:31b` on Ollama Cloud (pure HTTP API, zero local models) over real parent… |
| `ops/tools/runtime_readiness_report.py` | CI | Manual trusted-main diagnostic. Only ciphertext leaves the existing container. |
| `ops/tools/scripture_scan.py` | يدوي | Find quoted scripture inside free text, and say whether it is sound. |
| `ops/tools/seed_vps_answer_cache_from_teacher.py` | يدوي | seed_vps_answer_cache_from_teacher.py — Exports all clean, standalone `Gemma 4 31B` gold-standard answers (plus the 25 new KB gap… |
| `ops/tools/sira_sources.py` | يدوي (يذكره نص pre-commit عند الفشل) | جلب مصادر قصة سيرة إلى `ops/data/sira/` |
| `ops/tools/social_media_autoposter.py` | يدوي | social_media_autoposter.py — أداة النشر التلقائي لمنشورات التسويق والتربية اليومية. تقرأ النصائح من… |
| `ops/tools/test_post_infographic.py` | يدوي | test_post_infographic.py — سكربت اختبار سريع لنشر أحد الانفوجرافات المائية على جميع الحسابات (تليجرام وبفر) فوراً. |
| `ops/tools/translate_curriculum.py` | يدوي | ترجمة المنهج إلى الإنجليزية — خط إنتاج بمراجعة عدائية |
| `ops/tools/translate_knowledge_base.py` | يدوي | ترجمة قاعدة المعرفة إلى الإنجليزية — وحدات جديدة، لا استبدال |
| `ops/tools/translate_stories.py` | يدوي | ترجمة قصص الأطفال إلى الإنجليزية — نفس خط الإنتاج بمراجعة عدائية |
| `ops/tools/upload_ultra_bundle_to_hf.py` | يدوي | upload_ultra_bundle_to_hf.py — Uploads the anonymized & Teacher-distilled Google Colab Ultra bundle (`tg_colab_ultra_bundle.zip`… |
| `ops/tools/validate_age_groups.py` | يدوي | Validate that every age_group in knowledge_base/units/*.json maps to a canonical value. Exits with code 1 if any unknown… |
| `ops/tools/validate_knowledge_units.py` | يدوي | التحقق من ملفات وحدات المعرفة مقابل JSON schema (يُذكر في README) |
| `ops/tools/watermark_infographics.py` | يدوي | watermark_infographics.py — سكربت لإضافة لوجو التطبيق تلقائياً وعلامة مائية على الانفوجرافات المولدة مسبقاً وتصديرها لمجلد… |
| `ops/tools/write_infographic_prompts.py` | يدوي | كتابة بلوكات برومبت الإنفوجراف للدروس التي لا تملك واحدًا |

### 6.3 `scripts/` — مولّدات محتوى ونشر (تُشغَّل يدويًا أو من كرون محلي)

| السكربت | الغرض |
|---|---|
| `scripts/add_new_lesson_podcasts.py` | One-shot: register the 25 newly-authored lessons in the podcast pipeline. |
| `scripts/adhkar_tips_en.py` | English wording for the 124 `tip` items in the family adhkar pack. |
| `scripts/build_lesson_index.py` | Build unified lesson index from AI-generated assets. |
| `scripts/check_buffer_post_status.py` | Read the real outcome of Buffer posts — did the network actually publish? |
| `scripts/check_new_lessons.py` | فحص أصول الدروس الجديدة مقابل lesson_index |
| `scripts/clean_notebooklm_duplicates.py` | Regex to find lesson IDs, e.g. lesson_16-18_medical_adult_transition_03 or lesson_4-6_islamic_parenting_adab_01 |
| `scripts/cleanup_reports_and_indices.py` | Cleanup curriculum assets: 1. Strips LLM preamble and "Answer:" block from Markdown reports. |
| `scripts/complete_toddler_curriculum.py` | Complete the 2-3 ("toddler") age band: generate sourced lesson bodies from the user's NotebookLM "المربي" notebook and write… |
| `scripts/compose_screenshots.py` | تركيب لقطات متجر Play (مسارات مطلقة) |
| `scripts/cron_gen_en_media.sh` | Daily English media generation — harvest first, then each medium on its own |
| `scripts/cron_gen_path_videos.sh` | Periodic NotebookLM path-video generation for the 12 new paths, until done. |
| `scripts/cron_gen_podcasts.sh` | Periodic NotebookLM podcast generation, one language per invocation. |
| `scripts/cron_regen_podcasts.sh` | Daily retry of NotebookLM podcast regeneration until all 53 placeholder |
| `scripts/demo_grounded_generation.py` | تجربة توليد مؤصّل من كتاب PDF عبر NotebookLM (معرّف دفتر مكتوب) |
| `scripts/demo_media_generation.py` | Configuration |
| `scripts/emulator_controller.py` | تحكم بالمحاكي عبر adb (مسار SDK مطلق) |
| `scripts/expand_lessons.py` | Expand the curriculum so every path has >=4 lessons (broad expansion across all ages, per the maintainer's choice). 25 hand-authored text… |
| `scripts/export_to_notebooklm.py` | تحويل دروس المنهج إلى Markdown مجمّعة بالعمر لـNotebookLM |
| `scripts/extract_hero_frames.py` | Extract, resize, and compress video frames from Flow video for canvas scroll scrubbing. |
| `scripts/fill_all_lesson_media.py` | Fill missing lesson media so EVERY lesson in docs/lesson_index.json has both a podcast (edge-tts) and a video (PIL title card +… |
| `scripts/fix_failed_assets.py` | A real section runs to thousands of characters. Anything shorter is a failed |
| `scripts/ga4_cohort_report.py` | Daily-cohort retention + acquisition report from GA4. |
| `scripts/gen_aqeedah_infographics_batch.py` | Generate remaining aqeedah infographics one by one with per-lesson timeout. |
| `scripts/gen_flashcards_quizzes.py` | Generate flashcards + quizzes for the 25 new lessons (the _bNN ones) from their own text, using the local Ollama model with… |
| `scripts/gen_lesson_videos.py` | Local video generator for the new lessons (NotebookLM is rate-limited). Builds a clean title-card (domain gradient + shaped… |
| `scripts/gen_path_videos_cron.py` | Cron-safe path-video generator (NotebookLM video overviews), any language. |
| `scripts/gen_podcasts_cron.py` | Cron-safe podcast generator (NotebookLM audio overviews), any language. |
| `scripts/gen_tts_podcasts.py` | Local-ish alternative to NotebookLM: narrate each new lesson as an MP3 using edge-tts (Microsoft free neural TTS, Arabic Egyptian… |
| `scripts/generate_all_podcasts.py` | توليد بودكاست لكل الدروس عبر notebooklm CLI |
| `scripts/generate_all_podcasts_v2.py` | generate_all_podcasts_v2.py Upload missing lesson markdown files to NotebookLM, then trigger + poll + download podcasts. |
| `scripts/generate_arabic_podcasts.py` | توليد بودكاستات عربية |
| `scripts/generate_clean_assets.py` | Clean per-lesson interactive assets (flashcards + quiz), authored from each lesson's own content — replacing the broken… |
| `scripts/generate_gap_fill_units.py` | Gap-filling content generator — knowledge units for the top-9 repeated parent-question themes that retrieval failed to serve… |
| `scripts/generate_lesson_01_assets.py` | Configuration |
| `scripts/generate_missing_data_tables.py` | Generate missing data_table assets for lessons using NotebookLM ask. |
| `scripts/generate_missing_infographics.py` | Generate missing infographic assets for lessons using NotebookLM. |
| `scripts/generate_missing_path_videos.py` | توليد فيديوهات المسارات الناقصة |
| `scripts/generate_missing_podcasts.py` | Generate the NotebookLM episode for every lesson whose index entry has none. |
| `scripts/generate_missing_reports.py` | Generate missing report assets for lessons using NotebookLM ask. |
| `scripts/generate_new_lesson_md.py` | Generate NotebookLM markdown source files for the 25 newly-authored lessons (ids ending in _bNN) so the existing podcast pipeline… |
| `scripts/generate_path_videos.py` | توليد فيديوهات المسارات |
| `scripts/generate_pending_text_assets.py` | Configuration |
| `scripts/generate_toddler_lessons.py` | Correct answer goes to a spread, deterministic slot — the same one |
| `scripts/infographic_prompts_lib.py` | infographic_prompts_lib — استخراج بلوكات البرومبت لكل درس من scripts/infographic_prompts.md، وحساب الدروس الناقصة فيها إنفوجرافيك. |
| `scripts/lib/nblm_session.sh` | shellcheck shell=bash |
| `scripts/link_lessons_to_units.py` | Link the 25 new hand-authored lessons (unit_ids == []) to the most relevant knowledge-base units, so the lesson screen stops… |
| `scripts/make_youtube_short.py` | Convert a tutor-guardian path video into a YouTube Short (9:16) with captions and CTA. |
| `scripts/migrate_age_groups.py` | ترحيل age_group في lesson_index إلى القيم القانونية |
| `scripts/monitor_qa_v2.sh` | Monitor tutor-guardian v2 fine-tune dataset generation. |
| `scripts/nblm_failure.py` | مكتبة يستوردها `gen_podcasts_cron.py`/`gen_path_videos_cron.py`/`generate_missing_infographics.py`: تمييز جلسة NotebookLM الميتة عن المهمة الغائبة |
| `scripts/parse_all_assets.py` | Parse markdown asset files -> JSON flashcards + slides Updates lesson_index.json and creates JSON files in docs/lesson_assets/ |
| `scripts/parse_generated_assets.py` | Output files |
| `scripts/play_listing_upload.py` | Google Play — store-listing refresh (text + graphics) for المربّي. |
| `scripts/play_reviews.py` | تعليقات Google Play — قراءة والرد |
| `scripts/play_upload.py` | Google Play Store — رفع AAB تلقائي |
| `scripts/podcast_to_reel.py` | podcast_to_reel.py — convert a tutor-guardian podcast into a 9:16 marketing Reel. |
| `scripts/prepare_play_assets.py` | 1. Copy App Icon |
| `scripts/publish_reels_to_buffer.py` | Publish generated tutor-guardian reels to Buffer (Instagram/TikTok/Facebook). |
| `scripts/reel` | اختصار bash لمصنع الريلز من أي مجلد |
| `scripts/reel_from_video.py` | مصنع الريلز — v2: يقصّ من فيديوهات المنهج بدل توليد صورة ثابتة |
| `scripts/reels_pipeline.py` | tutor_reels: generate reels. Publishing is a separate, deliberate step. |
| `scripts/regen_podcasts.py` | Regenerate REAL NotebookLM audio for lessons whose local docs/ file is an edge-tts placeholder, then download + place it at the… |
| `scripts/release_bundle.py` | Inspect unsigned hosted AABs and locally signed copies. Never signs or uploads. |
| `scripts/release_play_publish.py` | Publish the exact validated signed artifact at 100%; no build or signing. |
| `scripts/release_play_validate.py` | Validate a verified, locally signed AAB in our temporary Play edit. Never commits. |
| `scripts/remove_bad_podcasts.py` | Find all mp3 files created in the last 3 days (these are the bad ones) |
| `scripts/resume_infographics_cron.sh` | Resumable infographics batch driver (cron-friendly). |
| `scripts/seed_common_gap_units.py` | Seed high-quality knowledge units for the most common parenting concerns that were proven gaps in the KB (picky eating, tantrums,… |
| `scripts/seed_common_gap_units_2.py` | Batch 2 of curated knowledge units for common parenting gaps. |
| `scripts/seed_flashcards_quizzes.py` | Hand-authored flashcards + quizzes for the 25 new lessons (the maintainer asked me to write them, not the local model). Each lesson gets… |
| `scripts/seed_infant_pregnancy_curriculum.py` | Seed script for Infant & Pregnancy (الحمل والرضع) Curriculum Content |
| `scripts/seed_infant_pregnancy_curriculum_en.py` | Seed script for English Infant & Pregnancy (الحمل والرضع) Curriculum Content |
| `scripts/seed_prenatal_assets.py` | Seed hand-crafted, high-yield interactive assets (flashcards + quizzes) for the 5 lessons of the "prenatal-1" infant_pregnancy… |
| `scripts/sharia_review_en.py` | Independent Sharia review of English translations vs Arabic originals. v2: Proper Arabic word boundaries, distinguishes verb خلق… |
| `scripts/sync_index_with_curriculum.py` | Add published curriculum lessons that docs/lesson_index.json does not know. |
| `scripts/test_app_flow.py` |  |
| `scripts/test_navigation.py` |  |
| `scripts/trigger_and_download_podcasts.py` | trigger_and_download_podcasts.py Trigger audio generation for all lessons that have source_id but no podcast, |
| `scripts/update_lesson_index.py` | Update lesson_index.json with newly generated flashcards and slides |
| `scripts/update_production_registry.py` | Update production_registry.md - robust table parsing |
| `scripts/upload_new_podcast_sources.py` | Efficient one-shot upload of the 48 new lesson md sources to NotebookLM. |
| `scripts/upload_to_notebooklm.py` | List of possible method names and their call signatures |
| `scripts/validate_podcasts.py` | Guard against placeholder/broken lesson podcasts. |
| `scripts/write_notebooklm_sources.py` | Write the NotebookLM markdown source for lessons that have none. |
| `scripts/write_path_source.py` | Write the NotebookLM path source a path video is generated from. |

*`scripts/archive/*` أرشيف مستبدَل (15 ملفًا) — لا تُشغَّل.*

### 6.4 أدوات أخرى

| الأداة | الغرض |
|---|---|
| `mobile/tool/audit_light_surfaces.dart` |  |
| `docs/brand/tools/brand_build.py` | خط الهوية البصرية — أوامر فرعية `review` · `android <a\|b\|c>` · `store` · `web` · `frame` (argparse) |
| `docs/brand/tools/store_listing.py` | مجموعة قائمة متجر Play — `build --listing … --captures <run_id>=<dir>` و`contact` (argparse) |
| `mobile/tool/gen_story_narration.py` | «اسمعها من نور» — record a story, one file per page, with sentence timings. |
| `mobile/tool/real_recitation.py` | Real recitation for a ﴿verse﴾ quoted in a story — no TTS voice ever recites the Qur'an. |
| `mobile/tool/story_alive_demo.dart` |  |
| `mobile/tool/story_art.py` | «ورق مقصوص» — the story scenes' cut-paper pieces, written as SVG. |
| `mobile/tool/test_gen_story_narration.py` | The narration check: a page passes only if its transcript is the page. |
| `remotion-reels/scripts/check_vo.py` | check_vo — an independent ear on the voice-over takes. |
| `remotion-reels/scripts/gen_teaser_qr.py` | gen_teaser_qr — the QR codes on the teaser's and the campaign reels' end cards. |
| `remotion-reels/scripts/gen_teaser_sfx.py` | gen_teaser_sfx — the four soft sounds of the «نور» teaser, computed from code. |
| `remotion-reels/scripts/gen_vo.py` | gen_vo — the voice-over lines of the «المربّي» reels (teaser + five campaign reels). |
| `remotion-reels/scripts/make_campaign_sheet.py` | make_campaign_sheet — a contact sheet of the campaign reels, pulled from the rendered MP4s themselves (not from the source), so… |
| `remotion-reels/scripts/make_reel_data.py` | Generate Remotion data/reel.json from tutor-guardian path manifest. |
| `remotion-reels/scripts/make_round_logo.py` | make_round_logo — the app icon, cut to a circle, for the teaser and the campaign reels (end card + small corner mark). |
| `remotion-reels/scripts/render.sh` | رندر الريل العام (قديم) |
| `remotion-reels/scripts/render_noor_campaign.sh` | Render the six «المربّي» campaign reels (1080×1920, H.264, 30 fps), one |
| `remotion-reels/scripts/render_noor_teaser.sh` | Render the «نور» teaser: three MP4s (H.264, CRF 18) and six key stills of |
| `remotion-reels/scripts/render_noor_vo.sh` | Render the voice-over cuts (`_vo`): the Arabic teaser and the six campaign |
| `remotion-reels/scripts/sync_app_art.sh` | Copy the app's own «ورق مقصوص» art (mobile/assets/svg/stories + noor) into |
| `remotion-reels/scripts/verify_videos.py` | verify_videos — check rendered reels by their effect, not by the render's exit code. |
| `backend/scripts/debug_coach.py` | أداة تصحيح: توليد نصيحتين مع لوج مفصّل |
| `backend/scripts/generate_coach_samples.py` | توليد ~20 عيّنة نصيحة للمراجعة البشرية (Gate #1) |
| `check.sh` | بوابة جودة محلية: check_kb_integrity (--full يضيف Chroma + الاختبارات) |
| `e2e/run.sh` | Runs the E2E journeys on the emulator that reactivecircus/android-emulator-runner |
| `e2e/rehearsal.sh` | The Ramadan rehearsal (gate G2) and the sound × recitation check, on the |
| `e2e/install_system_image.sh` | Installs the emulator system image before reactivecircus/android-emulator-runner |
| `.github/ci/lock-backend-deps.py` | إعادة توليد requirements-prod.lock من constraints الإنتاج |
| `.github/ci/refresh-constraints-from-prod.sh` | تحديث constraints-prod.txt من حزم الحاوية الحية |
| `.github/ci/reject-broken-images.sh` | يكسر نسخة من الصورة ويطلب من الـsmoke رفضها |

### 6.5 أوامر شائعة (من README/الدليل)

```bash
# تشغيل محلي
PYTHONPATH=$(pwd) python -m uvicorn backend.app.main:app --reload --port 8090      # من README (يتطلب CHILD_MODE_SECRET)
docker compose up -d ollama && docker compose up -d backend                          # الحزمة المحلية (8000)
# حراس
./check.sh [--full]  ·  python ops/tools/check_kb_integrity.py --check-index
python ops/tools/normalize_units.py && python ops/tools/build_vector_db.py          # بعد تعديل وحدات المعرفة
# اختبارات
backend/.venv/bin/python -m pytest        # لا python3 المجرد (ينقصه chromadb)
cd mobile && flutter analyze --fatal-infos --fatal-warnings && flutter test
# خطافات
git config core.hooksPath .githooks      # ⚠️ المسار المطلق في الشجرة الرئيسية يحكم كل الأشجار
```

## 7) سير GitHub Actions (`.github/workflows/`)

| الملف | يشتغل عند | يعمل على | الغرض |
|---|---|---|---|
| `backend.yml` | push/PR (مسارات الباكند/KB + `ops/data/sira/**`) + dispatch | GitHub-hosted | pytest (+golden CI) + سلامة KB + حرّاس الآيات/الأحاديث/التغطية + حارسا قصص الأنبياء والسيرة + حارس نسبة الأقوال لأهل العلم + تكافؤ الإنجليزي + ruff — بوابة النشر |
| `deploy.yml` | push إلى main (مسارات `backend/**` · `knowledge_base/**` · `ops/tools/**` · `ops/scripts/**` · `frontend/**` · `docs/lesson_index.json` · `docs/lesson_assets/**` + ملفات compose/Dockerfile/lock) + dispatch | gate+image: GitHub · deploy+alert: self-hosted `[self-hosted, production]` (runner `vps-tg`) على الـVPS؛ الـgate مشروط بـ`github.repository == almorabbi/almorabbi` و`vars.CUTOVER_DONE == true` | gate (ينتظر backend.yml لنفس الـSHA) ← image (GHCR + smoke) ← deploy (فحص media، نسخ احتياطي، recreate، فحص /health و/privacy-policy و/api/app-config، تراجع تلقائي) ← alert تلجرام |
| `flutter.yml` | push/PR على mobile/** + dispatch | GitHub-hosted | flutter analyze + flutter test |
| `mobile-e2e.yml` | PR + dispatch | GitHub-hosted (KVM) | بناء APK release للرأس والأساس ثم رحلات Maestro (fresh×14 + upgrade×4) + تجربة رمضان (rehearsal) + معرض لقطات + بوابة delivery |
| `e2e-avd-cache.yml` | يومي 04:23 + push/PR + dispatch | GitHub-hosted | حفظ لقطة AVD على main |
| `candidate-image.yml` | PR على ما يدخل الصورة + dispatch | GitHub-hosted | يبني ويفحص الصورة ويكسرها ثلاث مرات ليتأكد أن الـsmoke يرفض |
| `release-play.yml` | dispatch فقط (main) | GitHub-hosted | AAB موقَّع ← Google Play (track + rollout) |
| `build-release-unsigned.yml` | PR + dispatch | GitHub-hosted | AAB غير موقَّع لـSHA معتمد (التوقيع والرفع محليان) |
| `runtime-readiness.yml` | dispatch | self-hosted production (diagnostic) | تشخيص جاهزية يدوي بمخرجات مشفّرة بمفتاح عام مؤقت |
| `golden-full.yml` | dispatch | GitHub-hosted | تقييم ذهبي كامل (بلا مفاتيح => UNAVAILABLE) |
| `chroma-1x-recall.yml` | dispatch | GitHub-hosted | تجربة Chroma 1.x (استدعاء) |
| `chroma-1x-runtime.yml` | dispatch | GitHub-hosted | تجربة Chroma 1.x (تشغيل/ترحيل) |
| `docker.yml` | push/PR/dispatch | GitHub-hosted | بناء صورة (مطفأ عمليًا حسب الدليل) |
| `ci.yml` | dispatch فقط | self-hosted production | ⚠️ مُعطَّل عمدًا — redirect إلى backend.yml |

## 8) خطافات git (`.githooks/`، تفعيل: `git config core.hooksPath .githooks`)

| الخطّاف | يشغّل |
|---|---|
| `pre-commit` | بالترتيب: `check_kb_integrity` ← `check_quran_citations` ← `check_quran_rendering` (فشل self-test = إيقاف) ← `review_en_parity check --staged` ← `check_adhkar_integrity` ← `check_hadith_citations` ← `check_scripture_coverage` ← `check_anbiya_stories` ← `check_sira_stories` (exit 2 = اختباراتهما الذاتية) ← `check_scholar_quotes check` ← `check_curriculum_schema` ← `check_programs` ← `check_kb_fidelity check` ← ruff على `backend/ ops/ scripts/` |
| `pre-push` | إن مسّت الدفعة `mobile/`: `flutter analyze --fatal-infos --fatal-warnings` + `flutter test` (يتخطّى `SKIP_MOBILE_CHECKS=1`) |

⚠️ في نسخة almorabbi المحلية `core.hooksPath` **غير مضبوط** (مُقاس 2026-11-08) ⇒ الخطافات لا تعمل عند الـcommit ما لم تُفعَّل؛ CI (`backend.yml`) يشغّل الحرّاس نفسها كبوابة. قبل commit محتوى شرعي شغّل `bash .githooks/pre-commit` يدويًا من جذر الشجرة (أو فعّل `git config core.hooksPath .githooks` — بمسار نسبي لا مطلق).

## 9) تطبيق الموبايل — نقاط الدخول

### 9.1 التبويبات الأربعة (`features/shell/root_scaffold.dart`، `IndexedStack`)

| الفهرس | التبويب | الشاشة |
|---:|---|---|
| 0 | اليوم `tab_today` | `screens/home_screen.dart` (ثلاث كتل: ① خطوة ابنك ② اسأل المربّي ③ مهمة الطفل + سماء نور + قناديل + متابعة/خطة + برامج الأسرة) |
| 1 | مساراتي `tab_learn` | `features/program/screens/paths_screen.dart` |
| 2 | المساعد `tab_assistant` | `screens/chat_screen.dart` |
| 3 | المزيد `tab_more` | `features/hub/screens/hub_screen.dart` (كتالوج بيانات `hub_catalog.dart`) |

### 9.2 كتالوج «المزيد» (`kHubGroups`)

| المجموعة | الوجهات |
|---|---|
| child | أطفالي · برامج الأسرة (مشروطة بـ`GET /api/programs`) · حساب اليوم/ميزان العادات (بحسب العمر) · تخصيص العادات · رؤى تربوية · يوم الأب (`parent_day`) |
| games | الألعاب التعليمية · الكويز |
| achievements | الشارات · العملات · شارات حصرية · العهد · المفضلة |
| library | حكايات النوم · مولّد القصص · المصحف · البحث |
| tools | الأذكار · المسبحة · محوّل هجري |
| (عام) | أين أجد…؟ · الإعدادات · احفظ تقدّمك · ادعُ صديقًا · شاركنا رأيك |

### 9.3 الشاشات المسمّاة (`Screens` في `core/app_routes.dart`) وفاكتوريات `AppRoutes`

67 فاكتوري في `AppRoutes` (كل دفع شاشة يمرّ منها لتوسم باسم ثابت لـGA4 — **لا تُعاد تسمية** ثابت). القائمة الكاملة في `05-ui.md`.

### 9.4 الروابط العميقة والإشعارات

- **App Links** (Android `autoVerify`): `https://tg-api.alsaba.cloud/{go,l/<lesson_id>,p/<path_id>}` ← `features/deeplink/deep_link_handler.dart`؛ التحقق عبر `/.well-known/assetlinks.json` (حزمة `com.alsaba.almorabbi`).
- **إسناد التثبيت:** `play_install_referrer` ← `referral_service.dart` يقرأ `ref_<CODE>` ويطالب به `POST /api/referral/claim`.
- **قنوات إشعار Android:** قناتان (`features/push/notification_channels.dart`): «تذكيرات ومستجدّات» و«تنبيهات سلامة الطفل» (الوحيدة التي تصل حتى لو أُسكتت الباقي).
- **أنواع رسائل FCM (حقل `data.type`):** `followup_due`، `milestone`، `mission_digest`، `account_alert`، `license_alert`، `device_proof` (تحدّي صامت)، + إعادة التفاعل من `cron_push_triggers.py`.
- **إشعارات محلية:** إشعار يومي واحد (`notification_service.dart`، يُجدوَل بمنطقة المستخدم الزمنية) — كان ثلاثة (أذكار 06:00/19:00 + ورد) ثم دُمجت.
- **أذونات Android:** INTERNET, ACCESS_NETWORK_STATE, AD_ID (+ACCESS_ADSERVICES_AD_ID), RECEIVE_BOOT_COMPLETED, WAKE_LOCK, POST_NOTIFICATIONS, RECORD_AUDIO (تسجيل صوت الأب/ملاحظة صوتية).

### 9.5 الواجهة البرمجية للعميل

`mobile/lib/api/tg_client.dart` (3508 سطرًا): عميل HTTP/SSE وحيد (`TgClient`) لكل مسارات §2 المستعملة من التطبيق: جلسات، بث/استعلام، منهج، أصول، بحث، تفسير، نصيحة المرشد، أطفال، تقدّم، تحدٍّ، إحالة، إشعارات، هوية، يومي/عادات، وضع الطفل، اتفاقية، مهام، رخصة، برامج الأسرة، ذاكرة، قناديل، حذف حساب. يجدّد التوكن شفافًا ويخفي نص أخطاء الخادم الخام.

مسارات الخادم **بلا عميل في التطبيق** (راجع FEATURES/08-gotchas): `/api/sync/*`، `/api/program/{daily-tip,story-themes,monthly-report}`، `/api/push/token`، `/api/quranic-linguistics/*`، `/api/tafsir/{search,search-tafsir,sources}`، `/api/health`، `/api/feedback/digest`.

