# Create Localization Keys

Generate localization keys following Wix best practices.

## Output Format

Output keys in this format:
```
feature.page.element → "Value with punctuation included"
```

## Process

1. **Scan the codebase first** — Follow the "Before Starting" step in `rules.md`. Also note the page/component structure of the project.
2. **Ask what UI component or feature needs keys** — Use real feature names and pages found in the codebase as examples in your question (never use invented examples)
3. Generate keys using breadcrumbs naming, matching existing project conventions
4. Output using the format above
5. Verify against the rules in `rules.md`

---

## Rules

Read `rules.md` for the full rule set. All hard rules must be satisfied before outputting keys.

---

## Example Key Structures

> Replace `FEATURE` with the actual feature name from the codebase you scanned. Never use invented feature names — always use real ones from the project.

### Page with Bullets
```
FEATURE.welcomePage.title         → "Main headline"
FEATURE.welcomePage.subtitle      → "Supporting text"
FEATURE.welcomePage.bullet1       → "First benefit"
FEATURE.welcomePage.bullet2       → "Second benefit"
FEATURE.welcomePage.primaryButton → "Main CTA"
```

### Modal with Dynamic Content
```
FEATURE.deleteModal.title         → "Delete {{itemName}}?"
FEATURE.deleteModal.description   → "This action cannot be undone."
FEATURE.deleteModal.cancelButton  → "Cancel"
FEATURE.deleteModal.deleteButton  → "Delete"
```

### Form with Support Link and Pluralization
```
FEATURE.form.emailLabel       → "Email:"
FEATURE.form.emailPlaceholder → "Enter your email"
FEATURE.form.emailError       → "Please enter a valid email address"
FEATURE.form.submitButton     → "Submit"
FEATURE.help.linkText         → "Learn more"
FEATURE.help.linkURL          → "https://support.wix.com/${locale}/article/your-article-slug"
FEATURE.counter               → "{count, plural, =0 {No items} one {# item} other {# items}}"
```

---

## Pre-Submission

Before outputting keys, verify all hard rules from `rules.md` are satisfied.
