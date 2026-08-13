---
name: localization-slack-on-call
description: Use when a Slack on-call channel message arrives containing a structured localization request with fields like Task, Company, Babel project, Tag/List of keys, Urgency, Viewer, including Developer Center, Dealer, and Email/Automated Emails tasks. Scores resolved Smartling strings only; never creates Babel keys or posts Slack summaries.
---

# Localization Slack On-Call

Full end-to-end workflow for on-call channel localization requests. Parses the Slack bot message, resolves strings in Smartling, creates/reuses a job, and creates a Monday item + subitem.

## Hard stops

- Email/Automated Emails, Developer Center/Dev Center, and Dealer tasks do not have source keys in Babel. Never add, create, upload, sync, or infer Babel keys for these task types. Use Smartling-only resolution. If a request or artifact appears to require Babel for one of these task types, stop and report the conflict instead of continuing.
- If a Slack payload provides a Smartling file name, component ID, app ID, tag, key list, or filtered Smartling URL, resolve that exact source scope. If the exact Smartling scope does not resolve, stop and report the unresolved name/scope. Do not continue with a fuzzy match, nearest file, renamed-looking file, similar content, similar date, or manually inferred substitute unless the user explicitly confirms that replacement.
- Do not post an end-of-flow summary, Smartling/Monday recap, or “done” message in Slack.

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

---

## Output

```
## Content Score — [task_name]

**Strings:** [N] found, wordcount: [W] words
**Score:** [X.XX] → 🟢 Green / 🟡 Yellow / 🔴 Red

| Dimension | Weight | Score | Weighted |
|---|---|---|---|
| Company | 25% | [X] | [X.XX] |
| Impact | 25% | [X] | [X.XX] |
| Complexity | 50% | [X] | [X.XX] |
| **Total** | | | **[X.XX]** |

**Reasoning:** [brief explanation of each dimension score]

**Recommendation:** [Green → LLM GREEN workflow / Yellow → LLM YELLOW workflow / Red → Human Translation]
```

## Rules

- **Do NOT create or update any Monday item or subitem**
- **Do NOT reply to the Slack thread**
- **Do NOT trigger Babel sync**
- **Do NOT create, upload, sync, or infer Babel keys. Email/Automated Emails, Developer Center/Dev Center, and Dealer tasks are Smartling-only/no-Babel.**
- **If an exact Smartling name/scope does not resolve, stop and report it instead of choosing a substitute.**
- **Do NOT authorize the Smartling job**
- Stop after Phase 5 — output only the content score table and recommendation
