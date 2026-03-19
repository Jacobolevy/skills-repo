# Figma and Babel Details

Practical reference for Figma API behavior, Babel key handling, error recovery, and reporting format.

## Figma API realities

### Annotations and comments (fast path)

Figma files can contain **comments** (via `get-file-comments`) and **annotations** (metadata attached to nodes). These are the fastest way to match Babel keys to Figma frames.

**What to look for in comments:**

| Pattern in comment text | What it means |
|---|---|
| Exact key name (e.g., `cart-core.removeDomainModal.title`) | Direct match to a Babel key |
| Key value text (e.g., "Remove {domainName}?") | The comment describes UI containing this key |
| Key name fragment (e.g., `removeDomainModal`) | Partial match — verify by checking the node |
| Jira ticket references | May link to the feature that uses the keys |

**Comment structure:**

```json
{
  "id": "123456",
  "message": "cart-core.removeDomainModal.title",
  "client_meta": {
    "node_id": "10457:222279",
    "x": 100,
    "y": 200
  }
}
```

The `client_meta.node_id` tells you exactly which Figma node the comment is attached to. This is your screenshot target (or its parent frame if the node is too small).

**What to look for in node names/descriptions:**

When exploring the node tree, also check:

- Frame/section names that match key name segments (e.g., frame "Remove Domain Modal" → `removeDomainModal.*` keys)
- Header text nodes inside `header-section` frames that describe the section's purpose (e.g., "Business Email line item → change seats - More than 20 seats")
- Description text nodes that explain the scenario being shown

**Why this is faster:** One `get-file-comments` call can resolve multiple keys at once, without needing to explore the entire file structure level by level.

### No text search

The Figma API does not support searching for text content. To find where a piece of text appears, you must:

1. Fetch the node tree (via `get-file` or `get-file-nodes`).
2. Parse the JSON response locally.
3. Search through `TEXT` type nodes for matching `characters` values.

For large files, this means saving the response to disk and parsing with a script. Example approach:

```python
import json

with open('figma-nodes.json') as f:
    data = json.load(f)

def find_text_nodes(node, path=""):
    current_path = f"{path} > {node.get('name', '?')}"
    if node.get('type') == 'TEXT':
        print(f"  Text: {node.get('characters', '')[:80]}")
        print(f"  Path: {current_path}")
        print(f"  ID:   {node.get('id')}")
        print()
    for child in node.get('children', []):
        find_text_nodes(child, current_path)

for node_id, node_data in data.get('nodes', {}).items():
    find_text_nodes(node_data.get('document', {}))
```

In practice, **you rarely need text search**. The section-based approach (mapping key groups to Figma sections by semantic understanding) is faster and more reliable.

### File structure conventions

Figma files for product design typically follow this hierarchy:

```
File
├── Page: "Dev handoff" / "Designs" / "Specs"
│   ├── Section: "Full flows"
│   │   ├── Frame: "Domain purchase / cart"
│   │   ├── Frame: "Checkout summary"
│   │   └── Frame: "Business email + domain"
│   ├── Section: "Errors + States"
│   │   ├── Frame: "Page load errors"
│   │   ├── Frame: "Checkout errors"
│   │   ├── Frame: "Domain availability"
│   │   └── Frame: "Business email errors"
│   └── Section: "Modals"
│       ├── Frame: "Remove domain"
│       └── Frame: "Replace domain"
└── Page: "Exploration" / "Archive" (ignore these)
```

Focus on the "Dev handoff" or equivalent page. Ignore exploration/archive pages.

### Image export

**`figma__get-image` behavior**:

- Accepts comma-separated node IDs.
- Returns S3 URLs per node ID.
- Use `format: "png"` and `scale: 2` for high-quality screenshots.
- **Render timeout**: Requests with too many or too large nodes fail with HTTP 400 "Render timeout." Start with 3-5 nodes per batch. If it fails, reduce to 1-2 nodes per batch.
- **Null images**: Sometimes a node returns `null` instead of a URL. This usually means the node is empty or hidden. Skip it and note the failure.

**S3 URL lifetime**: Figma image URLs (`https://figma-alpha-api.s3.us-west-2.amazonaws.com/images/<uuid>`) appear to be long-lived but are not officially guaranteed to be permanent. They work reliably as `imageContextUrl` values for Babel. If a URL stops working in the future, re-export the image.

### Efficient exploration strategy

1. `get-file` with `depth: 1` → page names and IDs.
2. `get-file-nodes` on relevant page with `depth: 1` → section names and IDs.
3. `get-file-nodes` on relevant sections with `depth: 1` → frame names and IDs.
4. Stop here. You now have enough structure to map keys to frames.

Do not fetch the full file at full depth — it can be tens of MB and will overwhelm processing.

## Babel key handling

### Multi-project keys

Keys from a single product often span multiple Babel projects. Common patterns:

| Key prefix | Typical project scope |
|---|---|
| `cart-core.*` | Core cart project |
| `anonymous-cart-standalone.*` | Standalone anonymous cart project |
| `anon-cart.*` | Anonymous cart project (may overlap with above) |
| `domain_search_suite.*` | Domain search project |
| `domains-search-gate.*` | Domain search gate project |
| `anonCart.*` | Anonymous cart (camelCase variant) |

Always record the `projectId` returned by `search_keys` — you need it for `update_key`.

### Duplicate keys across features

A single key name can appear multiple times in the same project under different `featureName` values (e.g., `"messages"` vs `"cart-core"`). When this happens:

- Prefer the one under `featureName: "messages"` — this is the standard feature for localization keys.
- If both have the same value, either one works for attaching a screenshot.

### Search strategies

**Primary**: Use `name` (exact match) + `locale: "en"`:
```
search_keys(name="cart-core.removeDomainModal.title", locale="en")
```

**Fallback 1**: Use `searchExpression` (fuzzy) if exact name fails:
```
search_keys(searchExpression="removeDomainModal.title", limit=5)
```

**Fallback 2**: Search without `locale` filter to see if the key exists in other locales but not English:
```
search_keys(name="cart-core.error.toast.remove.technical")
```

**Fallback 3**: Search across different project IDs if the key prefix suggests a different project.

### Update key safely

When calling `update_key`:

- Always pass the current `revision` to prevent conflicts.
- Only set `imageContextUrl`. Do not pass `value`, `name`, or other fields you don't intend to change.
- If you get a revision conflict, re-fetch the key with `search_keys` to get the latest revision and retry once.

## Error recovery

| Problem | Solution |
|---|---|
| Figma render timeout | Reduce batch size to 1-2 nodes, retry |
| Figma node returns null image | Skip node, mark as `render_error` |
| Babel key not found by name | Try `searchExpression`, then without locale |
| Babel revision conflict | Re-fetch key, retry with new revision |
| Babel key found in wrong project | Record actual `projectId`, proceed |
| Figma response too large to process | Save to file, parse with Python script |
| Multiple Figma sections could match a key | Ask the user |

## Report format

### Per-key table

```markdown
| # | key | status | project | figma_section | note |
|---|-----|--------|---------|---------------|------|
| 1 | cart-core.removeDomainModal.title | updated | c6ac963f | Remove domain `10457:222279` | — |
| 2 | cart-core.removeDomainModal.content | already_done | c6ac963f | — | Had screenshot before run |
| 3 | cart-core.error.toast.remove.technical | not_found | — | — | Not found in any project |
```

### Statuses

| Status | Meaning |
|---|---|
| `updated` | Screenshot uploaded this session |
| `already_done` | Key already had `imageContextUrl` |
| `not_found` | Key does not exist in Babel |
| `upload_error` | Babel update failed (include error) |
| `no_section` | Could not map key to a Figma section |
| `render_error` | Figma image export failed |

### Totals line

```
Totals: X updated · X already_done · X not_found · X upload_error · X no_section · X render_error
```

### Grouping in report

When many keys share the same Figma section, group them:

```
Section: "Remove domain errors" (10457:222279)
  → Image: https://figma-alpha-api.s3.us-west-2.amazonaws.com/images/...
  → Keys updated (4):
    - cart-core.removeDomainModal.title
    - cart-core.removeDomainModal.content
    - cart-core.removeDomainModal.primaryButton
    - cart-core.removeDomainModal.secondaryButton
```

This makes the report easier to verify — the user can check one screenshot against all its keys at once.
