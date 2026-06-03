---
name: monday-localizer
description: Use when you need to create a localization item and subitem in the Monday.com board after a Smartling job has been created. Creates the main item with feature metadata and a subitem with wordcount and product details.
---

# Monday Localizer

Create a main item and a subitem in the Monday.com localization board after a Smartling job has been processed.

Do not use raw API credentials or direct HTTP calls. Use Monday MCP tools for all operations.

## Configuration

```
# Boards
BOARD_ID         = 9991668759   # Product Localization Tasks
SUBITEM_BOARD_ID = 9991673115   # Subitems of Product Localization Tasks

# Main item columns (board: 9991668759)
COL_JIRA         = link_mkvjmysa    # Jira ticket link
COL_FIGMA        = link_mkxhhyv6    # Figma design link
COL_EXPERIMENTS  = text_mkxjezkn    # Feature toggle / spec name
COL_WORDCOUNT    = numeric_mm0y1t7h # Total wordcount
COL_MORE_INFO    = link_mkvjsw67    # More Info (use for any extra link if needed)
COL_STORYBOOK    = link_mkxhn4kq    # Storybook link (optional)
COL_STATUS       = color_mkvj6xjp   # Release Status — always set to "In progress" on creation (exact label, lowercase p)
COL_ETA          = date_mm0yhmf9    # ETA date on main item — set to same ETA calculated for the subitem (only when wordcount ≤ 80)
COL_REPOSITORY   = dropdown_mkzcwa5s # Repository (for GA) — short artifact label only, e.g. "business-email-translations"

# Subitem columns (board: 9991673115)
SUBCOL_NAME             = name                  # Subitem name
SUBCOL_TYPE             = color_mkvqvvbb        # Type (status)
SUBCOL_RELATED_PRODUCT  = dropdown_mkvqg648     # Related Product
SUBCOL_LANGUAGES        = color_mkvqrkfy        # Languages (status)
SUBCOL_PRIORITY         = color_mkvq6t6         # Priority (status)
SUBCOL_QA               = color_mkxnx8px        # QA? (status)
SUBCOL_WORDCOUNT        = numeric_mkvq4h0s      # Wordcount
SUBCOL_EST_TIME         = numeric_mkyfwwj6      # Estimated time
SUBCOL_TASK_LINK        = link_mkvq6z0h         # Task Link → Smartling job URL goes here
SUBCOL_JIRA             = link_mkxf9rz2         # Jira link
SUBCOL_TASK_STATUS      = color_mkyf691e        # Task Status
SUBCOL_ETA              = date0                 # ETA date
SUBCOL_ECOMM_PERSON     = multiple_person_mkxh72vw  # eComm-only person column on subitem
SUBCOL_SCORE_COLOR      = color_mm3qayc2        # Content score color — set in Phase 6.5 (Green / Yellow / Red)

# Fixed user assignment
LM_USER_ID = 14828021       # Jacobo Levy — always assigned to LM columns on item and subitem
ECOMM_PERSON_ID = 22720905  # eComm team member — added to SUBCOL_ECOMM_PERSON on eComm subitems only
```

## Naming conventions

These rules are based on how this board is actually used. Follow them exactly.

### Item name
- Use the Jira ticket title, removing any prefixes like `[LOC]`, `[TRANS]`, `[LOC-REVIEW]`, or similar bracket annotations
- Keep it as a high-level feature name: `"Eclipse Package Picker"`, `"Domains purchase flow on Dynamic"`, `"BE cancel modal - cancellation reasons flow"`
- If the ticket title is very long, shorten to the essential feature concept
- If there is no Jira ticket, derive the name from the key namespace or ask the user

### Subitem name
- Start from the item name and add specificity if needed
- Add context in parentheses when the scope is limited: `"Checkout preview (Viewer)"`, `"Error states (Merchant)"`, `"Checkout preview (Additions)"`
- Add qualifiers when it's a partial task: `"Eclipse Package Picker - New Design"`, `"BE cancel modal - Part II"`
- If the item name is already specific and there is only one subitem, the subitem name can match the item name exactly
- Look at the key content (namespaces, values) to determine if extra context is needed for writers

### Stream and related product — from Jira space

Identify the Jira space prefix (the letters before the `-` in the issue key, e.g. `BILL-123` → space is `BILL`).

| Jira space | Related product | Stream (for "More Info" text) |
|---|---|---|
| `BILL` | Premium | `"Billing"` |
| `DOM` | Premium | `"Domains"` |
| `PREM` | Premium | `"Plans"` if about Premium Plans; `"Google Workspace"` if about Business Email |
| `ECP` | eComm | `"eComm"` |

For `PREM` disambiguation:
- If the Jira title or description mentions "Business Email", "Google Workspace", "BE", or "Google Voice" → stream = `"Google Workspace"`
- Otherwise → stream = `"Plans"`

If there is no Jira ticket (key list or Slack input), **ask the user** — do not guess.

### Group placement
Choose the Monday group based on `related_product`:
- `"Premium"` → group `group_mkxhtynn` ("Premium - Jacobo")
- `"eComm"` → group `group_mkzc9m74` ("eComm - Jacobo")

### "More Info" column — stream label
The `COL_MORE_INFO` column (`link_mkvjsw67`) is used as a stream label, not a real link.
Set it with a blank URL and the stream name as text:
```json
{ "url": " ", "text": "Billing" }
```
Replace `"Billing"` with the appropriate stream name for the task.

### Subitem type
- Always set `SUBCOL_TYPE` to `"MTPE"` unless the user explicitly specifies a different type.

## Inputs

Collect before starting:

- `item_name` — derived from Jira title, following naming conventions above
- `subitem_name` — derived from item name + key content context, following naming conventions above
- `related_product` — `"Premium"` or `"eComm"` (from Jira space, or ask user if no Jira)
- `stream` — e.g. `"Billing"`, `"Domains"`, `"Plans"`, `"Google Workspace"`, `"eComm"` → goes in `COL_MORE_INFO` as text label
- `smartling_strings_url` — Smartling strings view URL filtered by tag + IN_PROGRESS status → goes in `SUBCOL_TASK_LINK`
- `jira_url` — Jira ticket URL (or `null`) → goes in `COL_JIRA` and `SUBCOL_JIRA`
- `figma_url` — Figma design URL (or `null`) → goes in `COL_FIGMA`
- `feature_toggle` — feature toggle / spec name (or `null`) → goes in `COL_EXPERIMENTS`
- `wordcount` — total word count from Smartling → goes in `COL_WORDCOUNT` and `SUBCOL_WORDCOUNT`
- `is_urgent` — boolean, default `false`. Set to `true` if the user says "urgente", "urgent", "ASAP" or similar. Affects ETA and Priority columns.
- `repository_label` — optional short artifact label for `COL_REPOSITORY`, e.g. `"business-email-translations"` (not the full `com.wixpress.*` project name)

## Workflow

### 1. Discover available tools

List the Monday MCP tools available in this session. Look for tools that can:
- Create an item on a board: `monday_create_item`, `create_item`, or similar
- Create a subitem: `monday_create_subitem`, `create_subitem`, or similar
- Update item column values: `monday_update_item`, `change_column_value`, or similar
- Get board structure: `monday_get_board`, `get_board`, or similar (use only if needed to verify column IDs)

Adapt tool names to what is actually available.

### 2. Create the main item

Resolve the group ID from `related_product`:
- `"Premium"` → `group_mkxhtynn`
- `"eComm"` → `group_mkzc9m74`

Call the item creation tool with:
- `board_id = BOARD_ID`
- `group_id` = resolved group ID
- `item_name = item_name`

Record the returned `item_id`.

### 3. Set main item column values

Update the main item columns with the provided data.

Set each column that has a non-null value:
- `COL_LM` (`person`) → always `14828021` (Jacobo Levy)
- `COL_STATUS` (`color_mkvj6xjp`) → always `"In progress"` on creation (exact label, lowercase p)
- `COL_ETA` (`date_mm0yhmf9`) → same ETA date calculated for the subitem (only when wordcount ≤ 80; skip if wordcount > 80)
- `COL_JIRA` (`link_mkvjmysa`) → `jira_url`
- `COL_FIGMA` (`link_mkxhhyv6`) → `figma_url`
- `COL_EXPERIMENTS` (`text_mkxjezkn`) → `feature_toggle`
- `COL_WORDCOUNT` (`numeric_mm0y1t7h`) → `wordcount`
- `COL_MORE_INFO` (`link_mkvjsw67`) → stream label. Use a blank URL and stream name as text: `{ "url": " ", "text": "Billing" }`. Always set this — it's how the stream is identified in Monday.

If the Monday MCP supports setting column values during item creation, do it in one call. Otherwise, update each column individually.

For the repository dropdown:
- Use the **short label** that exists in Monday, not the DevEx `projectName`
- Example: `com.wixpress.business-email-translations` must be converted to `business-email-translations`
- If Monday rejects the label, inspect the error message and retry with the exact existing label it lists

For link columns, use the Monday link column format with a descriptive label:
- Jira links → `{ "url": "https://...", "text": "Jira" }`
- Figma links → `{ "url": "https://...", "text": "Figma" }`

Skip columns whose values are `null` — do not set them to empty strings.

### 4. Create the subitem

Call the subitem creation tool with:
- `parent_item_id = item_id`
- `item_name = subitem_name`

Record the returned `subitem_id`.

### 5. Set subitem column values

**Column order matters** — Monday automations trigger based on the sequence columns are updated. Always set columns left-to-right, with ETA in a **separate final call**.

**Call 1 — all columns except ETA (in this order):**
1. `SUBCOL_TYPE` (`color_mkvqvvbb`) → `"MTPE"` (or user-specified type)
2. `SUBCOL_RELATED_PRODUCT` (`dropdown_mkvqg648`) → `related_product`
3. `SUBCOL_WORDCOUNT` (`numeric_mkvq4h0s`) → `wordcount`
4. `SUBCOL_TASK_LINK` (`link_mkvq6z0h`) → `smartling_strings_url` — text `"Smartling"`
5. `SUBCOL_JIRA` (`link_mkxf9rz2`) → `jira_url` — text `"Jira"`
6. `SUBCOL_LM` (`multiple_person_mkzdq7y4`) → `14828021` (Jacobo Levy)
7. `SUBCOL_ECOMM_PERSON` (`multiple_person_mkxh72vw`) → `22720905` — **eComm tasks only** (when `related_product = "eComm"`); omit for Premium
8. `SUBCOL_LANGUAGES` (`color_mkvqrkfy`) → `"Account + Viewer"` if `is_uou = true`; omit if false

**Call 2 — ETA only (always last):**
8. `SUBCOL_ETA` (`date0`) → calculated ETA date in `YYYY-MM-DD` format (only when wordcount ≤ 80)
   OR `SUBCOL_TASK_STATUS` (`color_mkyf691e`) → `"Ready for ETA"` (when wordcount > 80)

For link columns, use the Monday link format with descriptive labels:
- Smartling → `{ "url": "https://...", "text": "Smartling" }`
- Jira → `{ "url": "https://...", "text": "Jira" }`

For the dropdown column (`SUBCOL_RELATED_PRODUCT`), use:
```json
{ "labels": ["Premium"] }
```
or
```json
{ "labels": ["ecom-Platform"] }
```

For the status column (`SUBCOL_TYPE`), use the Monday status format — check the label value for `"MTPE"` using the board schema if needed.

Skip columns whose values are `null`.

### ETA and priority logic (subitem)

Apply these rules based on `wordcount` and `is_urgent` at the time of subitem creation.

**Work week: Sunday–Thursday. Friday, Saturday, and Israeli public holidays are non-working days.**

**Israeli public holidays — fetch dynamically from Hebcal:**

Before calculating ETA, call this URL to get the current year's Israeli public holidays:
```
https://www.hebcal.com/hebcal?v=1&cfg=json&year={YEAR}&c=off&i=on&lg=s&maj=on
```
(replace `{YEAR}` with the current year, e.g. `2026`)

From the response, treat as non-working days any item where:
- `category = "holiday"` AND `subcat = "major"`
- AND the title does **not** contain `(CH''M)` — those are Chol HaMoed (intermediate days, worked normally)
- AND the title does **not** start with `Erev` — those are eves (day before, not a holiday)

This returns the actual Yom Tov days: Pesach I, Pesach VII, Shavuot, Rosh Hashana I & II, Yom Kippur, Sukkot I, Shemini Atzeret/Simchat Torah, and Yom HaAtzma'ut.

When advancing days for ETA, skip any date that is a Friday, Saturday, or a holiday from the above API. Move to the next valid working day if the calculated date lands on one.

#### If wordcount ≤ 80:

Calculate ETA date:
1. **Always verify the current date and time using the Bash tool** — do NOT rely on the system-reminder date, which can be stale or incorrect:
   ```bash
   date
   ```
   Use the output to determine today's date and current time in Israel (UTC+3 summer / UTC+2 winter).
2. If `is_urgent = true` → ETA = today + 2 working days, regardless of current time. Set `SUBCOL_PRIORITY` (`color_mkvq6t6`) to label `"URGENT"`.
3. Else if current time < 14:00 → ETA = today + 2 working days.
4. Else (current time ≥ 14:00) → ETA = today + 3 working days.

**Working day = not Friday, not Saturday, not an Israeli public holiday.**

Set:
- `SUBCOL_ETA` (`date0`) → calculated ETA date in `YYYY-MM-DD` format
- `SUBCOL_PRIORITY` (`color_mkvq6t6`) → `"URGENT"` only if `is_urgent = true`; otherwise leave unset

#### If wordcount > 80:

- Set `SUBCOL_TASK_STATUS` (`color_mkyf691e`) → label `"Ready for ETA"`
- Do **not** set `SUBCOL_ETA` — leave it empty

### 6. Return structured output

```
## Monday — Item Created

**Board:** [BOARD_ID]
**Item:** [item_name] (ID: [item_id])
**Subitem:** [subitem_name] (ID: [subitem_id])

**Fields set:**
- Smartling job: [URL]
- Figma: [URL or "not set"]
- Feature toggle: [name or "not set"]
- Related product: [name]
- Wordcount: [N words]

**Monday item link:** https://[your-workspace].monday.com/boards/[BOARD_ID]/pulses/[item_id]
```

If any column update fails, report which column and continue with the rest.

## Rules

- Always create the main item before the subitem.
- If `BOARD_ID` or `SUBITEM_BOARD_ID` is still `FILL_IN`, stop and ask the user to provide the board IDs.
- If a column ID is `FILL_IN`, skip that column and note it in the output.
- Do not delete or modify existing items.
- If Monday MCP is unavailable, report exactly which tool is missing.

## Example prompts

- Use `$monday-localizer` to create a Monday item for "Business Email Q3" with Smartling job https://... and wordcount 340.
- Create the Monday item and subitem for this localization run.
