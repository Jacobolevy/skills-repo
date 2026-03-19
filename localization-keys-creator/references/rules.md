# Localization Rules

Canonical rules for Wix localization keys. Referenced by `create-keys.md`, `review-keys.md`, and `fix-keys.md`.

## Before Starting (all workflows)

Scan the project's existing localization files (e.g., `*.json` locale files, `messages_en.json`, `translations/`, `locales/`, or similar) and source code to discover:
- Existing feature names and key prefixes already in use
- The naming conventions the project follows
- Whether the project uses consistent terminology (e.g., `button` vs `cta`)

## Hard Rules (must fix)

| Rule | Requirement | Example |
|------|-------------|---------|
| **Breadcrumbs structure** | Keys must use `feature.page.element` pattern | `payLinks.firstVisit.title` |
| **lowerCamelCase** | Must start lowercase (underscores/hyphens allowed but not preferred) | `blogPosts.commentsPage.replyButton` |
| **Full words** | No abbreviations (except `cta`, `url`, `id`, `api`) | `createCampaignPage` not `createCmpgnPage` |
| **No generic names** | Keys must have context | `products.deleteModal.confirmButton` not `delete` |
| **Complete sentences** | Never split text across multiple keys — use `<1>tags</1>` or `{{params}}` for dynamic parts | See below |
| **Punctuation in values** | Include ALL punctuation in key values, not in code | Value: `"Email:"` not `"Email"` with `:` in code |
| **Separate URL keys** | Support article links (support.wix.com) with static locales need `.linkText` and `.linkURL` | `feature.help.linkText` + `feature.help.linkURL` |
| **Valid characters** | Pattern: `/^[a-zA-Z0-9._-]{1,350}$/` | No spaces, `@`, `/`, `'`, or special chars |
| **Length 1-350** | Key names must be 1-350 characters | |
| **Unique keys** | No duplicates within namespace | Check before adding new key |
| **Legacy plural suffix** | Keys must NOT end in `_plural`, `_zero`, `_one` | Use ICU format instead |

### Split Sentences — How to Fix

```
❌ WRONG — Sentence split across two keys:
footer.text     → "This feature is part of your {{PremiumPlanLink}}"
footer.planLink → "Premium Plan"

✅ CORRECT — Use numbered tags to keep the full sentence in one key:
footer.text → "This feature is part of your <1>Premium Plan</1>"

✅ ALSO CORRECT — Use inline parameter when no link/formatting is needed:
footer.text → "This feature is part of your {{planName}}"
```

### URL Key Exceptions (not violations)

- URLs with dynamic locale variables (`${locale}`, `${accountLanguage}`, `${siteLanguage}`) — already localized in code
- Non-support URLs (www.wix.com, internal routes) — not KB-managed

## Warnings

| Check | What to look for | Suggestion |
|-------|------------------|------------|
| **Missing ICU =0 case** | `{count, plural, one {...} other {...}}` without `=0` | Add `=0 {No items}` if zero state is possible |

## Best Practices

- **Check existing keys** — Reuse when text matches exactly
- **Consistent terminology** — Pick `button` OR `cta` and stick with it project-wide
- **Match existing conventions** — For existing projects, follow what's already there
- **Test ICU syntax** — Validate at https://format-message.github.io/icu-message-format-for-translators/editor.html
- **Notify on key changes** — Before changing existing keys, notify EN Writer and Localization Manager
