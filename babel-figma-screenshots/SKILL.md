---
name: babel-figma-screenshots
description: Use when the user wants to provide Babel key names and a Figma file, Jira ticket with images, or manually pasted screenshots, then map keys to design sections and upload screenshots to Babel. This skill is for batch screenshot association workflows; it does not create keys or update key values.
---

# Babel Figma Screenshots

Run a batch workflow that starts from Babel key names and a visual source (Figma file, Jira attachments, or manually pasted images), maps keys to design sections or images, and uploads screenshots to Babel.

Use this skill when the user asks for a flow like "process these keys against this Figma file and upload screenshots to Babel", or when a Jira ticket contains embedded screenshots instead of a Figma link.

## Image Sources

This skill supports three image sources:

| Source | Detection | Workflow |
|---|---|---|
| **Figma file** | User provides a `figma.com` URL | Full Figma exploration flow (phases 3–6) |
| **Jira attachments** | Jira ticket has `attachment[]` with image files | Download via Jira API URL, upload to Babel |
| **Manual images** | User pastes image(s) directly in chat | Save to temp file, upload to Babel |

Detect which source applies from the inputs and follow the matching path. Multiple sources can be combined in one run (e.g., Jira images for some keys, Figma for others).

### Jira attachment flow

When the image source is Jira attachments:

1. Each attachment has a `content` URL (e.g., `https://api.atlassian.com/ex/jira/.../attachment/content/994644`).
2. **Auth limitation**: Jira attachment content URLs require OAuth tokens that only the Jira MCP has internally. curl and other tools cannot access them directly. Ask the user to download the images manually from the Jira ticket (right-click → Save image) to `~/Downloads/` and provide the file paths.
3. Read each downloaded image using the Read tool — Claude is multimodal and can see the image content visually.
4. Match each image to the correct key by reading what is visible in the screenshot (UI text, labels, layout) and comparing to the Babel key names and English values. Do not ask the user — use visual OCR to determine the mapping.
5. Upload using the **mcp-s CLI script** (see below). Do NOT use `babel__upload_key_image_context` directly.
6. If only one image and one key, skip visual matching and upload directly.

### Manual image flow

When the user pastes one or more images in chat:

1. Claude sees the image(s) visually in the conversation.
2. Read each image to understand its content — use the visible UI text, labels, and layout to match it to the correct Babel key. Do not ask the user to confirm the mapping unless the match is genuinely ambiguous.
3. **Find the file on disk using the message timestamp.** Images captured with Snagit are saved as temp files named `YYYY-MM-DD_HH-MM-SS.png` in `/var/folders/71/*/T/`. The filename timestamp matches the moment the capture was taken. Search with:
   ```bash
   ls -lt /var/folders/71/*/T/*.png 2>/dev/null | head -5
   ```
   Pick the file(s) whose timestamp is closest to the message send time.
4. If no matching file is found, the image exists only in the clipboard — Claude can see it but cannot access its bytes. Ask the user to save it to disk using any of these methods:
   - **Cmd+Shift+4** → screenshot saved automatically to Desktop
   - **Right-click the image in chat → Save image** → save to any known path
   - **Snagit** → saves automatically to `/var/folders/71/*/T/`
   Then ask for the file path and continue.
5. Upload using the **mcp-s CLI script** (see below). Do NOT use `babel__upload_key_image_context` directly.

### ⚠️ CRITICAL: How to upload local images to Babel

**Never pass base64 strings manually to `babel__upload_key_image_context`.** The MCP tool silently truncates long base64 strings (anything over ~200 chars), resulting in a corrupt image that renders as a solid gray rectangle in Babel. This happens regardless of image size or format.

**The correct approach: use the `@mcp-s/cli` subprocess.**

This reads the file directly in Node.js — the base64 never passes through the LLM — and calls the MCP tool via the CLI.

**Step 1 — Check auth (once per session):**
```bash
npx -y --registry https://npm.dev.wixpress.com @mcp-s/cli@0.0.21 check-auth
```
If it returns `token expired` (exit 4), tell the user to run:
```bash
npx -y --registry https://npm.dev.wixpress.com @mcp-s/cli@0.0.21 login
```
Wait for them to confirm login before proceeding.

**Step 2 — Write and run the upload script:**

```javascript
// /tmp/babel_upload.mjs
import { readFileSync } from 'fs';
import { spawnSync } from 'child_process';

const NPM_REGISTRY = 'https://npm.dev.wixpress.com';
const CLI = '@mcp-s/cli@0.0.21';

const keyId = 'REPLACE_WITH_KEY_UUID';
const imagePath = 'REPLACE_WITH_IMAGE_PATH';  // full resolution original — no need to resize
const imageType = 'image/png';  // or image/jpeg

const imageBase64 = readFileSync(imagePath).toString('base64');
console.log(`Image: ${imagePath} (${imageBase64.length} b64 chars)`);

const args = JSON.stringify({ keyId, image: imageBase64, imageType });

const result = spawnSync(
  'npx', ['-y', '--registry', NPM_REGISTRY, CLI, 'call', 'babel__upload_key_image_context', args],
  { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024, env: { ...process.env, npm_config_registry: NPM_REGISTRY } }
);

console.log('stdout:', result.stdout?.slice(0, 500));
console.log('exit:', result.status);
```

Run with: `node /tmp/babel_upload.mjs`

**After upload, always verify** by downloading the S3 URL and checking with PIL:
```python
import urllib.request
from PIL import Image
urllib.request.urlretrieve(IMAGE_URL, '/tmp/verify.png')
img = Image.open('/tmp/verify.png'); img.load()
print(f'Valid: {img.size}')  # should print dimensions, not throw OSError
```

**Use full resolution.** Do not resize the original screenshot — upload it at native size for maximum clarity.

## Architecture

This skill uses a **section-based** workflow for Figma, and a **direct-upload** workflow for Jira attachments and manual images.

```
AUTH CHECK → GATHER → DETECT SOURCE → TRIAGE → PERSIST MAPPING → [FIGMA PATH or DIRECT UPLOAD PATH] → BULK UPDATE → REPORT
```

## Workflow

### Phase 0: Auth check

**Before any other work**, verify Babel is reachable with a cheap probe call (e.g. `babel__get_project` on the known project ID, or `babel__search_keys` with a single known key name). If it fails with a token error, trigger re-auth immediately — do not discover auth failures mid-update-loop.

### Phase 1: Gather input

Collect:

- `key_names[]` — the full list of Babel key names.
- `image_source` — one of:
  - `figma_file`: a Figma URL or file key
  - `jira_attachments`: a list of Jira attachment objects (from `jira-reader` output or the localization workflow)
  - `manual_images`: image(s) pasted by the user in chat (user must provide file paths)

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

**Batch searching**: Search up to **20 keys in parallel** to minimize round trips. With 89 keys this means ~5 parallel waves instead of ~18.

**Multi-project awareness**: Keys commonly span multiple Babel projects. Track the `projectId` per key. Do not assume all keys share a project.

**Persist triage results immediately** to `/tmp/babel_triage.json` — a JSON array where each entry has the full `id`, `name`, `revision`, `projectId`, and `imageContextUrl`. Never rely on session summary text for these values; the summary may truncate UUIDs.

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

**Step 4c — Match section names to key name segments**:

Key names often encode UI context directly. Extract the context words from the key name and match them to Figma section names:

| Key name contains | Look for Figma sections containing |
|---|---|
| `account_level` | "account level", "Account Level", "from account level" |
| `site_level` | "site level", "Site Level", "from site level" |
| `snackbar`, `toast` | frames/sections showing a notification overlay on a full page |
| `modal` | frames/sections with overlay modal dialogs |
| `activation` | "activation flow", "Activation flow from…" |

**When key names contain `account_level`:** only accept screenshots from sections explicitly named with "account level". Never use site-level pages even if they look visually similar.

**Step 4d — Go deeper if needed**:

If sections are still too broad, fetch their children at `depth: 1` to find individual design frames or subsections. The goal is to identify frames that represent complete screens/views — these are the screenshot targets.

**Embedded screenshots vs. designed components**: Figma files often contain two types of content:
- **Designed components** (FRAME/INSTANCE nodes) — renderable by the Figma API
- **Embedded image rectangles** (RECTANGLE nodes with `imageRef`) — real screenshots placed directly in Figma

Both are valid screenshot sources. When a section contains mostly RECTANGLE nodes with image fills, get them with `figma__get-image` individually and visually inspect each one (download + Read) to find the best match.

**Step 4e — Visually verify ONCE per section, not per key**:

After obtaining a candidate image for a section, download it and visually inspect it **once**:

```bash
curl -s "<figma_image_url>" -o /tmp/candidate.png
```

Then Read the file and confirm:
1. The UI context matches the key name (e.g., account-level page, not site-level)
2. The visible text in the image matches (or is semantically related to) the key's English value
3. The relevant UI element (button, toast, banner, etc.) is clearly visible

If the image fails any of these checks, try a different frame. **Do not re-verify the same URL for every key that maps to the same section** — one check per section is enough.

**Handling large responses**: Figma API responses can be very large. If a response exceeds what you can process:

1. Save it to a local file using the agent-tools directory.
2. Parse it with a Python script via Shell to extract the structure summary (node names, IDs, types).
3. Use the summary to decide which nodes to explore further.

### Phase 5: Map keys to Figma sections and persist mapping

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

**After completing all section→URL mappings, persist the full key→image mapping to `/tmp/key_image_mapping.json`** before starting any Babel updates. The file must contain complete, untruncated values:

```json
[
  {
    "id": "17b99225-22f6-4785-8834-43047af527b4",
    "name": "EM_V2_CampaignOverview_ReplyTo_Placeholder",
    "revision": "2",
    "projectId": "486ea051-99c2-4b80-8e8b-18feb8025b1c",
    "imageContextUrl": "https://figma-alpha-api.s3.us-west-2.amazonaws.com/images/f9c29488-...",
    "bucket": "campaign_overview"
  }
]
```

This file is the source of truth for the update loop. If the session is interrupted and resumed, read from this file — never reconstruct IDs from session summary text, which may truncate UUIDs.

### Phase 6: Batch export Figma images

For each Figma section that has keys mapped to it:

1. Use `figma__get-image` with `format: "png"` and `scale: 2`.
2. **Batch requests**: Include up to 3-5 node IDs per `get-image` call.
3. **Handle render timeouts**: If the API returns a 400 "Render timeout", split the batch into smaller groups (1-2 nodes per call) and retry.
4. Record the resulting S3 image URL for each section.

**Image URL format**: Figma returns URLs like `https://figma-alpha-api.s3.us-west-2.amazonaws.com/images/<uuid>`. These URLs are usable as `imageContextUrl` values. See [references/figma-and-babel-details.md](references/figma-and-babel-details.md) for URL lifetime notes.

### Phase 7: Bulk update Babel keys

1. Read the full mapping from `/tmp/key_image_mapping.json`.
2. Fire **all keys in parallel** in a single wave using `babel__update_key`. Keys share no dependencies — there is no reason to batch them sequentially. With 89 keys this is one wave vs. 18 sequential batches.
3. Do **not** change the key `name` or `value`.
4. Collect results: for each failure (revision conflict, 503, token error):
   - **Revision conflict**: re-fetch the key for its current revision and retry once.
   - **503 / server error**: retry once after a short pause.
   - **Token expired**: re-authenticate (open browser to reauth URL), then retry the failed keys.
5. Write progress to `/tmp/babel_progress.json` as updates complete so a session interruption can resume from where it left off without re-doing successful updates.

**Resume rule**: At the start of a resumed session, read `/tmp/key_image_mapping.json` and `/tmp/babel_progress.json`. Skip any key whose ID already appears in the progress file as `"status": "updated"`.

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
| `needs_path` | Manual image — waiting for user to provide file path |
| `auth_error` | Jira attachment URL not accessible; needs manual download |

## Rules

- **Auth first**: Probe Babel auth before starting any work. Do not discover token expiry mid-update-loop.
- **Persist to files, not memory**: Save triage results (`/tmp/babel_triage.json`), section→URL mapping (`/tmp/key_image_mapping.json`), and update progress (`/tmp/babel_progress.json`) as structured JSON files with full untruncated values. Session summaries may truncate UUIDs — never reconstruct IDs from them.
- **Resume from files**: On session resume, read the mapping and progress files. Skip already-updated keys.
- **Check before you work**: Always triage keys for existing `imageContextUrl` before touching Figma.
- **Section-based, not per-key**: Screenshot entire design sections, not individual text nodes (Figma path only).
- **Verify once per section**: Visually inspect each Figma section URL exactly once. Do not re-verify the same URL for each key that maps to it.
- **Multi-project aware**: Keys can live in different Babel projects. Track `projectId` per key.
- **Batch triage at 20 parallel**: Search up to 20 keys simultaneously to minimize round trips.
- **Update all keys in one parallel wave**: Fire all `babel__update_key` calls at once — they have no dependencies on each other.
- **Handle Figma limits**: Batch image exports (3-5 per call), retry on render timeout with smaller batches.
- **Always confirm mapping** when there are multiple images and multiple keys — never assign images to keys without user confirmation.
- **Context must match key name**: If a key name contains `account_level`, the screenshot MUST show the account-level UI. If it contains `site_level`, use site-level UI. Never use a different context just because the frame looks similar.
- **Text must match key value**: The visible text in the screenshot must match (or closely relate to) the key's English value. If the text shown is different, find a different frame.
- **Avoid sections that are too wide**: Never screenshot an entire section containing many frames — it renders as a tiny unreadable overview. Always screenshot individual frames or sub-frames.
- Do not create keys in Babel.
- Do not update Babel key values.
- Do not silently skip unresolved keys — report every key's status.
- If a required MCP tool is unavailable, say exactly which step is blocked.

## Example prompts

- Process these Babel keys against this Figma file and upload screenshots to Babel.
- Find the Figma section for these keys and attach screenshots in Babel.
- Use `$babel-figma-screenshots` for this key list and Figma URL.
- The Jira ticket has screenshots embedded — upload them to Babel for these keys.
- I'm pasting a screenshot manually — associate it with this key in Babel.
