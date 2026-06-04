---
name: localization-slack-on-call
description: Use when a Slack on-call channel message arrives containing a structured localization request with fields like Task, Company, Babel project, Tag/List of keys, Urgency, Viewer.
---

# Localization Slack On-Call

Full end-to-end workflow for on-call channel localization requests. Parses the Slack bot message, resolves strings in Smartling, creates/reuses a job, and creates a Monday item + subitem.

## Input

Accept a Slack message URL or pasted text. If given a URL, fetch with `mcp__Webrix__slack__get_thread_replies` using channel ID and thread timestamp from the URL.

Structured fields to extract:

| Field | Usage |
|---|---|
| **Task** | `task_name` → item/subitem name in Monday, job name in Smartling |
| **Company** | `company` → Monday group lookup |
| **Babel project** | Context only (not used for routing) |
| **Tag** | `tag` → existing Smartling tag to search by |
| **Key doc** | Google Sheet URL with key names |
| **Requestor** | Record only |
| **Figma/Screenshots** | `"Screenshot in Smartling"` → skip Phase 3; or Figma URL |
| **Urgency** | Normal 🟢 → `is_urgent = false`; Urgent / 🔴 / "ASAP" → `is_urgent = true` |
| **Viewer (UoU)** | Yes → `is_uou = true`; No → `is_uou = false` |
| **Slack message URL** | `slack_url` → goes in COL_JIRA column on Monday item (replaces Jira link) |

## Phase 1: Resolve strings in Smartling

### 1a. Find the project ID

The company name maps to a Smartling project. Known mappings:

| Company | Smartling project | Project ID |
|---|---|---|
| Online Programs | Online Programs | `44e6d2cd4` |
| Premium (BILL, DOM, PREM-BE) | Premium | `b3eef828d` |
| Premium (PREM-Plans) | Plans | `25c8740e5` |
| eComm | eComm | `6bc9e740e` |

If the company is not in the table, determine project ID by searching for a key from the key doc (see 1b). Call `smartling_search_strings` with `exact_match=true` for one key. The project ID appears in the response.

### 1b. Get keys and hashcodes

**When a tag is provided in the message:**
Call `smartling_search_strings` with `tag_filter = tag` on the resolved project. This returns all strings with that tag — collect hashcodes and `totalWordCount`.

**When a key doc (Google Sheet) is provided:**
Call `google-workspace__get-sheet-values` on the spreadsheet ID (extract from URL). Find the "Key" column. For each key:
1. Call `smartling_search_strings` with `exact_match=true`
2. Collect: `hashcode`, `totalWordCount`, `fileUri`

Use parallel searches when there are multiple keys.

Collect:
- `hashcodes[]`
- `wordcount` = sum of `totalWordCount`
- `file_uris[]` = for GA artifact lookup

### 1c. GA artifact (Phase 2.5)

From `file_uris`, derive `projectPath` (up to `packages/<package-name>`) and call `devex__search_projects`.

Filter results: `repoUrl` must match the repo from the file path.

Get the `projectName` (e.g. `com.wixpress.challenges-web-business-manager`). Short name = strip `com.wixpress.` prefix.

Only set the Monday GA column if the short name exists in the dropdown. If not → skip silently.

## Phase 2: Smartling job

> **Do NOT authorize the job here.** Authorization happens in Phase 6.5 after content scoring, using the correct LLM workflow (GREEN/YELLOW/default). The workflow selection depends on the content score which is not known yet.

### Search for existing job
Call `smartling_list_jobs` with `project_id` and task name keywords.

Reuse rules:
- `IN_PROGRESS` → add strings ✅ (authorize in Phase 6.5)
- `COMPLETED` → reuse if relevant to same feature ✅ (add strings, authorize in Phase 6.5)
- `CANCELLED` → do NOT reuse

### Create or add to job
1. If a suitable existing job exists → `smartling_add_strings_to_job` only (no authorize yet)
2. Otherwise → `smartling_create_job` with `job_name = task_name`, `target_locale_ids` matching language scope below
3. **If job creation fails** (API error) → find any `IN_PROGRESS` job for the same feature, add strings there, note the fallback in output — **do not authorize yet**

> ⚠️ **Locale check when reusing an existing job**: if the existing job has more locales than the task requires (e.g. 47 locales but `is_uou = false` needs only 21), note this. Authorization in Phase 6.5 will use `locale_workflows` to restrict to the correct 21 locales with the selected workflow — do NOT call bare `smartling_authorize_job` without `locale_workflows`.

Language scope:
- `is_uou = false` → Account languages (21): `cs-CZ, da-DK, de-DE, es, fr-FR, hi-IN, id-ID, it-IT, ja-JP, ko-KR, nl, no-NO, pl-PL, pt, ru-RU, sv-SE, th-TH, tr-TR, uk-UA, vi-VN, zh-TW`
- `is_uou = true` → all 36 locales

Smartling strings URL (for Monday SUBCOL_TASK_LINK):
```
https://dashboard.smartling.com/app/projects/{project_id}/strings/?limit=25&offset=0&sourceOnly=false&tagsFilter.keywords[]={url_encoded_tag}&tagsFilter.mode=OR_MODE&status=IN_PROGRESS
```

## Phase 3: Screenshots

- `"Screenshot in Smartling"` → skip entirely ✅
- Figma URL present → run `babel-figma-screenshots` skill
- Neither → check Babel for existing `imageContextUrl`; if missing, note as pending in final summary

## Phase 4: Monday item

### Fixed parent item
**Do NOT create a new main item.** All on-call tasks are created as subitems under the fixed parent item:

```
Parent item ID: 12180072682  (board 9991668759)
```

Skip group lookup and main item creation entirely.

### Related product label (subitem)

Map the `company` field from the Slack message to a `related_product_label`:

| Company (Slack message) | Label |
|---|---|
| `Online Programs` | `"Online Programs"` |
| `Premium`, `BILL`, `DOM`, `PREM` | `"Premium"` |
| `eComm`, `ECP` | `"eccom"` |
| Any other | Use the company name as-is |

Always set `dropdown_mkvqg648` with `create_labels_if_missing: true`. If the company name doesn't match any known label, the raw company name becomes the label (Monday will create it).

### Create subitem
```graphql
mutation { create_subitem(parent_item_id: 12180072682, item_name: "{task_name}") { id board { id } } }
```

**Call 1 — all columns except ETA (left-to-right):**
1. `color_mkvqvvbb` → `{"label": "MTPE"}`
2. `dropdown_mkvqg648` → `{"labels": ["{related_product_label}"]}` with `create_labels_if_missing: true`
3. `numeric_mkvq4h0s` → wordcount
4. `link_mkvq6z0h` → `{"url": "{smartling_strings_url}", "text": "Smartling"}`
5. `multiple_person_mkzdq7y4` → `{"personsAndTeams": [{"id": 14828021, "kind": "person"}]}`
6. `color_mkvqrkfy` → `{"label": "Account + Viewer"}` only if `is_uou = true`
7. `link_mkxf9rz2` → `{"url": "{slack_url}", "text": "Slack"}` — Slack message URL at subitem level

**Call 2 — ETA only (always last):**
- wordcount ≤ 80 → `date0 = {"date": "YYYY-MM-DD"}`
- wordcount > 80 → `color_mkyf691e = {"label": "Ready for ETA"}`

### ETA calculation
Work week: Sunday–Thursday. Skip Fridays, Saturdays, and Israeli public holidays.

- `is_urgent = true` → today + 2 working days; set `color_mkvq6t6 = {"label": "URGENT"}`
- `is_urgent = false`, Israel time < 14:00 → today + 2 working days
- `is_urgent = false`, Israel time ≥ 14:00 → today + 3 working days

**Israeli public holidays — fetch dynamically:**
```
GET https://www.hebcal.com/hebcal?v=1&cfg=json&year={YEAR}&c=off&i=on&lg=s&maj=on
```
Count as non-working any item where `category="holiday"`, `subcat="major"`, title does NOT contain `(CH''M)` (Chol HaMoed), and does NOT start with `Erev`.

### GA artifact column
Set `dropdown_mkzcwa5s` on the **parent item** (board `9991668759`, item `12180072682`) using the short artifact name.
Always use `create_labels_if_missing: true` — if the label doesn't exist in the dropdown yet, it will be created automatically.

```graphql
mutation {
  change_column_value(
    board_id: 9991668759,
    item_id: 12180072682,
    column_id: "dropdown_mkzcwa5s",
    value: "{\"labels\": [\"{short_artifact_name}\"]}",
    create_labels_if_missing: true
  ) { id }
}
```

## Phase 5: Content scoring

Invoke the `content-scoring-framework` skill with:
- `company_area` = company name from Slack message
- `strings[]` = the strings resolved in Phase 1
- `task_summary` = task name + any business context

The skill returns a `final_score` (1.0–3.0) and a color:

| Score | Color | Action |
|---|---|---|
| 1.00–1.51 | 🟢 Green | LLM GREEN workflow |
| 1.52–2.50 | 🟡 Yellow | LLM YELLOW workflow |
| 2.51–3.00 | 🔴 Red | Project default (human translation) |

Pass `score_color` to Phase 6.5.

## Phase 6.5: Post-auth Smartling actions

### Step 1 — Find LLM workflow UIDs (Green and Yellow only)

```
smartling_list_workflows(project_id, keyword: "LLM")
```

- GREEN workflow: name contains "LLM" and "GREEN" → UID `972739bc38e4` (shared across projects)
- YELLOW workflow: name contains "LLM" and "YELLOW" → UID `0d48ce8988bf` (shared across projects)

Skip this step if score is Red.

### Step 2 — Authorize the job with the selected workflow

Build a `locale_workflows[]` array mapping **every target locale** for this task (21 if `is_uou = false`, 36 if `is_uou = true`) to the selected workflow UID:

```json
locale_workflows: [
  { "target_locale_id": "cs-CZ", "workflow_uid": "<selected_uid>" },
  { "target_locale_id": "da-DK", "workflow_uid": "<selected_uid>" },
  ...all 21 (or 36) locales...
]
```

Call:
```
smartling_authorize_job(
  project_id = project_id,
  job_uid = job_uid,
  locale_workflows = <array above>
)
```

> **Always pass `locale_workflows`** — never call bare `smartling_authorize_job` without it. This ensures authorization is scoped to the correct 21 (or 36) locales even when reusing a job that has more locales.

> **If `locale_workflows` call fails** (some projects reject it on IN_PROGRESS jobs): fall back to bare `smartling_authorize_job` without arguments, note the fallback in the output, and warn that all job locales may be authorized.

For Red score: skip authorization entirely — leave the job in AWAITING_AUTHORIZATION.

### Step 3 — Sync Babel (Green and Yellow only)

Resolve the Babel project ID from the `Babel project` field in the Slack message:
1. If it says **"In Dev center"** → skip Babel sync entirely
2. Otherwise extract project ID from the Babel URL → call `babel__sync_project(projectId)`

This sync is async — no need to wait.

### Step 4 — Update Monday score color column (all scores)

Always set `color_mm3qayc2` on the subitem — for every score:

```graphql
mutation {
  change_column_value(board_id: 9991673115, item_id: {monday_subitem_id},
    column_id: "color_mm3qayc2",
    value: "{\"label\": \"Green\"}") { id }   # or "Yellow" or "Red"
}
```

Use `mcp__Webrix__monday__all_monday_api` for this call.

### Step 5 — Green score: set Task Status = Done

**Only when score = Green**, set on the subitem:

```graphql
change_column_value(board_id: 9991673115, item_id: {subitem_id},
  column_id: "color_mkyf691e", value: "{\"label\": \"Done\"}")
```

### Phase 6.5 report line

```
Phase 6.5 — Post-auth:
✓ Re-authorized with LLM GREEN workflow (21 locales)   ← Green
✓ Babel sync triggered
✓ Monday score color → Green
✓ Task Status → Done

✓ Re-authorized with LLM YELLOW workflow (21 locales)  ← Yellow
✓ Babel sync triggered
✓ Monday score color → Yellow

Post-auth: none (Red → human translation)              ← Red
✓ Monday score color → Red
```

## Phase 7: Reply to Slack thread

After Phase 6.5 is complete, reply to the original Slack thread using `mcp__Webrix__slack__reply_to_thread`:

```
Here is the task: https://wix.monday.com/boards/9991668759/pulses/{item_id}. ETA is {ETA_date} 🟢
```

Use the channel ID and thread timestamp from the original message URL.

---

## Output

```
## On-Call Localization — Done

**Task:** [task_name]
**Company:** [company]
**Strings:** [N] found, wordcount: [W] words

**Smartling:**
  Job: [job_name] ([job_uid]) — [created / added to existing IN_PROGRESS]
  Strings URL: [url]

**Monday:**
  Item: [name] → https://wix.monday.com/boards/9991668759/pulses/[item_id]
  Subitem: [name] (ETA: [date] / Ready for ETA)
  Slack link: set in Jira column ✓
  GA artifact: [name] (label created if new)
  Score color: [Green / Yellow / Red]

Phases:
  ✓ 1. Strings resolved ([N] found, [K] not found)
  [✓/⚠] 2. Smartling job [created / reused / failed + fallback used] — pending auth
  [✓/—] 3. Screenshots [in Smartling / uploaded / pending]
  ✓ 4. Monday item & subitem created (ETA: [date])
  ✓ 5. Content score: [X.X] → [Green / Yellow / Red]
  ✓ 6.5. [Re-authorized with LLM GREEN/YELLOW / skipped (Red)] · [Babel sync triggered / skipped] · Monday score color → [color]
  ✓ 7. Slack thread replied with Monday URL + ETA
```

## Rules

- Always use `all_monday_api` GraphQL for Monday mutations — column values as JSON strings
- **Never authorize in Phase 2** — always defer authorization to Phase 6.5 after content scoring
- **Always pass `locale_workflows` to `smartling_authorize_job`** — never bare-authorize without it; this scopes authorization to exactly 21 (or 36) locales. If `locale_workflows` fails, fall back to bare authorize and warn.
- When job creation fails → add to existing IN_PROGRESS job for same feature (do not block the workflow); note locale count mismatch if applicable
- Always set `dropdown_mkvqg648` on the subitem — map company name to label using the table above; use `create_labels_if_missing: true`
- Always put the Slack message URL in `COL_JIRA` (`link_mkvjmysa`) with text `"Slack"` — there is no Jira ticket
- Use company name in `COL_MORE_INFO` as stream label
- ETA on main item = same date as subitem ETA (only when wordcount ≤ 80)
- Always set `color_mm3qayc2` on the subitem (Phase 6.5) for every score — Green, Yellow, or Red
- Babel sync: skip if "In Dev center"; trigger for Green and Yellow scores
