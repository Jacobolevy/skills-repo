---
name: smartling-post-auth
description: Run post-authorization Smartling actions (workflow selection, Babel sync, Monday Done) based on the content score color (Green/Yellow/Red). Always runs after Phase 6 (content scoring). Never call this skill directly — it is invoked by localization-workflow after Phase 6.
---

# Smartling Post-Authorization Actions

Select the correct Smartling LLM workflow based on the content score color and re-authorize the job with it. The workflow itself handles translation routing — no separate publish/reject API calls needed.

## How the workflows work

| Workflow name | UID (project b3eef828d) | Behavior |
|---|---|---|
| Product Localization LLM default flow - GREEN | `972739bc38e4` | GEMINI → Processing → **Published** (auto, no human review) |
| Product Localization LLM default flow - YELLOW | `0d48ce8988bf` | GEMINI → **Human Review** → Processing → Published |
| Project default (human translation) | — | Human translator workflow, no LLM |

> UIDs above are for project `b3eef828d`. For other projects, call `smartling_list_workflows` with keyword `"LLM"` to find the equivalent workflows.

## Inputs

Required from the localization-workflow orchestrator:

| Input | Source |
|---|---|
| `score_color` | Phase 6 content score → `Green` / `Yellow` / `Red` |
| `project_id` | Smartling project UID |
| `job_uid` | Smartling job UID (from Phase 4; if split-project, one per job) |
| `target_locales[]` | All locale IDs authorized in the job |
| `monday_subitem_id` | Monday subitem ID (from Phase 5; if two subitems, apply Green/Done to both) |
| `babel_project_id` | Babel project ID (from Phase 3 triage; if multiple, sync all of them) |

> The `is_uou` flag does **not** change what this skill does. It already had its effect in Phase 4 (locale count: 21 vs 36). Phase 6.5 applies the same Green/Yellow/Red rules regardless of UoU.

## Decision table

| Score | Workflow to use | Babel sync | Monday |
|---|---|---|---|
| Green | LLM GREEN (`972739bc38e4`) | ✓ Sync | `color_mkyf691e` = `Done`; `color_mm3qayc2` = `Green` |
| Yellow | LLM YELLOW (`0d48ce8988bf`) | ✓ Sync | `color_mm3qayc2` = `Yellow` |
| Red | Project default (no override) | — | `color_mm3qayc2` = `Red` |

**"no change" for task status** = the Monday subitem already has `color_mkyf691e` = `Ready for ETA` from Phase 5. No update needed.

> `color_mm3qayc2` = **score color column** — always set on every subitem, regardless of Green/Yellow/Red.

## Workflow

### Step 1 — Find LLM workflow UIDs (Green and Yellow only)

For projects other than `b3eef828d`, or to confirm the UIDs:

```
smartling_list_workflows(project_id, keyword: "LLM")
```

Select:
- GREEN workflow: name contains "LLM" and "GREEN"
- YELLOW workflow: name contains "LLM" and "YELLOW"

Skip this step if score is Red.

### Step 2 — Re-authorize the job with the selected workflow (Green and Yellow only)

Build a `locale_workflows[]` array mapping **every target locale** in the job to the selected workflow UID:

```json
locale_workflows: [
  { "targetLocaleId": "cs-CZ", "workflowUid": "<selected_workflow_uid>" },
  { "targetLocaleId": "da-DK", "workflowUid": "<selected_workflow_uid>" },
  ...
]
```

Call:
```
smartling_authorize_job(
  project_uid = project_id,
  job_uid = job_uid,
  locale_workflows = <array above>
)
```

This re-authorization is safe on IN_PROGRESS jobs — Smartling accepts it and changes the workflow for all strings in the job.

For Red score, skip this step entirely — leave the job with its project default workflow (human translation).

**Split-project jobs**: run Step 2 for each `job_uid` independently.

### Step 3 — Sync Babel (Green and Yellow only)

Immediately after re-authorizing, trigger a Babel sync:

```
babel__sync_project(projectId = babel_project_id)
```

If the workflow has keys across multiple Babel projects, call `babel__sync_project` for each.

This sync is async — Babel will update in the background. No need to wait.

Skip this step if score is Red.

### Step 4 — Update Monday columns (all scores)

**Always set `color_mm3qayc2` (score color) on the subitem — for every score:**

```graphql
mutation {
  change_column_value(board_id: 9991673115, item_id: {monday_subitem_id},
    column_id: "color_mm3qayc2",
    value: "{\"label\": \"Green\"}") { id }   # or "Yellow" or "Red"
}
```

**Additionally, for Green only — set `color_mkyf691e` to `Done`:**

```graphql
mutation {
  change_column_value(board_id: 9991673115, item_id: {monday_subitem_id},
    column_id: "color_mkyf691e",
    value: "{\"label\": \"Done\"}") { id }
}
```

Use `mcp__Webrix__monday__all_monday_api` for these calls. These two can be batched into a single `change_multiple_column_values` call for Green. For Yellow and Red, only `color_mm3qayc2` needs to be set.

If there are two subitems (split-project or mixed scope), apply both updates to **both** subitems.

## Report

Append to the Phase 6 inline report:

```
   Phase 6.5 — Post-auth Smartling actions:
   ✓ Re-authorized with LLM GREEN workflow        ← Green
   ✓ Babel sync triggered                         ← Green and Yellow
   ✓ Monday status → Done                         ← Green only

   ✓ Re-authorized with LLM YELLOW workflow       ← Yellow
   ✓ Babel sync triggered                         ← Yellow

   Post-auth actions: none (Red → human translation)  ← Red
```

## Rules

- **On-call tasks**: same rules apply — Green/Yellow/Red determine workflow selection exactly like Jira tasks.
- **Split-project jobs**: re-authorize each `job_uid` independently with the same workflow.
- **Re-authorization is always safe**: calling `smartling_authorize_job` on an IN_PROGRESS job changes the workflow for all strings without resetting progress.
- **Babel sync is async**: no need to wait — fire and continue.
- **Red score**: do nothing in Smartling. Leave the job with the default human translation workflow.
