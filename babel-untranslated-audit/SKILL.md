---
name: babel-untranslated-audit
description: >
  Audit a Babel i18n project (triggered by an n8n workflow payload) to find translation keys that
  need attention — either never translated or outdated (English was updated after the translation).
  Applies a 5-minute seeding window and a per-key confidence filter (ratio of genuinely translated
  languages) to suppress false positives. After the audit, triggers the localization translation and
  review workflow for all outdated and never-translated keys. Use this skill for: "audit translations
  from n8n", "find missing or outdated translations", "which keys need translation or re-translation",
  "translation sync audit".
---

# Babel Translation Sync Audit (n8n-driven)

Receives an n8n payload, audits a Babel project for untranslated or outdated keys, filters out
false positives using a per-key confidence level, then triggers the localization workflow for
flagged keys. Pushes results to Base44.

---

## Tools available

- `babel__sync_project` — trigger a Smartling sync (fire-and-forget)
- `babel__search_keys` — list keys filtered by locale (includes `value` + `updatedDate`)

**Do NOT use `babel__get_key` per key** — it only returns the EN entry, not per-language dates.
**Do NOT delegate to background agents** — fetch data directly with parallel tool calls.

---

## Step 0 — Parse the n8n payload

The skill is invoked with a structured payload from the n8n workflow. Extract:

| Field | Description |
|-------|-------------|
| `projectId` | Babel project ID (required) |
| `targetLanguages` | List of language codes to audit (e.g. `["FR","DE","ES"]`). If absent, default to all 21 BM target languages |
| `projectName` | Optional display name for Base44 / summaries |

If `targetLanguages` is omitted, use all 21 BM target languages (see locale table in Step 3).

---

## Step 1 — Sync from Smartling (fire-and-forget)

```
babel__sync_project(projectId: <projectId>)
```

Do not wait for the sync to complete — proceed immediately.

---

## Step 2 — Fetch all EN keys (paginated)

```
babel__search_keys(projectId: <projectId>, locale: "en", limit: 100)
```

Paginate until cursor is null. **Deduplicate**: for keys that appear more than once, keep only the
entry with the most recent `updatedDate`.

Build EN map: `key_name → {updatedDate, value}`

---

## Step 3 — Fetch target locale keys (parallel batches)

Fetch only the locales listed in `targetLanguages` from the payload. If the payload didn't include
`targetLanguages`, use the full 21-language list below.

| Code | Locale IDs to try (first match wins) |
|------|--------------------------------------|
| FR | fr-FR, fr |
| DE | de-DE, de |
| ES | es-ES, es |
| PT | pt-BR, pt, pt-PT |
| RU | ru-RU, ru |
| JA | ja-JP, ja |
| NL | nl-NL, nl |
| IT | it-IT, it |
| TR | tr-TR, tr |
| UK | uk-UA, uk |
| PL | pl-PL, pl |
| KO | ko-KR, ko |
| CS | cs-CZ, cs |
| SV | sv-SE, sv |
| DA | da-DK, da |
| TH | th-TH, th |
| NO | no-NO, nb-NO, nb, no |
| ZH | zh-TW, zh-CN, zh |
| ID | id-ID, id |
| VI | vi-VN, vi |
| HI | hi-IN, hi |

```
babel__search_keys(projectId: <projectId>, locale: <locale_id>, limit: 100)
```

Fetch multiple locales in parallel (5–10 at a time). Paginate each until cursor is null.
If a locale returns PERMISSION_DENIED, skip it gracefully and try the next locale ID for that
language; if all IDs fail, skip the language entirely.

**Deduplicate**: for the same key+locale pair, keep only the entry with the most recent
`updatedDate`.

Build TX map: `key_name → lang_code → {updatedDate, value}`

---

## Step 4 — Per-key confidence level

Before classifying individual languages, determine how "translated" each key is overall:

```python
for key_name, en_entry in en_map.items():
    en_val = en_entry['value']
    target_langs = [lang for lang in target_languages if key_name in tx_map]

    genuinely_translated = sum(
        1 for lang in target_langs
        if tx_map[key_name].get(lang, {}).get('value', en_val) != en_val
    )
    total = len(target_langs)
    ratio = genuinely_translated / total if total > 0 else 0

    if ratio >= 0.80:
        continue  # Key is clearly being translated — skip entirely

    if 0.20 <= ratio < 0.80:
        missing_status = "likely_false_positive"  # Rollout in progress
    else:
        missing_status = "never_translated"       # Barely or never touched
```

`missing_status` is the label applied to any flagged language on this key in Step 5.

---

## Step 5 — Per-language classification

For each key that passed the confidence check (ratio < 80%), classify each target language:

```python
SEEDING_WINDOW_SEC = 300  # 5 minutes

for lang_code in target_languages:
    tx_entry = tx_map.get(key_name, {}).get(lang_code)

    if tx_entry is None:
        # No entry at all → flag
        flag(lang_code, status=missing_status)
        continue

    tx_date = parse_iso(tx_entry['updatedDate'])
    tx_val  = tx_entry['value']
    en_date = parse_iso(en_entry['updatedDate'])
    en_val  = en_entry['value']
    lag_sec = (en_date - tx_date).total_seconds()  # positive = EN is newer

    if abs(lag_sec) <= SEEDING_WINDOW_SEC and tx_val == en_val:
        # Entry exists, same value as EN, created within 5 min → Babel bulk-seeded placeholder
        flag(lang_code, status=missing_status)

    elif abs(lag_sec) <= SEEDING_WINDOW_SEC and tx_val != en_val:
        pass  # Different value within 5 min → fast real translation → in sync

    elif lag_sec > SEEDING_WINDOW_SEC:
        # EN was updated more than 5 min after the translation → outdated
        days_behind = lag_sec / 86400
        flag(lang_code, status="outdated", days_behind=days_behind)

    else:
        pass  # TX is newer than EN → in sync
```

**Situation summary:**

| Situation | Flag? | Status |
|-----------|-------|--------|
| No translation entry | ✅ | `missing_status` |
| Same value as EN + within 5 min | ✅ | `missing_status` (bulk-seeded placeholder) |
| Different value + within 5 min | ❌ | In sync (fast real translation) |
| EN updated > 5 min after TX | ✅ | `outdated` + days behind |
| TX updated after EN (> 5 min) | ❌ | In sync |

---

## Step 6 — Aggregate (one record per key)

Combine all flagged languages for a key into a single row. Worst status wins:
`outdated` > `never_translated` > `likely_false_positive`

```json
{
  "keyName": "my.key.name",
  "affectedLanguages": "FR,DE,ES",
  "affectedLanguagesCount": 3,
  "translatedLanguages": "IT,JA,KO",
  "translatedLanguagesCount": 3,
  "status": "outdated",
  "maxDaysOutOfSync": 83.2
}
```

- `status`: `"outdated"` if any affected lang is outdated; else `"never_translated"` or
  `"likely_false_positive"` based on `missing_status`.
- `maxDaysOutOfSync`: max across all affected languages (null for non-outdated keys).
- `translatedLanguages`: target langs that are in sync (not flagged).

**Sort order**: outdated first (by `maxDaysOutOfSync` desc), then `never_translated`, then
`likely_false_positive` (both by `affectedLanguagesCount` desc).

---

## Step 7 — Push to Base44

Base44 REST API: `https://babel-localization-audit.base44.app/api`
Auth header: `api_key: 32b30a7370f5427f9b26a7d0c798329d`

**Always use `api_key` header (NOT `x-api-key`).**

### 7a — Register/update project in BabelProject

```python
existing = GET /entities/BabelProject
found = next((p for p in existing if p['projectId'] == PROJECT_ID), None)
if not found:
    POST /entities/BabelProject {"name": <project_name>, "projectId": PROJECT_ID, "lastAuditDate": <today_iso>}
else:
    PUT /entities/BabelProject/<found['id']> {"lastAuditDate": <today_iso>}
```

### 7b — Create AuditRun

```python
run = POST /entities/AuditRun {
    "projectId": PROJECT_ID,
    "projectName": <project_name>,
    "runDate": <today_iso>,
    "status": "running"
}
run_id = run['id']
```

### 7c — Bulk push AuditResult (batches of 50)

```python
POST /entities/AuditResult/bulk [batch_of_50]
```

Each result includes: `auditRunId`, `projectId`, `keyName`, `affectedLanguages`,
`affectedLanguagesCount`, `translatedLanguages`, `translatedLanguagesCount`, `status`,
`maxDaysOutOfSync`.

### 7d — Finalize AuditRun

```python
PUT /entities/AuditRun/<run_id> {
    "status": "complete",
    "totalFlagged": N,
    "outdatedCount": N_outdated,
    "neverTranslatedCount": N_never,
    "likelyFalsePositiveCount": N_fp
}
```

---

## Step 8 — Trigger translation and review for flagged keys

For all keys with `status` of `"outdated"` or `"never_translated"` (exclude `"likely_false_positive"`):

1. Collect the key names and the specific affected languages from the payload's `targetLanguages`.
2. Invoke `/localization-workflow` (or the relevant translation skill) with:
   - The list of flagged key names
   - The affected language codes per key
   - Context: source = n8n audit, project = `<projectName>`
3. After translation is submitted, invoke the review skill for those same keys.

Skip `"likely_false_positive"` keys — they are flagged only for visibility and should not trigger
translation automatically (a rollout is likely already in progress).

---

## Step 9 — Output to user

Print a summary table (outdated first, then never_translated, then likely_false_positive):

```
| Key | Status | Affected Langs | Days Out of Sync |
|-----|--------|----------------|-----------------|
| my.key.name | outdated | FR, DE, ES (3) | 83 |
| other.key | never_translated | IT, JA (2) | — |
| maybe.key | likely_false_positive | KO (1) | — |
```

End with:
> **N keys flagged: X outdated, Y never translated, Z likely false positives.**
> Results pushed to Base44: https://babel-localization-audit.base44.app
> Translation workflow triggered for X+Y keys.

---

## Why the 5-minute seeding window?

When engineers import keys programmatically, Babel creates entries for all locales simultaneously
— English and every translation — within seconds, all pre-filled with the English text. Without
this check, every locale would look "translated" (entry exists, same date as English), but it's
actually just a placeholder. The 5-minute (300-second) window catches this pattern: same value AND
created at nearly the same moment as English → never actually translated.

## Why "likely false positive" vs "never translated"?

If ≥20% of target languages already have a genuinely different value from English, the key is
probably being translated in an in-progress rollout. Flagging those remaining languages as
"never_translated" would be misleading — they're just behind. So they get a lower-confidence label
("likely_false_positive") to signal they need attention without alarming the team.

If <20% are translated → clearly nobody has touched this key → "never_translated".

---

## Performance notes

- Fetch locale pages in parallel batches — never serially one-by-one
- Do NOT call `babel__get_key` per key — it's slow and doesn't return TX dates
- Do NOT delegate to background agents — fetch directly
- Tool result files (large pages) are parsed as:
  ```python
  outer = json.loads(raw_file_content)
  inner = json.loads(outer['content'][0]['text'])
  keys = inner['keys']  # [{id, name, value, locale, updatedDate, createdDate}]
  ```
- Inline responses (small final pages) are parsed directly from the tool call result
