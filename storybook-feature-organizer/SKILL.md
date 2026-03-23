---
name: storybook-feature-organizer
description: Use when adding a new component story to a storybook, reorganizing stories by feature, or when stories show translation keys or crash with BI event errors. Works with any storybook project regardless of framework or i18n setup.
---

# Storybook Feature Organizer

## Overview

Adds a new story file, reorganizes existing stories into feature groups, fixes missing i18n keys, and patches missing event function crashes. Fully project-agnostic — detects local conventions before writing anything.

## Step 1 — Ask the User

Ask: **"What component/feature do you want to add to storybook?"**

Then ask: **"Should I also reorganize all existing stories into feature groups?"** (default: yes if not already done)

## Step 2 — Detect Project Conventions (REQUIRED before writing anything)

Read the project before touching any file. Detect:

### Story pattern
Read 2–3 existing `.stories.*` files. Identify:
- Import style (`Meta/storykit`, `Meta/Story`, `storiesOf`, CSF3 with `satisfies Meta`)
- Context/provider wrapper pattern (what providers wrap each story)
- Mock data sources (fixtures, factories, builders)
- Story export style (`export const X = storykit.getComponent(fn)` vs `export const X: Story = { render: () => ... }`)

### Feature groupings
```bash
grep -r "title:" src --include="*.stories.*"
```
Infer feature groups from component names and existing titles. Group by product domain (e.g. skip cycle, pause/resume, checkout, auth).

### i18n interpolation syntax
```bash
# Sample 5–10 values from the existing locale file
grep -m 10 "{" src/assets/locale/messages_en.json   # or wherever locale files live
```
Detect whether the project uses:
- `{variable}` — single braces (i18next with custom interpolation)
- `{{variable}}` — double braces (i18next default)
- `%(variable)s` — Python-style
- Other

**Always match the syntax already in use. Never assume.**

### BI / analytics event pattern
Check how existing stories handle analytics events that fire on mount:
```bash
grep -r "useEffect\|biLogger\|analytics\|track" src/components --include="*.tsx" -l | head -5
```
If analytics calls fire on mount and the installed package may be outdated, check which exported functions are missing:
```bash
cat node_modules/@your/analytics-package/dist/types/index.d.ts | grep "export"
```

## Step 3 — Reorganize Existing Stories

Update `title` fields to use slash-based feature grouping: `features/FeatureName/ComponentName`.

Derive feature groups from the codebase — do not use the groups from this skill as defaults. Group by what makes sense for the product domain you observe.

Use `sed` for bulk title updates:
```bash
sed -i '' "s|title: 'components/FooModal'|title: 'features/FeatureName/FooModal'|g" path/to/FooModal.stories.tsx
```

## Step 4 — Create the New Story File

Place at the same directory as the component. Use the **exact pattern** you detected in Step 2 — not the template below. The template is illustrative only:

```tsx
// Pattern detected from existing stories in THIS project
import { Meta, [storyExportHelper] } from '[storybook-import]';
import { [MockFactory] } from '[mock-path]';
// ... providers detected in step 2

const basicRender = () => (
  <[DetectedProviders]>
    <MyComponent isOpen={true} onClose={() => {}} />
  </[DetectedProviders]>
);

export const { Story: BasicRender } = [storyExportHelper](basicRender);
// or: export const BasicRender: Story = { render: basicRender };

export default {
  title: 'features/[DetectedFeatureGroup]/MyComponent',
} as Meta;
```

Cover at minimum: default state, error/empty state, any subscription-type or user-role variants relevant to the component.

## Step 5 — Fix Missing Analytics/Event Functions

If the component calls event creator functions (e.g. from an analytics package) inside a `useEffect` on mount, and those functions don't exist in the installed package version, the story will crash with `X is not a function`.

**Detect missing functions:**
```bash
# Compare what component imports vs what package exports
grep "from '@your/analytics'" src/components/MyComponent/MyComponent.tsx
cat node_modules/@your/analytics/dist/types/index.d.ts | grep "export function"
```

**Fix:** Polyfill at the top of the stories file, after all imports:
```tsx
import * as analyticsModule from '@your/analytics-package';

const analyticsAny = analyticsModule as any;
const noop = () => ({});
['missingFunction1', 'missingFunction2'].forEach((key) => {
  if (!analyticsAny[key]) analyticsAny[key] = noop;
});
```

This pattern works because webpack compiles ES modules to objects that are mutably patchable at runtime.

## Step 6 — Fix Missing i18n Keys

If a story renders key names instead of strings (e.g. `my-component.title` appears as text):

**1. Find all keys used by the component:**
```bash
grep -rh "t(" src/components/MyComponent/ | grep -oE "'[a-z][^']+'" | sort -u
grep -rh 'i18nKey="' src/components/MyComponent/ | grep -oE '"[a-z][^"]+"' | sort -u
```

**2. Get the real strings from the source of truth.**

⛔ **NEVER invent or guess translation strings.** Key names are not strings.

Ask the user: **"These keys are missing from the locale file. What is the source of truth for translations in this project? (e.g. Babel, Smartling, Phrase, Lokalise)"**

Then retrieve the actual strings from there. Do not write any string to the locale file until you have the real value confirmed by the user or fetched from the translation tool.

**3. Detect interpolation syntax from existing values:**
```bash
grep -m 5 "{" path/to/locale/en.json
```

**4. Add the confirmed strings using the DETECTED syntax:**
```json
"my-component.title": "[VALUE FROM BABEL/TRANSLATION TOOL]",
"my-component.subtitle": "[VALUE FROM BABEL/TRANSLATION TOOL] [DETECTED_SYNTAX]param[/DETECTED_SYNTAX]"
```

## Step 7 — Verify

- No errors in webpack/build logs
- No console errors in browser
- Story renders with real strings (not key names)
- All story variants load without crashing

## Common Mistakes

| Problem | Cause | Fix |
|---|---|---|
| `X is not a function` on mount | Analytics function missing from installed package | Polyfill in stories file (Step 5) |
| Shows key names as text | Key missing from locale file | Get real string from Babel/translation tool, NEVER invent it (Step 6) |
| Interpolation params shown literally (`{{var}}`) | Wrong brace syntax for this project | Detect and match the existing syntax (Step 2) |
| Wrong translation text | String was guessed from key name | ⛔ NEVER infer strings from key names — always get from source of truth |
| Story pattern doesn't match project | Copied template blindly | Always read existing stories first (Step 2) |
| Date in the past breaks component | Mock uses stale date | Override with `addDays(new Date(), N)` |
