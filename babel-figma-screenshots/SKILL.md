---
name: babel-figma-screenshots
description: Use when the user wants to provide Babel key names and a Figma file, then map keys to Figma design sections and upload section screenshots to Babel. This skill is for batch screenshot association workflows; it does not create keys or update key values.
---

# Babel Figma Screenshots

Run a batch workflow that starts from Babel key names, triages which keys need screenshots, explores a Figma file's structure to identify design sections, maps groups of keys to sections, and uploads section screenshots to Babel.

Use this skill when the user asks for a flow like "process these keys against this Figma file and upload screenshots to Babel."

## Architecture

This skill uses a **section-based** workflow, not a per-key workflow. Keys are grouped by UI area and mapped to Figma sections. One section screenshot serves multiple keys.

```
GATHER → TRIAGE → ANNOTATIONS MATCH → EXPLORE FIGMA → GROUP KEYS → BATCH EXPORT → BATCH UPDATE → REPORT
```

## Workflow

### Phase 1: Gather input

Collect:

- `key_names[]` — the full list of Babel key names.
- `figma_file` — a Figma URL or file key.

If the user gives a Figma URL, extract:

- **file key**: from `https://www.figma.com/design/<file_key>/...` or `https://www.figma.com/file/<file_key>/...`.
- **node-id** (if present): from the `node-id=` query parameter. Use as a starting scope hint.

### Phase 2: Triage keys

Before doing any Figma work, check the current state of every key in Babel.

For each key:

1. Search with `babel__search_keys` using `name` (exact match) and `locale: "en"`.
2. If a key returns results from multiple projects, record all matches. Keys may live in different Babel projects — this is normal.
3. If a key is not found with `name`, retry with `searchExpression` (fuzzy search). If still not found, try without `locale` filter.
4. Record:
   - `id`, `revision`, `projectId`
   - Whether `imageContextUrl` is already set
   - The English `value` (for semantic grouping later)

**Classify each key**:

| Status | Condition |
|---|---|
| `already_done` | Key found, `imageContextUrl` already set |
| `needs_screenshot` | Key found, no `imageContextUrl` |
| `not_found` | Key not found in any Babel project |

**Batch searching**: Search up to 5 keys in parallel to speed up triage.

**Multi-project awareness**: Keys commonly span multiple Babel projects. Track the `projectId` for each key — you will need it for updates. Do not assume all keys share a project.

Report triage results before proceeding:

```
Triage complete:
- 36 already have screenshots
- 10 need screenshots
- 2 not found in Babel

Proceeding with the 10 that need screenshots.
```

If all keys already have screenshots, stop and report. If some keys are not found, report them and ask the user whether to continue or correct the names.

### Phase 3: Match via Figma annotations (fast path)

**Before exploring the file structure manually, try matching keys against Figma annotations.** This is the fastest and most precise method.

Figma files often contain **annotations** — text labels attached to specific nodes that describe their purpose or content. These annotations frequently contain the exact Babel key name, the key value text, or a description that maps directly to a key.

**Step 3a — Get file comments/annotations**:

Use `figma__get-file-comments` on the file key to retrieve all comments. Scan comment text for:

1. Exact Babel key names (e.g., `cart-core.removeDomainModal.title`).
2. Key value text (e.g., "Remove {domainName}?").
3. Key name fragments (e.g., `removeDomainModal`).

**Step 3b — Match annotations to nodes**:

Comments include `client_meta` with a `node_id` indicating which Figma node they are attached to. When a comment matches a key:

1. The `node_id` from the comment gives you the exact frame or component.
2. Use `figma__get-file-nodes` on that node to verify it's a suitable screenshot target.
3. If the node is too small (a text node or icon), walk up one or two levels to find the containing design frame.

**Step 3c — Also check node descriptions and frame names**:

When exploring nodes (in this phase or the next), look for:

- Frame names that match key name segments (e.g., a frame named "Remove Domain Modal").
- Node `description` fields that reference key names or values.
- Annotation-style component names that map to key prefixes.

**When annotations resolve a key directly**, skip the manual Figma exploration (Phase 4) for that key. Only fall through to Phase 4 for keys that annotations did not resolve.

This fast path can resolve many keys without any manual file structure exploration, especially in well-annotated design files.

### Phase 4: Explore Figma structure (fallback)

For keys not resolved by annotations, explore the file structure manually.

The Figma API has **no text search**. You must explore the file structure to understand its organization and identify screenshot-worthy sections.

**Step 4a — Get the page structure**:

Use `figma__get-file` with `depth: 1` to get the top-level pages. Identify the relevant page (usually named something like "Dev handoff", "Designs", "Specs", or similar).

**Step 4b — Get sections within the page**:

Use `figma__get-file-nodes` on the relevant page with `depth: 1` to see its direct children (sections/frames). These are typically organizational containers like:

- "Full flows"
- "Errors + States"
- "Checkout"
- "Business email"

**Step 4c — Go deeper if needed**:

If sections are still too broad, fetch their children at `depth: 1` to find individual design frames or subsections. The goal is to identify frames that represent complete screens/views — these are the screenshot targets.

**Handling large responses**: Figma API responses can be very large. If a response exceeds what you can process:

1. Save it to a local file using the agent-tools directory.
2. Parse it with a Python script via Shell to extract the structure summary (node names, IDs, types).
3. Use the summary to decide which nodes to explore further.

### Phase 5: Map keys to Figma sections

Group the `needs_screenshot` keys by semantic UI area based on their Babel values and key name prefixes.

**Grouping heuristics**:

| Key name pattern | Likely Figma section |
|---|---|
| `*.error.pageLoad.*` | Page load error states |
| `*.error.checkout.*` | Checkout error states |
| `*.error.domainUnavailable.*` | Domain availability states |
| `*.error.noPermission.*` | Permission error states |
| `*.error.purchaseComplete.*` | Purchase complete states |
| `*.removeDomainModal.*` | Remove domain modal |
| `*.replaceDomainInCart.*` | Replace domain modal |
| `*.error.toast.remove.*` | Remove error toasts |
| `*.cart.domainItem.*` | Main cart domain items |
| `*.cart.businessEmail.*` | Business email section |
| `*.header.user.*` | Header/navigation area |

Map each group to the Figma section identified in Phase 3 (annotations) or Phase 4 (manual exploration). Use the Figma section names and the Babel key values together to make the mapping.

If a mapping is unclear, ask the user. Do not guess.

### Phase 6: Batch export Figma images

For each Figma section that has keys mapped to it:

1. Use `figma__get-image` with `format: "png"` and `scale: 2`.
2. **Batch requests**: Include up to 3-5 node IDs per `get-image` call.
3. **Handle render timeouts**: If the API returns a 400 "Render timeout", split the batch into smaller groups (1-2 nodes per call) and retry.
4. Record the resulting S3 image URL for each section.

**Image URL format**: Figma returns URLs like `https://figma-alpha-api.s3.us-west-2.amazonaws.com/images/<uuid>`. These URLs are usable as `imageContextUrl` values. See [references/figma-and-babel-details.md](references/figma-and-babel-details.md) for URL lifetime notes.

### Phase 7: Batch update Babel keys

For each key group:

1. Use `babel__update_key` with the key's `id`, current `revision`, and the section's image URL as `imageContextUrl`.
2. Do **not** change the key `name` or `value`.
3. Update up to 5 keys in parallel.
4. If an update fails (e.g., revision conflict), re-fetch the key to get the current revision and retry once.

### Phase 8: Report

End every run with a summary. See [references/figma-and-babel-details.md](references/figma-and-babel-details.md) for the full format specification.

Statuses:

| Status | Meaning |
|---|---|
| `updated` | Screenshot uploaded this session |
| `already_done` | Key already had `imageContextUrl` before this run |
| `not_found` | Key not found in Babel |
| `upload_error` | Key found, Figma image obtained, but Babel update failed |
| `no_section` | Key found, but could not map to a Figma section |
| `render_error` | Figma image export failed for the mapped section |

## Rules

- **Check before you work**: Always triage keys for existing `imageContextUrl` before touching Figma.
- **Section-based, not per-key**: Screenshot entire design sections, not individual text nodes.
- **Multi-project aware**: Keys can live in different Babel projects. Track `projectId` per key.
- **Batch everything**: Search keys in parallel, export images in batches, update keys in parallel.
- **Handle Figma limits**: Batch image exports (3-5 per call), retry on render timeout with smaller batches.
- Do not create keys in Babel.
- Do not update Babel key values.
- Do not silently skip unresolved keys — report every key's status.
- If a required MCP tool is unavailable, say exactly which step is blocked.

## Example prompts

- Process these Babel keys against this Figma file and upload screenshots to Babel.
- Find the Figma section for these keys and attach screenshots in Babel.
- Use `$babel-figma-screenshots` for this key list and Figma URL.
