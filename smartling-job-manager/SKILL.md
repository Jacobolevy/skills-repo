---
name: smartling-job-manager
description: Use when you need to create a Smartling translation job, add strings to it by hashcode, authorize it, and retrieve the resulting wordcount and job URL. Designed to run after smartling-tag-manager has already resolved the string hashcodes.
---

# Smartling Job Manager

Create a Smartling translation job, populate it with strings, authorize it for translation, and return the job URL and wordcount.

Do not use raw API credentials or direct HTTP calls. Use Smartling MCP tools for all operations.

## Job naming rules

Job names use human readable text — NO hyphens or kebab-case.

Jobs are **feature-level**, broader than the tag. Examples: `"BE - Business purchase flow"`, `"Gift Cards - Viewer"`, `"Pricing Plans"`.

**Always search for an existing job before creating a new one.** Old jobs are often reused even if created years ago, as long as the feature is the same.

## Inputs

Collect before starting:

- `project_id` — Smartling project UID (resolve via `smartling_list_projects` if only the name is known)
- `job_name` — proposed job name (feature-level, human readable). The orchestrator will have already searched for existing jobs.
- `existing_job_uid` (optional) — if an existing job was identified for reuse, pass it here to skip creation
- `hashcodes[]` — list of string hashcodes to add to the job (passed in from `smartling-tag-manager`; do NOT re-resolve keys)
- `wordcount` — total word count from `smartling-tag-manager` output (sum of `totalWordCount` per string). **Required.** Use this value if the job API does not return a wordcount field.
- `is_uou` — boolean. `true` = authorize for all 36 languages; `false` = authorize for "Account languages" group (21 languages)
- `due_date` (optional) — ISO date string; omit if not specified by user

## Workflow

### 1. Discover available tools

Use the confirmed Smartling MCP tool names:
- `smartling_list_projects` — list/resolve projects
- `smartling_list_jobs` — search existing jobs
- `smartling_create_job` — create a new job
- `smartling_add_strings_to_job` — add hashcodes to a job
- `smartling_authorize_job` — authorize job for translation
- `smartling_get_job` — fetch job details and wordcount

### 2. Resolve project

If `project_id` is not provided:
1. Call `smartling_list_projects` to find the project.
2. If a single clear match, use it.
3. If multiple matches, ask the user to choose.

### 3. Create the job

Call the job creation tool with:
- `project_uid = project_id`
- `name = job_name`
- `due_date` if provided
- `description` (optional): auto-populate with `"Created by localization workflow automation"`

Record the returned `job_uid`.

### 4. Add strings to the job

Add the provided hashcodes to the job.

- If the MCP tool supports batch addition, pass all hashcodes in one call.
- If there is a limit (typically 1000 per call), batch into chunks of 1000.
- Do not re-resolve keys — use the hashcodes passed in directly.

### 5. Add target locales — do NOT authorize yet

This skill only adds strings to the job and sets the target locales. **Do not call `smartling_authorize_job` here.**

Authorization with the correct LLM workflow happens in **Phase 6.5** (after content scoring), via the `smartling-post-auth` skill. The workflow selection (GREEN / YELLOW / project default) depends on the content score, which is not known yet at this phase.

**Set target locales** based on `is_uou`:

| `is_uou` | Target locales | Count |
|---|---|---|
| `false` | Account languages | 21 |
| `true` | All locales | 36 |

**Account languages — exact locale IDs (21):**
`cs-CZ, da-DK, de-DE, es, fr-FR, hi-IN, id-ID, it-IT, ja-JP, ko-KR, nl, no-NO, pl-PL, pt, ru-RU, sv-SE, th-TH, tr-TR, uk-UA, vi-VN, zh-TW`

**All locales (36)** — same 21 + additional Viewer locales. Check an existing Viewer job for the full list (e.g. job `s1lgfxt1djfa` in project `6bc9e740e`).

Pass `target_locale_ids` when calling `smartling_create_job` (not `smartling_authorize_job`).

**Strict locale rule:**
- If `is_uou = false`, the job must contain only the 21 Account languages listed above.
- Do **not** reuse an old job that already includes extra locales such as `ar` or `he-IL` unless the user explicitly approves authorizing beyond the 21 Account languages.
- If the best existing job has extra locales, create a new clean 21-locale job instead.

**Important — strings added to existing IN_PROGRESS jobs:**

When strings are added to an existing job that is already `IN_PROGRESS`, Smartling does NOT auto-authorize the new strings — they remain in `AWAITING_AUTH` status. In this case, Phase 6.5 will authorize those strings when it runs.

**Race condition with `move_enabled=true`:** When strings are moved from another job, Smartling processes the move asynchronously. **Wait ~5 seconds** before Phase 6.5 runs its authorization call.

### 6. Retrieve job details

Fetch the job to confirm its status.

For wordcount: the Smartling job API does not reliably return a wordcount field. **Always use the `wordcount` input value passed in from `smartling-tag-manager`.** Do not rely on the API response for this.

Construct the Smartling dashboard URL for the job:
`https://dashboard.smartling.com/app/projects/{project_id}/jobs/{job_uid}`

### 7. Return structured output

Return the following clearly, for use by Phase 6.5 (`smartling-post-auth`) and the Monday skill:

```
## Smartling Job — Created (pending authorization)

**Job name:** [name]
**Job UID:** [uid]
**Status:** AWAITING_AUTHORIZATION (will be authorized in Phase 6.5)
**Target locales:** [21 account / 36 all]
**Strings added:** [N]
**Wordcount:** [N words]
**Job URL:** https://dashboard.smartling.com/app/projects/{project_id}/jobs/{job_uid}
```

## Rules

- Always use hashcodes passed in — never re-resolve keys via search.
- Reuse existing jobs for the same feature when possible — `IN_PROGRESS` or `COMPLETED` jobs can both receive new strings; only skip `CANCELLED` jobs.
- If the create or add-strings step fails, stop and report clearly.
- If wordcount is not available in the API response, note it as "not available from API — check Smartling dashboard".
- Keep the response compact.

## Example prompts

- Use `$smartling-job-manager` to create a job called "Premium Email — Q2" with these hashcodes: [...]
- Create and authorize a Smartling job for project `abc123` using the hashcodes from the last tagging run.
