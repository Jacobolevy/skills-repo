# Review Localization Keys

Check keys for compliance with Wix localization best practices.

**Scope:** This skill reviews KEY NAMES and KEY VALUES. It may also check code if provided to detect issues like split sentences.

## Process

1. **Scan the codebase first** — Follow the "Before Starting" step in `rules.md`. Also note any project-specific patterns to compare against.
2. Get keys from user (or find them in current file)
3. Check each key against the rules in `rules.md`
4. Output a report with status for each key

---

## Severity Levels

Check each key against the rules in `rules.md` and classify issues as:

- **FAIL** — Hard rule violations (all rules in the "Hard Rules" table)
- **WARNING** — Missing ICU `=0` case (only when zero state is possible)
- **INFO** — Reusable key exists, inconsistent terminology, conventions mismatch, ICU not validated, or modifying an existing key (remind to notify EN Writer + Loc Manager)

---

## Output Format

```
📋 Localization Key Review

✅ PASS: payLinks.firstVisit.title
   Breadcrumbs: ✓ | lowerCamelCase: ✓ | Complete: ✓

✅ PASS: blogPosts.commentsPage.replyButton
   Breadcrumbs: ✓ | lowerCamelCase: ✓ | Complete: ✓

❌ FAIL: delete
   Missing breadcrumbs structure
   Fix: Use context like "products.list.deleteButton"

❌ FAIL: items_plural
   Legacy plural suffix
   Fix: Use ICU format "{count, plural, one {# item} other {# items}}"

⚠️ WARNING: orders.count = "{count, plural, one {# order} other {# orders}}"
   Missing =0 case
   Consider: "{count, plural, =0 {No orders} one {# order} other {# orders}}"

ℹ️ INFO: feature.submitButton
   Project uses "primaryButton" elsewhere - consider consistency

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Summary: 2 passed | 2 failed | 1 warning | 1 info
```
