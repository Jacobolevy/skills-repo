# Skills

A collection of custom AI agent skills for Claude Code, Cursor, and Codex.

## Skills

### [`localization-guidelines`](./localization-guidelines/)
Localization (i18n) skill for Wix projects. Supports three modes:
- **Create** — Generate new translation keys following breadcrumb structure (`feature.page.element`)
- **Review** — Check existing keys against rules
- **Fix** — Scan code for localization violations

### [`smartling-tag-manager`](./smartling-tag-manager/)
Smartling API integration for bulk tagging strings. Resolves project IDs, accepts keys from CSV/clipboard/file, deduplicates and tags in bulk batches of 1000.

### [`babel-figma-screenshots`](./babel-figma-screenshots/)
Batch workflow that maps Babel key names to Figma design sections and uploads screenshots. Handles annotation matching, frame exploration, batch export, and per-key status reporting.
