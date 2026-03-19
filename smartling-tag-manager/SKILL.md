---
name: smartling-tag-manager
description: Add Smartling tags to strings starting from a manual key list, spreadsheet column, or copied export, using Smartling MCP instead of direct API credentials. Use when the user wants to tag many Smartling strings by key or variant, resolve missing project IDs, preserve the original script's exact-then-partial matching behavior, and report which keys were found, tagged, or not found.
---

# Smartling Tag Manager

Resolve Smartling string hashcodes from user-provided key names, then add one or more tags in bulk through Smartling MCP.

Do not use environment variables, raw Smartling credentials, or direct HTTP calls. Prefer Smartling MCP tools for discovery, matching, and tagging.

## Inputs

Collect only what is needed:

- `project_id`
- `tag_names[]`
- `keys[]`

Accept keys from:

- a pasted list
- a CSV or spreadsheet export already present in the workspace
- user-provided column values extracted from a file

If the user gives a project name instead of an ID, resolve it with Smartling MCP before searching strings.

Normalize keys before matching:

- trim whitespace
- lowercase for comparison
- keep the original text for reporting

Ignore blank rows and duplicates in the input list.

## Workflow

### 1. Resolve the project

If `project_id` is missing:

1. Use `smartling_list_projects` to find the project.
2. If there is a single clear match, use it.
3. If there are multiple plausible matches, ask the user to choose.

### 2. Prepare the key list

Build a deduplicated input set from the supplied keys.

Track:

- `original_key`
- `normalized_key`
- `status`
- `matched_hashcodes[]`
- `matched_display_keys[]`

### 3. Find strings with an exact pass first

Mirror the original script's behavior by doing an exact pass before any fuzzy fallback.

For each unresolved key:

1. Call `smartling_search_strings` with:
   - `project_uid = project_id`
   - `key_variant_filter.keyword = original_key`
   - `key_variant_filter.exact_match = true`
   - `source_only = true`
2. Treat any returned string hashcodes as exact matches.
3. Record the best display key from the returned variant/key metadata when available.

Prefer batching search calls in parallel when many keys are provided.

### 4. Run a partial pass only for unresolved keys

For keys not found in the exact pass, run a fallback search:

1. Call `smartling_search_strings` with:
   - `project_uid = project_id`
   - `key_variant_filter.keyword = original_key`
   - `key_variant_filter.exact_match = false`
   - `source_only = true`
2. Keep only plausible matches whose normalized key or variant contains the normalized input, or is contained by it.
3. Skip very short keys for partial matching when they are likely to create noisy results.

Do not mark a key as found unless the returned match is plausibly the same key family. The goal is to preserve the script's "exact first, cautious partial second" behavior, not maximize recall at any cost.

### 5. Deduplicate hashcodes and tag in bulk

After both passes:

1. Combine all matched hashcodes.
2. Deduplicate them across keys.
3. Call `smartling_add_tags_to_strings` with the final hashcode list.
4. If the set exceeds 1000 hashcodes, split into batches of 1000.

Do not fail the whole run just because some keys were not found.

### 6. Return a compact report

Always report:

- total input keys
- unique non-empty keys
- found keys
- not found keys
- total unique hashcodes tagged
- whether matches came from exact or partial search

When possible, include a Smartling dashboard URL in this form:

`https://dashboard.smartling.com/app/projects/{project_id}/strings/?limit=25&offset=0&tagsFilter.keywords[]={urlencoded_tag}&tagsFilter.mode=OR_MODE&sourceOnly=false`

## Rules

- Use Smartling MCP tools instead of raw API authentication.
- Prefer exact key-variant matches before partial matches.
- Deduplicate both keys and hashcodes.
- Ignore blank input rows.
- Continue when some keys cannot be found.
- Ask the user only when project resolution or match ambiguity has meaningful risk.
- Keep the final response compact and operational.

## Output format

End with:

1. A short summary sentence.
2. A flat list of matched keys and their resolution mode when the batch is small enough to read.
3. A flat list of not found keys.
4. The Smartling tag URL when a tag was applied successfully.

## Example prompts

- Use `$smartling-tag-manager` to tag these Smartling keys with `release-2026-03`.
- Apply the tag `billing-audit` to this pasted list of Smartling keys.
- Read the first column from this CSV, resolve the Smartling strings, and tag the matches.
