---
name: localization-guidelines
description: >-
  Creates and reviews localization (i18n) keys following Wix best practices.
  Use when creating new translation keys, reviewing existing keys for compliance,
  adding user-facing text to UI components, working with translation files,
  or converting hardcoded text to localized keys.
metadata:
  version: 1.0.0
  author: Wix
---

# Localization Guidelines

Help users work with localization (i18n) keys following Wix best practices.

## Intent Detection

1. If the user explicitly asks to create, review, or fix keys, proceed with that option
2. If the user provides existing keys or a file with keys, default to **review** mode
3. If the user describes a UI component or feature needing text, default to **create** mode
4. If the user asks to scan or fix code for localization issues, default to **fix** mode
5. If the intent is ambiguous, ask which they'd like to do

## Instructions

### Option 1: Create Keys
Read the file `references/create-keys.md` and use it as your guide. Follow its rules and output format.

**Important:** Before asking the user any questions, scan the codebase for existing localization files and source code to discover real feature names, page names, and existing key conventions. Use these as examples when prompting the user — never use invented or generic feature names.

### Option 2: Review Keys
Read the file `references/review-keys.md` and use it as your guide. Check keys against its rules and use its output format.

### Option 3: Fix Issues
Read the file `references/fix-keys.md` and use it as your guide. Scan code for localization violations and propose fixes.

## Quick Example

**User:** "Create keys for a delete confirmation modal in the products feature"

**Output:**
```
products.deleteModal.title         → "Delete product?"
products.deleteModal.description   → "This action cannot be undone."
products.deleteModal.cancelButton  → "Cancel"
products.deleteModal.deleteButton  → "Delete"
```

## Edge Cases

- **No existing localization files**: Use the breadcrumbs structure from the rules as the starting convention
- **Inconsistent existing conventions**: Flag the inconsistency to the user and suggest which convention to follow going forward
- **Mixed create + review request**: Handle creation first, then review the created keys
- **Changing existing keys**: Remind the user to notify the EN Writer and Localization Manager before making changes

## Resources

- **ICU validator:** https://format-message.github.io/icu-message-format-for-translators/editor.html
- **Format library:** https://bo.wix.com/pages/yoshi/docs/editor-flow/runtime-api/formatter
