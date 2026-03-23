---
name: storybook-feature-organizer
description: Use when adding a new component story to the billing-subscriptions-bm storybook, reorganizing stories by feature, or when storybook stories are flat under "components/" and need to be grouped by feature. Also use when a new story renders but shows translation keys or BI event crashes.
---

# Storybook Feature Organizer

## Overview

Adds a new `.stories.tsx` to the billing-subscriptions-bm storybook, reorganizes existing stories under `features/FeatureName/ComponentName` titles, fixes missing i18n keys, and patches missing BI event functions.

## Step 1 — Ask the User

Ask: **"What component/feature do you want to add to storybook?"**

Then ask: **"Should I also reorganize all existing stories into feature groups?"** (default: yes if not already done)

## Step 2 — Explore Before Writing

Before touching any file:
- Read 2–3 existing `.stories.tsx` files to learn the exact local pattern
- Run: `grep -r "title:" src --include="*.stories.*"` to see current groupings
- Read the target component to find: props, context dependencies, BI imports, i18n keys used

## Step 3 — Reorganize Existing Stories

Update the `title` field in each story file using the slash-based group:

| Group | Title pattern | Components |
|---|---|---|
| Skip Cycle | `features/SkipCycle/ComponentName` | SkipCycleModal, SkipCycleBetweenDatesModal, SkipOrderStatusSection, ResumeOrdersNow/OnNextCycle/RescheduleNextOrder/RevertOrderScheduleModal |
| Pause/Resume | `features/PauseResume/ComponentName` | PauseModal, ResumeModal, PauseStatusSection, EditResumeDateModal, CancelScheduledPauseModal, GracePeriodPauseModal |
| Subscription Lifecycle | `features/SubscriptionLifecycle/ComponentName` | CancelModal, ReactivateModal, SuspendModal, AutoRenewOnModal, ExtendDateModal, MarkAsPaidModal |
| Others | keep as `components/`, `pages/`, `other/` |

Use `sed` for bulk updates when changing many titles at once.

## Step 4 — Create the New Story File

Place at `src/components/ComponentName/ComponentName.stories.tsx`.

Follow this exact pattern:

```tsx
import React from 'react';
import { aContact } from '@wix/ambassador-contacts-v4-contact/builders';
import { Meta, storykit } from '@wix/yoshi-flow-bm/storybook';
import { recurringPaymentSubscription } from '../../../__tests__/mocks/SubscriptionsMocks';
import { InitiatorProvider } from '../../contexts/InitiatorContext';
import {
  SubscriptionDetailsContext,
  SubscriptionDetailsDispatchContext,
} from '../../hooks/SubscriptionDetailsProvider';
import { ActionModalInitiator } from '../../types/EnumsCommon';
import { MyComponent } from './MyComponent';

const contact = aContact({ info: { name: { first: 'John', last: 'Doe' } } });

const ContextProvider = ({ children }: { children: React.ReactNode }) => {
  const mockState = {
    subscription: recurringPaymentSubscription(),
    contact,
    allowedActions: [],
    isLoading: false,
    isMotoAvailable: false,
  };
  return (
    <SubscriptionDetailsDispatchContext.Provider value={() => {}}>
      <SubscriptionDetailsContext.Provider value={mockState}>
        <InitiatorProvider initiatorName={ActionModalInitiator.MANAGE_SUBSCRIPTION_MENU}>
          {children}
        </InitiatorProvider>
      </SubscriptionDetailsContext.Provider>
    </SubscriptionDetailsDispatchContext.Provider>
  );
};

const basicRender = () => (
  <ContextProvider>
    <MyComponent isOpen={true} closeModal={() => {}} />
  </ContextProvider>
);

export const { Story: BasicRender } = storykit.getComponent(basicRender);

export default {
  title: 'features/FeatureName/MyComponent',
} as Meta;
```

**Override subscription fields as needed** (e.g. `nextBillingDate` must be in the future: `addDays(new Date(), 7)`). Cover at minimum: default, SAPI (bassManaged: false), no upcoming orders (nextBillingDate: undefined).

## Step 5 — Fix Missing BI Events

If the component imports BI event creators from `@wix/bi-logger-premium-data-bass/v2` that fire in a `useEffect` on mount, they may not exist in the installed package version. Add this polyfill at the **top** of the stories file, after all other imports:

```tsx
import * as biLoggerV2 from '@wix/bi-logger-premium-data-bass/v2';

// Polyfill missing BI event creators not yet in the installed package version
const biModule = biLoggerV2 as any;
const noop = () => ({});
[
  'missingEventFunctionName1',
  'missingEventFunctionName2',
].forEach((key) => { if (!biModule[key]) biModule[key] = noop; });
```

To find which functions are missing: check `node_modules/@wix/bi-logger-premium-data-bass/dist/types/v2/index.d.ts` for the installed exports vs what the component imports.

## Step 6 — Fix Missing i18n Keys

If the story renders translation keys instead of strings (e.g. `subscriptions.my-component.title`):

1. Find all keys used: `grep -rh "subscriptions\." src/components/MyComponent/ | grep -oE "'subscriptions\.[^']+'"`
2. Add missing keys to `src/assets/locale/messages_en.json`
3. **Use single-brace interpolation: `{variable}` not `{{variable}}`** — this project uses i18next with single braces

```json
"subscriptions.my-component.title": "My Title",
"subscriptions.my-component.subtitle": "Hello {contactName}",
```

## Step 7 — Verify

Check storybook compiles without errors:
- No errors in webpack build logs
- No console errors in browser
- Story renders with real strings (not keys)
- All story variants load without crashing

## Common Mistakes

| Problem | Fix |
|---|---|
| `X is not a function` on mount | BI event missing from installed package → add polyfill (Step 5) |
| Shows `subscriptions.foo.bar` as text | Key missing from `messages_en.json` → add with `{var}` syntax (Step 6) |
| `{{variable}}` shown literally | Wrong brace syntax — use single `{variable}` |
| `nextBillingDate` in the past | Override with `addDays(new Date(), 7)` in mock |
| Story crashes on SAPI subscription | Add `bassManaged: false` variant pointing to `SapiSkipCycleModal` |
