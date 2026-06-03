---
name: jira-reader
description: Use when you need to read a Jira ticket and extract localization-relevant data from it: keys, Figma URLs, feature toggles, sprint/feature name, and any linked tables or Confluence docs. Returns structured output for use in the localization workflow.
---

# Jira Reader

Read a Jira ticket by URL or issue key and extract all data needed to start a localization workflow: key list, Figma URL, feature toggle, and feature/sprint name. Also transitions the ticket to **In Progress** and checks for visual context if no Figma is found.

## Input

Accept any of:
- A full Jira URL (e.g. `https://jira.wixpress.com/browse/TRANS-1234`)
- A Jira issue key (e.g. `TRANS-1234`)

Extract the issue key from the URL if a full URL is given.

## Workflow

### 1. Discover available Jira MCP tools

List the Jira MCP tools available in this session. Look for tools that can:
- Fetch an issue by key (e.g. `get_issue`, `jira_get_issue`)
- Get issue comments or attachments
- Fetch linked Confluence pages

Use whatever tool names are actually available — do not assume specific names.

### 2. Fetch the issue

Call the Jira MCP tool to fetch the issue by key. Retrieve:
- `summary` (title)
- `description` (body — may be Atlassian Document Format or plain text)
- `status`, `assignee`, `labels`, `fixVersions`, `sprint` (if available)
- Any linked issues or remote links
- Attachments list (images attached to the ticket)

**Extract visual assets for Phase 3:**

From the Jira response, collect all image assets into `jira_images[]`:
1. **Attachments** — any attachment with `mimeType` starting with `image/` → record its `content` URL (the download URL)
2. **Inline images in description** — in ADF, look for nodes of type `mediaSingle` or `mediaInline` with `attrs.url` or `attrs.id` → record the media URL

These URLs require Jira auth headers to download. Store them as-is; the localization workflow will download them in Phase 3.

### 3. Parse the description

The description may contain:
- Tables with a "Key" or "String key" column — extract all values from that column
- Inline dot-separated key names (e.g. `namespace.component.action`) — extract them
- Figma links — look for `figma.com/design/` or `figma.com/file/`
- Feature toggle references — look for `specs.`, `feature toggle:`, `toggle:`, `spec:` patterns
- Sprint or feature name — use the ticket summary if no explicit name is found

**Key extraction rules:**
- A valid localization key matches the pattern: two or more dot-separated segments, where each segment is camelCase or kebab-case (e.g. `cart.removeDomainModal.title`, `billing-core.upgrade.cta`)
- Collect all unique keys found across description, tables, and any inline code blocks
- Deduplicate and trim whitespace

**Scope extraction — per key:**

Keys in Jira descriptions are often prefixed or labeled with their audience scope. Extract this label for each key:

| Label in Jira | Scope |
|---|---|
| `BM -`, `BM:`, `Business Manager`, `Merchant` | `bm` |
| `Viewer -`, `Viewer:`, `UoU`, `UoU-facing` | `viewer` |
| No label | `bm` (default — account languages only) |

Record each key with its scope: `{ key: "...", scope: "bm" | "viewer" }`.

If the label is ambiguous or the description structure is unusual, note it in the output and flag it for the user to confirm.

### 4. Transition ticket to In Progress

After successfully fetching the issue, use the Jira transition tool to move it to **In Progress**:
1. Call `get-available-transitions` to find the "In Progress" transition ID
2. Call `transition-issue` with that ID
3. Note the status change in the output (no need to ask the user — do it automatically)

### 5. Visual context check (when no Figma URL found)

If no Figma URL was found in step 3:

1. **Check Babel for existing content** — for each key, call `babel__get_key` (or `babel__search_keys`) to see if the key already exists in Babel with content/image context attached.
   - If **all keys have content in Babel**: note this in the output and proceed — no images needed.
   - If **any key is missing content in Babel**: note which keys are missing — the localization workflow Phase 3 will handle the upload using Jira images or Snagit. Do **not** block or ask the user here.

### 6. Fetch linked content (if needed)

If the description references or links to:
- A Confluence page: use the available MCP tool to fetch its content and apply the same key/Figma/toggle extraction
- Additional Jira sub-tasks or epics: note their keys but do not follow them unless the user asks

### 7. Return structured output

Return the following structure clearly, so the orchestrator or user can pass it to the next step:

```
## Jira Reader — Results

**Ticket:** [KEY] — [Summary]
**Status:** In Progress ✓ (transitioned from [previous status])

**Localization keys found:** [N]
[list of keys, one per line]

**Figma URL:** [URL or "not found"]
**Jira images:** [N images found — attachment URLs] or "none"
**Visual context:** [Found in Babel / Jira images available / Pending]
**Feature toggle:** [toggle name or "not found"]
**Feature/sprint name:** [name derived from ticket summary or sprint field]

**Notes:** [any ambiguities, multiple Figma links, partially matched keys, etc.]
```

If no keys are found, report that clearly and ask the user whether to continue or check the ticket manually.

## Rules

- Extract keys conservatively: prefer false negatives over false positives. Only include strings that match the localization key pattern.
- If the description is in Atlassian Document Format (ADF), parse the JSON to find text nodes — do not treat the raw JSON as key candidates.
- Always transition the ticket to In Progress — do not ask for permission, just do it.
- If the Jira MCP is unavailable, stop and report which tool is missing.
- Keep the output compact — the key list is the most important output.

## Example prompts

- Use `$jira-reader` on this ticket: https://jira.wixpress.com/browse/TRANS-1234
- Read `TRANS-5678` and extract the localization keys.
