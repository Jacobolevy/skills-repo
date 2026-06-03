---
name: localization-workflow
description: Main orchestrator for the end-to-end localization workflow. Given a Jira ticket URL, a list of keys, or pasted Slack text — extracts keys and metadata, tags strings in Smartling, uploads Figma screenshots to Babel, creates a Smartling job, creates the Monday item and subitem, scores the content, then authorizes with the correct LLM workflow (GREEN/YELLOW/default). Use this as the single entry point for starting a new localization task.
---

# Localization Workflow

Run the complete end-to-end localization workflow from a single input. This skill orchestrates all other localization skills in sequence.

## What This Does (in order)

```
1. Parse input → detect type → extract keys + metadata
2. Tag strings in Smartling         (/smartling-tag-manager)
2.5 Identify GA artifact(s) from Smartling file paths (DevEx)
3. Upload screenshots to Babel      (/babel-figma-screenshots or Jira images or Snagit)
4. Create Smartling job + add strings (/smartling-job-manager) ← do NOT authorize yet
5. Create Monday item + subitem      (/monday-localizer) ← includes GA artifact column
6. Score the task                    (/content-scoring-framework) → set color label on Monday subitem
6.5 Authorize job + post-auth actions (/smartling-post-auth) → authorize with GREEN/YELLOW/default workflow, Babel sync, Monday Done
7. [PAUSED] Add pilot tracking row to Google Sheet — skip for now
8. [PAUSED] Post pilot update on Monday subitem — skip for now
9. Show final summary report
```

**Phases 7–8 are currently paused. Skip them — go straight to the final summary after Phase 6.5.**

> **Why authorization is in Phase 6.5 and not Phase 4:** The Smartling workflow selection (LLM GREEN / LLM YELLOW / human) depends on the content score, which is only known after Phase 6. Smartling does not allow changing the workflow on an IN_PROGRESS job — so we must delay authorization until the score is known.

## Inputs

The user provides **one** of:

- **Jira URL** — e.g. `https://jira.wixpress.com/browse/TRANS-1234`
- **Key list** — dot-separated keys pasted directly in the message, one per line or comma-separated
- **Slack text** — a copied Slack message containing keys and context mixed together

Optionally, the user may also provide:
- A Smartling tag name (default: derive from feature name, e.g. `billing-upgrade-q3`)
- A Smartling project name or ID
- A Monday "related product" value

## Phase 1: Parse input and extract metadata

### Detect input type

| Condition | Type |
|---|---|
| Contains `jira.wixpress.com/browse/` or matches `[A-Z]+-\d+` | Jira ticket |
| Contains `wix.slack.com/archives/` OR is a structured Slack bot message with fields **Task:**, **Company:**, **Babel project:** | Slack on-call |
| Lines/items match the localization key pattern (two+ dot-separated segments) | Key list |
| Free-form text (doesn't match above) | Slack text |

### If Slack on-call message → handle inline

Parse the structured fields from the Slack bot message:

| Field | Variable |
|---|---|
| **Task** | `task_name` → Monday item name, Smartling job name |
| **Company** | `company` → Monday group + stream label |
| **Babel project** | `babel_project_url` → used to resolve Smartling project ID |
| **Tag / List of keys** | See detection rules below |
| **Key doc** | Google Sheet URL with key names |
| **Requestor** | Record only |
| **Figma/Screenshots** | `"Screenshot in Smartling"` → skip Phase 3; or Figma URL |
| **Urgency** | Normal 🟢 → `is_urgent = false`; Urgent / 🔴 / "ASAP" → `is_urgent = true` |
| **Viewer (UoU)** | Yes → `is_uou = true`; No → `is_uou = false` |
| **Slack message URL** | `slack_url` → goes in `COL_JIRA` on Monday item (replaces Jira link) |

**Tag vs Keys detection** (field "Tag / List of keys"):
- Value matches `[a-z0-9_]+\.[a-z0-9_.]+` pattern (dot-separated segments) → list of keys
- Value is a Google Sheets URL → key doc (read "Key" column via `google-workspace__get-sheet-values`)
- Otherwise → Smartling tag (search by `tag_filter`)

**Resolve Smartling project ID via Babel** (no Jira space available):
1. If `babel_project_url` says **"In Dev center"** (or "Dev Center") → Smartling project is always `c48d07e39`. Keys are NOT in Babel — skip all Babel lookups for this task.
2. If `babel_project_url` is a real URL → extract project ID from URL → `babel__get_project` → `configuration.translatorProjectId`
3. If no Babel URL → `babel__search_keys` with one key (exact name) → Babel `projectId` → `babel__get_project` → `configuration.translatorProjectId`

**On-call does NOT transition a Jira ticket.** Skip that step entirely.

**On-call Monday differences** (applied in Phase 5):
- `jira_url` = null
- Pass `slack_url` to `monday-localizer` as the Jira column value (text: `"Slack"`)
- Group: look up by `company` name in board schema; fallback to `group_mkxhtynn`
- Stream label (`COL_MORE_INFO`): use `company` name

**After Phase 5 (on-call only) — reply to Slack thread:**
Reply to the original Slack thread using `mcp__Webrix__slack__reply_to_thread`:
```
Here is the task: https://wix.monday.com/boards/9991668759/pulses/{item_id}. ETA is {ETA_date} 🟢
```
Use the channel ID and thread timestamp from the original Slack message URL.

**Skip Phases 6, 7, 8** for on-call requests. Go directly to Final Summary after Phase 5 + Slack reply.

Then continue to Phase 2 with the resolved keys, hashcodes, project ID, and metadata.

### If Jira ticket → use `jira-reader`

Invoke the `jira-reader` skill with the Jira URL or issue key. It will return:
- `keys[]`
- `figma_url`
- `feature_toggle`
- `feature_name` (from ticket title)

Then extract the **Jira space** from the issue key (e.g. `BILL-123` → `BILL`) and resolve:

**Related product, stream, and Smartling project ID:**

| Jira space | Related product | Stream | Smartling project ID (primary) |
|---|---|---|---|
| `BILL` | Premium | `"Billing"` | `b3eef828d` |
| `DOM` | Premium | `"Domains"` | `b3eef828d` |
| `PREM` + Business Email | Premium | `"Google Workspace"` | `b3eef828d` |
| `PREM` + Plans | Premium | `"Plans"` | `25c8740e5` |
| `ECP` | eComm | `"eComm"` | `6bc9e740e` |

For `PREM` disambiguation: if the title/description mentions "Business Email", "BE", "Google Voice", or "Google Workspace" → Google Workspace / `b3eef828d`. Otherwise → Plans / `25c8740e5`.

**Fallback — Babel project lookup:** If keys are not found in the primary project, use Babel to find the correct Smartling project:
1. Call `babel__search_keys` with `name = <one_unresolved_key>` (exact)
2. Take the `projectId` from the result → call `babel__get_project` → read `configuration.translatorProjectId`
3. Re-search all unresolved keys in that Smartling project
4. Tag and create jobs in EACH project separately — keys found in different projects cannot share a job

**Special project routing:**

| Project name | Project ID | Use when |
|---|---|---|
| Wix OneApp | `00ed380af` | Keys from `wix-one-app-ecom-platform` repo or mobile-prefixed namespaces |

**Wix OneApp rules (project `00ed380af`):**
- Authorize the Smartling job for **ALL 27 project locales** (not just the 21 Account languages) — call `smartling_get_project` to get the full locale list, then create the job with all of them
- In Monday, set `SUBCOL_LANGUAGES` (`color_mkvqrkfy`) = `"Account + Mobile"` on the OneApp subitem
- Authorization happens in Phase 6.5 — if `smartling_authorize_job` fails on the first attempt, retry immediately; the job is in AWAITING_AUTHORIZATION so retries are safe

**Split-project tickets (eComm + OneApp):**

When a ticket has keys in BOTH `6bc9e740e` (eComm) AND `00ed380af` (Wix OneApp), create **two separate Smartling jobs** AND **two subitems** — one per project:

| Subitem | Project | Languages column | Wordcount |
|---|---|---|---|
| Subitem A (eComm) | `6bc9e740e` | not set | eComm keys only |
| Subitem B (OneApp) | `00ed380af` | `"Account + Mobile"` | OneApp keys only |

- The **main item** wordcount = sum of both
- Each subitem's `SUBCOL_TASK_LINK` points to its own project's Smartling strings URL (use the correct `project_id` in the URL)
- The same tag name is used in both projects

### If key list → parse directly

Extract all strings matching the localization key pattern: two or more dot-separated segments where each is camelCase or kebab-case.

Prompt the user for any missing metadata:
- Do you have a Figma URL for this feature?
- What's the feature/sprint name (for the Monday item and Smartling job)?
- Is there a feature toggle?

Ask all missing questions at once — do not ping the user multiple times.

### If Slack text → extract heuristically

Scan the text for:
- Keys: same pattern as above
- Figma links: `figma.com/design/` or `figma.com/file/`
- Feature toggle: `specs.`, `spec:`, `toggle:`
- Feature name: first meaningful noun phrase or ask the user

If fewer than 3 keys are found or no keys at all, show what was extracted and ask the user to confirm before continuing.

### Phase 1 summary (informational — no confirmation needed)

After extraction, show a brief summary and immediately proceed to Phase 2 without waiting:

```
## Starting localization workflow — [feature name]

**Input type:** [Jira / Key list / Slack]
**Jira space:** [BILL / DOM / PREM / ECP or "n/a"]
**Feature name:** [name]
**Stream:** [Billing / Domains / Plans / Google Workspace / eComm]
**Related product:** [Premium / eComm]
**Smartling project:** [project ID]

**Keys found:** [N total]
  BM keys ([N]): [list]
  Viewer keys ([N]): [list]   ← omit section if none
  Unscoped keys ([N]): [list]  ← treated as BM

**Figma URL:** [URL or "none"]
**Feature toggle:** [name or "none"]
**Smartling tag:** [proposed tag name]
**Smartling job(s):**
  - [proposed job name] (BM, 21 langs)
  - [proposed job name - Viewer] (Viewer, 36 langs)   ← only if mixed

Running phases 2–5 automatically…
```

**Do not wait for user input.** Proceed directly to Phase 2 after displaying this block.

**If a Jira URL is available**, immediately transition the ticket to "In Progress" using the Jira MCP `transition-issue` tool (get available transitions first, pick the "In Progress" one). Do this silently before Phase 2 — no need to ask the user.

---

## Tag and job naming rules

### Tag name
- Human readable text — NO hyphens, NO kebab-case
- Task-level: describes this specific task, not the feature broadly
- Examples: `"BE Upsell to Yearly"`, `"Delivery Now"`, `"Domain Results Page"`
- **Before proposing a tag: search Smartling for existing tags on this feature** using `smartling_search_strings` or list recent jobs — if a matching tag exists, propose reusing it
- If UoU/Viewer detected: add `"viewer"` as a **second tag** alongside the task tag

### UoU / Viewer detection — per key, not per ticket

Keys in a Jira ticket can have **mixed scopes**. Look at the label next to each key in the description:

| Label in Jira | Scope | Languages |
|---|---|---|
| `BM`, `Business Manager`, `Merchant`, no label | Account only | 21 languages |
| `Viewer`, `UoU`, `User of Users`, `UoU-facing` | All locales | 36 languages |

**Detection rules:**
- If ALL keys are Viewer → `is_uou = true` for the whole run (single job, 36 langs)
- If ALL keys are BM / no label → `is_uou = false` (single job, 21 langs)
- If **MIXED** (some BM, some Viewer) → **split into two groups** (see Mixed scope below)

Also look for UoU/Viewer signals in: Jira title, description free text, or user message.

**Important non-signal:** phrases like `user-facing`, `customer-facing`, `public-facing`, or similar do **not** mean Viewer/UoU by themselves. Only explicit Viewer/UoU labels or equivalent wording should trigger Viewer scope. If the ticket only says `user-facing` and provides no Viewer/UoU label, treat it as BM/account scope by default.

### Mixed scope — two jobs, two subitems

When a ticket has both BM and Viewer keys:

1. **One tag** — apply the same tag to ALL keys regardless of scope
2. **Two Smartling jobs:**
   - Job A: BM keys only → authorized for Account languages (21 langs), job name without "Viewer"
   - Job B: Viewer keys only → authorized for all 36 languages, job name with "Viewer" suffix (e.g. `"Gift Cards - Viewer"`)
3. **One Monday item**, **two subitems:**
   - Subitem A: linked to Job A, `SUBCOL_LANGUAGES` not set
   - Subitem B: linked to Job B, `SUBCOL_LANGUAGES` = `"Account + Viewer"`
4. **Wordcount** on the main Monday item = total of both jobs combined

Present this split clearly in the Phase 1 summary block.

### Job name
- Feature-level, broader than the tag: `"BE - Business purchase flow"`, `"Gift Cards - Viewer"`
- **Search for existing Smartling jobs on this feature first** (`smartling_list_jobs`) — reuse an old job if it covers the same feature, even if created years ago
- If no suitable job exists, propose a new name: product prefix + feature name (e.g. `"BE - Business purchase flow"`)
- For Viewer jobs: always append `"- Viewer"` to the job name (e.g. `"Gift Cards - Viewer"`)
- Job name is less critical than the tag — when in doubt, ask the user

---

## Phase 2: Tag strings in Smartling

Invoke the `smartling-tag-manager` skill with:
- `keys[]` = **ALL keys** regardless of scope (BM + Viewer)
- `tag_names[]` = confirmed tag name + `"viewer"` if any Viewer keys exist
- `project_id` = resolved Smartling project (primary; fall back to generic search if not found)

**Important:** The same tag is applied to all keys. Scope split happens in Phase 4 (jobs), not here.

Collect the output:
- `hashcodes_bm[]` — hashcodes for BM keys (if mixed scope)
- `hashcodes_viewer[]` — hashcodes for Viewer keys (if mixed scope)
- `hashcodes_all[]` — all hashcodes combined (if single scope)
- Count of found / not found keys
- Tag confirmation URL
- **`wordcount`** — sum of `totalWordCount` from all `smartling_search_strings` responses. This value is passed to Phase 4 and Phase 5. It is the source of truth for wordcount — the Smartling job API does not reliably return it.

Report phase result inline:
```
✓ Phase 2 done — [N] strings tagged with "[tag]". [K] keys not found. Wordcount: [W] words.
```

If more than 20% of keys were not found, pause and ask the user whether to continue or investigate.

---

## Phase 2.5: Identify GA Artifact(s) from Smartling File Paths

Use the `fileUri` field from the `smartling_search_strings` results (collected in Phase 2) to identify the DevEx artifact(s) that own these strings. This artifact name will be stored in the Monday GA column.

### Step 1: Extract unique file paths

From all `smartling_search_strings` results, collect all unique `fileUri` values. A `fileUri` looks like:

```
wix-private/billing-monorepo/packages/billing-upgrade/src/assets/locale/messages_en.json
```

Group them by repo (`<org>/<repo>` segment), since all files in the same repo will resolve to the same set of artifacts.

### Step 2: Derive search parameters per repo

For each unique file path:

- **repoUrl_candidate**: `"git@github.com:" + <org>/<repo> + ".git"`
  Example: `git@github.com:wix-private/billing-monorepo.git`

- **pathInRepo_candidate**: strip the `<org>/<repo>/` prefix
  Example: `packages/billing-upgrade/src/assets/locale/messages_en.json`

- **projectPath_candidate**: take up to `packages/<package-name>` (stop before `src/`, `assets/`, or the filename)
  Example: `packages/billing-upgrade`

### Step 3: Call `devex__search_projects` (once per unique projectPath)

```json
{
  "search": {
    "search": { "expression": "packages/billing-upgrade" },
    "cursorPaging": { "limit": 50 }
  }
}
```

**Never call `devex__get_devex_fqdn`.** Each projectPath may be called at most once.

### Step 4: Filter results client-side

Keep only results where:
- `project.repoUrl === repoUrl_candidate` **AND**
- `project.pathInRepo === projectPath_candidate` OR `pathInRepo_candidate starts with project.pathInRepo + "/"`

### Step 5: Select artifact

| Result | Action |
|---|---|
| Exactly one project | Select automatically. Use its `projectName` as the artifact. |
| Multiple projects | Ask the user to pick from the list. |
| No projects | Try keyword fallback: search by last directory segment (e.g. `billing-upgrade`). If still ambiguous, ask the user for the artifact name directly. |

### Step 6: Handle multiple files → multiple artifacts

If keys span multiple repos (uncommon but possible), you may end up with more than one artifact. Collect all of them as a list. Monday's GA column will receive a comma-separated string of artifact names.

### Output

Collect `ga_artifacts[]` — a list of full artifact names (e.g. `["com.wixpress.billing-upgrade"]`).

Report phase result inline:
```
✓ Phase 2.5 done — GA artifact(s) identified: com.wixpress.billing-upgrade
```

If artifact cannot be determined, report:
```
⚠ Phase 2.5 — Could not identify GA artifact from file paths. Monday GA column will be left empty.
```
and continue without blocking.

---

## Phase 3: Upload screenshots to Babel

Work through these sources in order — stop as soon as all keys have context:

### Priority 1: Figma URL

If `figma_url` is available → invoke `babel-figma-screenshots` skill with:
- `key_names[]` from Phase 1
- `figma_file` = `figma_url`

```
✓ Phase 3 done — [N] screenshots uploaded, [K] already had screenshots, [M] not found.
```

### Priority 2: Jira images (when no Figma URL)

If `jira_images[]` was returned by `jira-reader` (attachments or inline images from the ticket):

1. For each image URL in `jira_images[]`, download it to `/tmp/jira_img_<n>.png`:
   ```bash
   curl -s -L -H "Authorization: Bearer $(cat ~/.jira_token 2>/dev/null || echo '')" \
     "<attachment_url>" -o /tmp/jira_img_1.png
   ```
   If the token is not available, try without auth (some Jira instances allow public access). If download fails → skip this image and continue.
2. Read/view each downloaded image to confirm it shows the relevant UI (visual QA gate — do not upload unrelated screenshots)
3. For each key missing `imageContextUrl` in Babel, upload the matching image via `babel__upload_key_image_context`
4. If multiple keys share the same UI context, use the same image for all of them

```
✓ Phase 3 done — [N] screenshots from Jira ticket uploaded.
```

### Priority 3: Babel existing context

Call `babel__search_keys` for each key and check `imageContextUrl`:

- All keys already have context → report and continue
- Some keys missing → proceed to Priority 4

### Priority 4: Snagit automatic lookup

Snagit saves captures as `.snagx` files (zip archives) in `~/Pictures/Snagit/`.

1. `ls -lt ~/Pictures/Snagit/*.snagx | head -10`
2. For the most recent files: `cd /tmp && unzip -o ~/Pictures/Snagit/<file>.snagx -d snagit_tmp`
3. Read/view the PNG at `/tmp/snagit_tmp/<uuid>.png` — confirm it matches the feature
4. Upload to Babel for missing keys via `babel__upload_key_image_context`

### No context found

If keys don't exist in Babel at all (mobile/native keys not integrated) → skip silently.

If no image source worked, include in final summary:
```
⚠ Phase 3 pending — keys with no visual context in Babel:
  - [key name]
To complete: take a Snagit screenshot of the UI and I will upload it automatically.
```

**If the user shares image file paths in the same message** → upload immediately, skip all other sources.

---

## Phase 4: Create Smartling job(s) and add strings

> **Do NOT authorize the job in this phase.** Authorization happens in Phase 6.5 after scoring, using the correct LLM workflow (GREEN/YELLOW/default). Smartling does not allow changing the workflow once a job is IN_PROGRESS — so authorization must be deferred until the score is known.

### ⚠️ Account Languages — exact list (BM / non-UoU)

**ALWAYS use exactly these 21 locale IDs. Never substitute or guess.**

`cs-CZ, da-DK, de-DE, es, fr-FR, hi-IN, id-ID, it-IT, ja-JP, ko-KR, nl, no-NO, pl-PL, pt, ru-RU, sv-SE, th-TH, tr-TR, uk-UA, vi-VN, zh-TW`

❌ Do NOT include: `ar`, `fi-FI`, `he-IL`, `hu-HU` — these are NOT account languages.

### ⚠️ If you need to fix job locales — recreate the job

Never patch a job by calling `remove_strings_from_job` + `add_strings_to_job` with partial `target_locale_ids`. This leaves the job in an inconsistent state. Instead:
1. Cancel the wrong job
2. Create a new job with the correct `target_locale_ids`
3. Add all strings
4. (Authorization happens in Phase 6.5)

### Single scope (all BM or all Viewer)

Invoke `smartling-job-manager` once with:
- `project_id` = Smartling project
- `job_name` = feature name
- `hashcodes[]` = all hashcodes from Phase 2
- `wordcount` = `wordcount` from Phase 2
- `is_uou` = `true` if all Viewer, `false` if all BM

### Mixed scope (BM + Viewer keys)

Invoke `smartling-job-manager` **twice**, in sequence:

**Job A — BM:**
- `job_name` = feature name (e.g. `"Gift Cards"`)
- `hashcodes[]` = `hashcodes_bm[]` from Phase 2
- `wordcount` = wordcount for BM keys only (sum of `totalWordCount` for BM hashcodes)
- `is_uou` = `false`

**Job B — Viewer:**
- `job_name` = feature name + `"- Viewer"` (e.g. `"Gift Cards - Viewer"`)
- `hashcodes[]` = `hashcodes_viewer[]` from Phase 2
- `wordcount` = wordcount for Viewer keys only (sum of `totalWordCount` for Viewer hashcodes)
- `is_uou` = `true`

Collect from each job: `job_url`. Wordcount comes from Phase 2, not the job API.

After Phase 4, construct the **Smartling strings URL** for Monday using the tag from Phase 2 and project_id:

```
https://dashboard.smartling.com/app/projects/{project_id}/strings/?limit=25&offset=0&sourceOnly=false&tagsFilter.keywords[]={url_encoded_tag}&tagsFilter.mode=OR_MODE&status=IN_PROGRESS
```

URL-encode the tag name (spaces → `%20`, underscores stay as `_`). This is the URL that goes into Monday as the task link — it shows all strings for this task filtered to IN_PROGRESS. There is only one tag per run, so the same URL is used for both BM and Viewer subitems.

Report phase result inline:
```
✓ Phase 4 done — 2 jobs created (pending authorization in Phase 6.5).
   Job A (BM): "[name]" — [N] words → [URL]
   Job B (Viewer): "[name] - Viewer" — [N] words → [URL]
   Total wordcount: [N+M] words
   Smartling strings URL: [constructed URL]
```

### ⚠️ All strings PUBLISHED — skip Phase 5

After adding strings, check the resulting string statuses in the job:

- If **all strings are `PUBLISHED`** (already translated in all target locales) → authorization will fail or is unnecessary. **Do NOT create a Monday item or subitem.** Instead, report in chat:
  > "All [N] strings are already `PUBLISHED` — fully translated in all target locales. This is likely a deployment/configuration issue, not a translation gap. No Monday item created."
  Then stop the workflow.

- If **at least one string is in `AWAITING_AUTHORIZATION`** → proceed normally to Phase 5.

---

### ⚠️ ETA calculation — always check Israel time first

**Before calculating any ETA**, run this Bash command to get the real current time in Israel:

```bash
TZ="Asia/Jerusalem" date
```

Use the output to determine today's date and current time. Do NOT assume or guess the time — always verify with this command.

**ETA rules:**
- Work week: Sunday–Thursday. Skip Friday, Saturday, and Israeli public holidays.
- `is_urgent = true` OR current time < 14:00 Israel → ETA = today + 2 working days
- Current time ≥ 14:00 Israel (and not urgent) → ETA = today + 3 working days

**Israeli public holidays 2026 (known — do not skip to API if these apply):**
- Shavuot: May 21 (erev, skip) + May 22 (chag, skip) → next working day = Sun May 24
- Check Hebcal API for other dates as needed

---

## Phase 5: Create Monday item and subitem(s)

---
# 🚨🚨🚨 MANDATORY — NEVER SKIP THIS 🚨🚨🚨

## EVERY subitem MUST have `dropdown_mkvqg648` (Related product) set. NO EXCEPTIONS.

**This column is REQUIRED on every single subitem, every single time. Forgetting it is not acceptable.**

| Company / Stream | Related product label |
|---|---|
| Premium (Billing, Domains, Plans, Google Workspace) | `"Premium"` |
| eComm / Online Stores | `"ecom - Platform"` |
| Online Programs | `"Online Programs"` |

If the company/stream is not in this table → ask the user for the correct label BEFORE creating the subitem.

## 🚨 eComm subitems ALSO require `multiple_person_mkxh72vw` = person `22720905`

**When `related_product = "ecom - Platform"` (eComm / Online Stores)**, set this additional column on every subitem:
```
"multiple_person_mkxh72vw": {"personsAndTeams": [{"id": 22720905, "kind": "person"}]}
```
This is separate from the LM person column. Do NOT omit it for eComm tasks.

Always use `create_labels_if_missing: true`.

# 🚨🚨🚨 END MANDATORY 🚨🚨🚨

---

### Single scope

Invoke `monday-localizer` with:
- `item_name` = feature name
- `subitem_name` = derived from item name (see monday-localizer naming rules)
- `smartling_strings_url` = constructed Smartling strings URL (same for all subitems)
- `figma_url`, `feature_toggle`, `related_product`, `jira_url` from Phase 1
- `wordcount` = from Phase 2 (the `total_wordcount` captured from `smartling_search_strings` responses)

### Split projects (keys in multiple Smartling projects)

When keys are found across **more than one Smartling project**, create one main item + **one subitem per project**:

**Main item:** total wordcount (all projects combined), ETA based on total.

**One subitem per project:**
- `subitem_name` = feature name (same name for all subitems)
- `smartling_strings_url` = URL with that project's `project_id` and the tag filter
- `wordcount` = wordcount for keys in that project only
- `SUBCOL_LANGUAGES` = `"Account + Mobile"` only if the project is Wix OneApp (`00ed380af`); otherwise not set
- `related_product`, `jira_url`, `person`, `type`, `ETA` = same on all subitems

This applies to any combination of projects — not just eComm + OneApp.

### Mixed scope

Invoke `monday-localizer` once for the main item + **two subitems**:

The main item is created once with total wordcount (BM + Viewer combined).

**Subitem A — BM:**
- `subitem_name` = item name (no suffix, or `"(Merchant)"` if context helps)
- `smartling_strings_url` = constructed Smartling strings URL
- `wordcount` = Job A wordcount
- `is_uou` = `false` → `SUBCOL_LANGUAGES` not set

**Subitem B — Viewer:**
- `subitem_name` = item name + `"(Viewer)"` or similar context
- `smartling_strings_url` = same constructed Smartling strings URL (same tag, same filter)
- `wordcount` = Job B wordcount
- `is_uou` = `true` → `SUBCOL_LANGUAGES` = `"Viewer Only"`

### Setting the GA artifact column

After `monday-localizer` creates the item, use `all_monday_api` GraphQL to set column `dropdown_mkzcwa5s` on board `9991668759` with the artifact name(s) from Phase 2.5.

Always use `create_labels_if_missing: true` — if the label doesn't exist in the dropdown yet, Monday will create it automatically. Never skip the GA column because the label is "missing".

If the dropdown already has a matching short label, prefer that existing label value exactly instead of creating a new full-name label.

```graphql
mutation {
  change_column_value(
    board_id: 9991668759,
    item_id: {item_id},
    column_id: "dropdown_mkzcwa5s",
    value: "{\"labels\": [\"{short_artifact_name}\"]}",
    create_labels_if_missing: true
  ) { id }
}
```

- If **artifact was not identified** (Phase 2.5 failed): skip this update and mention it in the final summary

The column value uses the **short artifact name** (without the `com.wixpress.` namespace prefix).

Mapping rule: strip `com.wixpress.` (and any other namespace prefix before the first meaningful segment) from the DevEx `projectName`.
- `com.wixpress.business-email-translations` → `business-email-translations`
- `com.wixpress.premium-purchase-plan-translations` → `premium-purchase-plan-translations`

Report phase result inline:
```
✓ Phase 5 done — Monday item created with 2 subitems.
   Item: [name] → [Monday URL]
   Subitem A (BM): [name]
   Subitem B (Viewer): [name (Viewer)]
   GA artifact column set: com.wixpress.billing-upgrade
```

---

## Phase 6: Score the task

Invoke the `content-scoring-framework` skill after Phase 5 using:
- company area inferred from the product/stream and repository/artifact
- task summary from the Jira title or input text
- representative string content from Smartling/Jira

For localization workflow tasks, prefer these company-area mappings unless stronger evidence points elsewhere:
- `ECP` / eComm dashboard and checkout settings flows → `Stores - ecom Platform`
- store viewer/shopfront tasks → `Stores - Online Shop`
- `BILL`, `DOM`, `PREM` → use the most specific matching area already inferred by the workflow, otherwise `Premium`

The score is informational. It does **not** change the localization workflow steps that already ran.

### Set score label on Monday subitem

After computing the score, set column `color_mm3qayc2` on the **subitem** (board `9991673115`) using `monday__all_monday_api`:

| Score range | Label |
|---|---|
| 1.00 – 1.51 | `Green` |
| 1.52 – 2.50 | `Yellow` |
| 2.51 – 3.00 | `Red` |

```graphql
mutation {
  change_column_value(board_id: 9991673115, item_id: {subitem_id},
    column_id: "color_mm3qayc2",
    value: "{\"label\": \"Green\"}") { id }
}
```

If there are two subitems (mixed scope or split project), set the label on **both**.

Report phase result inline:
```
✓ Phase 6 done — content score: [X.X / 3] → [Green/Yellow/Red]
   Company: [X.X] — [company area]
   Impact: [1/2/3] — [Low/Medium/High]
   Complexity: [1/2/3] — [Low/Medium/High]
```

---

## Phase 6.5: Authorize job + post-auth Smartling actions

Invoke the `smartling-post-auth` skill immediately after Phase 6, passing:
- `score_color` — from Phase 6 output (`Green` / `Yellow` / `Red`)
- `project_id` — Smartling project (from Phase 4; one per job if split-project)
- `job_uid` — from Phase 4 (one per job if split-project)
- `target_locales[]` — the locale IDs set on the job in Phase 4
- `monday_subitem_id` — from Phase 5 (one per subitem if two subitems)
- `babel_project_id` — from Phase 3 triage

**Quick reference — what this phase does:**

| Score | Actions |
|---|---|
| Green | Authorize with LLM GREEN workflow → Babel sync → Monday `color_mm3qayc2` = `Green` → `color_mkyf691e` = `Done` |
| Yellow | Authorize with LLM YELLOW workflow → Babel sync |
| Red | Authorize with project default (human translation) → nothing else |

The `is_uou` flag does not change what this phase does — it already determined locale count (21 vs 36) in Phase 4. Phase 6.5 applies the same Green/Yellow/Red rules regardless.

**On-call tasks:** Phase 6.5 applies normally — same Green/Yellow/Red rules as Jira tasks.

Report phase result inline (appended to Phase 6 block):
```
   Phase 6.5: ✓ Authorized (LLM GREEN) | ✓ Babel sync | ✓ Monday → Done
```
or:
```
   Phase 6.5: ✓ Authorized (LLM YELLOW) | ✓ Babel sync
```
or:
```
   Phase 6.5: ✓ Authorized (default) — Red → human translation
```

---

## Phase 7: Add pilot tracking row to Google Sheet

**Pilot scope: Premium tasks only.** If `related_product` is `"eComm"` (or any non-Premium product), skip Phases 7 and 8 entirely and proceed to the Final Summary.

After Phase 6, add the created Monday subitem to the pilot tracking sheet:

- Sheet URL: `https://docs.google.com/spreadsheets/d/1VosZTUt9mGIuyuB69NM30F1-rgyrIaaZh2NJKVuXFS4/edit?gid=0#gid=0`
- Read the header row first and match the existing worksheet structure before writing anything.
- For this pilot sheet, write **only columns `A-E`**. Do **not** populate columns `F-I` (or any later columns) with free text, explanations, URLs, or derived notes.

Write only these values:
- `A` = LM name
- `B` = Monday subitem link
- `C` = Related Product
- `D` = Business Impact
- `E` = Content Complexity

Strict value rules:
- Use the sheet's existing dropdown/label vocabulary exactly as it already appears in prior rows.
- Do **not** invent new values, combine multiple values into one cell, or add explanatory text.
- For `Related Product`, reuse an existing sheet value exactly, for example `Premium`, `Email Marketing`, `Forms`, `Automations`, or `ecom - Platform`, depending on the task.
- For `Business Impact`, use only the existing categorical value such as `Low`, `Medium`, or `High`.
- For `Content Complexity`, use only the existing categorical value such as `Low`, `Medium`, or `High`.
- If the correct label is unclear, inspect existing populated rows first and pick the exact existing label that matches best. If no safe exact match exists, stop and ask the user instead of inventing one.

If multiple rows could match the same task, prefer updating the existing row instead of creating a duplicate. Match by Monday subitem link first; if absent, match by feature name + current date.

Report phase result inline:
```
✓ Phase 7 done — pilot tracking sheet updated.
   Row: [new or updated]
   Monday item: [URL]
   Final score: [X.X / 3]
```

If the sheet is temporarily unreachable, do not block the workflow. Report it as a partial failure and include it in the final summary.

---

## Phase 8: Post standardized pilot update on the Monday subitem

After the sheet is updated, add the following exact message to the **Updates** section of the localization **subitem** created in Phase 5:

```text
@LLs T3
This task is part of a pilot program to improve how we work. After you finish the task, please fill out the short, 3-question feedback form. Please only mark the task as "Done" after you have submitted the form.
Your feedback is very important. It helps us work faster without hurting the quality or user experience. There are no right or wrong answers, so please share your honest thoughts.
Thank you!
```

Important:
- Post the update on the **subitem**, not the main item.
- Do **not** rely on plain-text `@LLs T3` to notify the group.
- Render the mention in the HTML body using Monday's team-mention attributes. The reliable pattern is:

```html
<a class="pulse-link"
   href="https://wix.monday.com/users/team/1234130"
   data-mention-type="Team"
   data-mention-id="1234130"
   target="_blank"
   rel="noopener noreferrer">@LLs T3</a>
```

- Replace `1234130` with the resolved team ID if it ever changes, but keep the same attribute structure.
- If you use `create_update` or `edit_update`, prefer this HTML mention pattern over plain-text `@LLs T3`. `mentions_list` may still be added for notification semantics, but the visible/rendered mention should come from the HTML anchor above.
- The phrase **`3-question feedback form`** must be a hyperlink to:
  `https://docs.google.com/forms/d/e/1FAIpQLSfDo9r-UEd2CIz6GjMBw_67o28YQ_eEB5wcJlqYhaDoWwp9PQ/viewform`
- When posting through the Monday API, use an HTML body so both the team mention and the form link render correctly.
- Do **not** leave the form URL as bare text in `text_body`; use a real `<a href="...">3-question feedback form</a>` hyperlink in the HTML body.
- Keep the visible body text exactly as shown above, but render the first line and the form reference through HTML anchors.

Report phase result inline:
```
✓ Phase 8 done — pilot update posted to the Monday subitem with a real LLs 3 team mention.
```

If posting the update fails, report it clearly and include a manual fallback in the final summary.

---

## Final Summary Report

After all phases complete, show a consolidated report:

```
## Localization Workflow — Complete

**Feature:** [name]
**Keys processed:** [N] ([K] not found in Smartling)
**Smartling tag:** [tag] → [dashboard URL]
**Figma screenshots:** [N updated / skipped]
**Smartling job(s):**
  - [name] — [N words] → [job URL]
  - [name - Viewer] — [N words] → [job URL]   ← only if mixed scope
**Monday item:** [name] → [Monday URL]
  - Subitem: [name]
  - Subitem: [name (Viewer)]   ← only if mixed scope
**GA artifact(s):** [com.wixpress.example] ← or "not identified"
**Content score:** [X.X / 3]
  - Company: [X.X] — [company area]
  - Impact: [1/2/3] — [Low/Medium/High]
  - Complexity: [1/2/3] — [Low/Medium/High]
  - Logic: [short explanation]
**Pilot sheet:** [row created/updated or failed]
**Monday update:** [posted or failed]

---
Phases:
  ✓ 1. Input parsed ([Jira/Key list/Slack])
  ✓ 2. Strings tagged in Smartling
  [✓/⚠] 2.5. GA artifact identified [or not identified]
  [✓/⚠] 3. Figma screenshots uploaded [or skipped]
  ✓ 4. Smartling job(s) created & authorized
  ✓ 5. Monday item & subitem(s) created
  ✓ 6. Content score calculated → [Green/Yellow/Red]
  ✓ 6.5 Authorized ([LLM GREEN | LLM YELLOW | default]) + [Babel sync | Monday Done | none]
  [✓/⚠] 7. Pilot tracking sheet updated
  [✓/⚠] 8. Pilot update posted in Monday
```

When reporting the created task summary, always include the content score block alongside the task links so the user sees the score and rationale in the same completion message.

If any phase failed partially, include it in the report with an explanation and a manual action the user can take.

---

## Rules

- Always run phases in order — each phase's output feeds the next.
- Pass hashcodes from Phase 2 directly into Phase 4 — do not re-resolve keys.
- If a phase fails completely, stop and report clearly. Do not silently skip phases.
- If `monday-localizer` has unfilled `FILL_IN` board/column IDs, warn the user before Phase 5 and offer to skip it.
- After the Monday item exists, always complete the pilot tracking sheet step and the standardized Monday update step before declaring the workflow done.

## Example prompts

- `/localization-workflow` followed by a Jira URL
- `/localization-workflow` followed by a pasted list of keys
- Use `$localization-workflow` for this Slack message: [paste]

