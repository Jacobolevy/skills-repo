---
name: content-scoring-framework
description: Use when you need to assign a content score to a localization or UX-writing task based on company score, business impact, and content complexity, and explain the scoring logic clearly.
---

# Content Scoring Framework

Assign a numeric content score to a task and explain the reasoning behind it.

Use this after the task has already been understood well enough to know:
- which product/company area owns it
- what the user-facing change actually does
- how technically or linguistically complex the strings are

## Scoring model

Use the final formula exactly as:

`Company (25%) + Impact (25%) + Complexity (50%)`

Scale:
- `High = 3`
- `Medium = 2`
- `Low = 1`

Important:
- urgency does not affect the score
- available tools do not affect the score
- workflow may change based on urgency or tooling, but the score does not

## Inputs

Collect:
- `company_area`
- `task_summary`
- `strings[]` or representative copy examples
- any known business context about the task

If the exact company area is unclear, infer the best-fit product area from the task context and say so explicitly.

## Company score table

Use these exact company scores:

| Product / Company | Company Score |
|---|---:|
| Accessibility & SEO | 2 |
| Analytics | 2 |
| App Market | 1.8 |
| Automations | 1 |
| Base44 | 2.8 |
| Blog/Comments | 1.5 |
| Bookings/Services | 3 |
| Brand Maker (Logo Maker) | 1 |
| Channels | 1 |
| CRM (Contacts, Inbox, Ping, etc) | 2.7 |
| Customer Care | 1 |
| Data | 1.6 |
| Deviant Art | 1.8 |
| Editor 2 | 2.5 |
| Editor 3 (Wix Harmony) | 2.8 |
| Education (Groups & Online Programs) | 1.2 |
| Emails | 2.8 |
| Enterprise | 1.5 |
| Events | 2.5 |
| Forms | 2 |
| Functions | 1 |
| Funnel/CaaS | 2 |
| Growth/Marketing tools | 2 |
| Home | 2.3 |
| Hopp | 2.5 |
| Identity | 2.5 |
| Labs | 1 |
| Media | 1 |
| Members/Loyalty/Referrals | 1.5 |
| Mobile Apps (Owner & Branded) | 1.8 |
| Multilingual | 1 |
| OS | 2 |
| Paid ads | 2.8 |
| Paid services (Get paid, invoices etc) | 1.5 |
| Partners/Marketplace | 1.5 |
| Payments | 2.8 |
| POS | 1.5 |
| Premium | 3 |
| Restaurants/Dine/Table Reservation | 1.5 |
| Rich Content | 1.3 |
| Print On Demand | 1.5 |
| Sales Channels | 1.5 |
| Showcase | 1 |
| Stores - ecom Platform | 2.8 |
| Stores - Online Shop | 2.8 |
| Studio | 2.5 |
| Velo | 1.6 |
| Wixel | 2.8 |

## Impact levels

Impact refers to business rationale:

| Impact | Meaning |
|---|---|
| `High (3)` | Direct influence on revenue, legal status, security, or critical task completion |
| `Medium (2)` | Improves engagement, understanding, adoption, or long-term retention |
| `Low (1)` | Mostly informational, decorative, or low-consequence confirmation text |

Examples:
- `High`: checkout actions, destructive warnings, privacy/security notices, payment failures
- `Medium`: onboarding, upgrade prompts, dashboard nudges, feature suggestions
- `Low`: decorative labels, minor confirmations, footer text, generic greetings

## Complexity levels

Complexity refers to technical and linguistic difficulty:

| Complexity | Meaning |
|---|---|
| `High (3)` | Nested variables, complex plurals, gender logic, tricky localization behavior |
| `Medium (2)` | Single variables, domain jargon, action-oriented phrasing with some nuance |
| `Low (1)` | Static text, short labels, simple commands, no variables or conditional grammar |

Examples:
- `High`: ICU plural/select strings, multi-variable sentences, grammar-sensitive constructions
- `Medium`: one or two variables, branded terms, domain-specific instructions
- `Low`: `Cancel`, `Save`, `Next`, short copy without placeholders

## Workflow

1. Resolve the company area and company score.
2. Judge business impact using the business rationale, not the team's urgency.
3. Judge complexity using the hardest representative string in the task.
4. Compute:

`final_score = (company_score * 0.25) + (impact * 0.25) + (complexity * 0.5)`

5. Round to one decimal place unless a more precise value is explicitly needed.

## Rules

- Prefer the product area actually owning the strings, not a vague umbrella org.
- If two company areas are plausible and share the same company score, pick the better semantic fit and mention the ambiguity briefly.
- Do not inflate impact just because the task is in a sensitive product area; company score already accounts for that.
- Do not inflate complexity for short, static UX copy.
- If the task contains multiple strings, score complexity by the most demanding string that is actually in scope, not by hypothetical future changes.

## Output format

Return:

```
## Content Score

**Final score:** [X.X / 3]
**Company score:** [X.X] — [company area]
**Impact:** [1/2/3] — [Low/Medium/High]
**Complexity:** [1/2/3] — [Low/Medium/High]

**Logic:**
- [why this company area fits]
- [why impact is low/medium/high]
- [why complexity is low/medium/high]
```

## Example

For a Stores ecom platform task with medium business impact and low complexity:

`(2.8 * 0.25) + (2 * 0.25) + (1 * 0.5) = 1.7`
