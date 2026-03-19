# Fix Localization Issues

Scan code for localization issues and fix them.

**Only fix violations of the rules in `rules.md`.** Do not invent additional rules or flag things not covered.

## Process

1. **Scan the codebase first** — Follow the "Before Starting" step in `rules.md` to understand existing conventions.
2. Scan the current file or provided code for issues
3. Identify only issues that violate the rules in `rules.md`
4. Propose fixes with before/after code
5. Apply fixes with user approval

## Common Fix Patterns

### Hardcoded strings → Translation keys
```javascript
// ❌ Before
<button>Delete</button>

// ✅ After
<button>{t('products.list.deleteButton')}</button>
```

### Hardcoded punctuation → Move to key value
```javascript
// ❌ Before
<label>{t('email')}</label>:

// ✅ After
<label>{t('form.emailLabel')}</label>
// Key value: "Email:"
```

### Split sentences → Single key
```javascript
// ❌ Before
<p>{t('this_feature')} {t('is_part_of')} {t('premium')}</p>

// ✅ After
<p>{t('feature.premiumMessage')}</p>
// Key: "This feature is part of your Premium Plan"
```

### Legacy plural suffix → ICU format
```javascript
// ❌ Before
key: "item"
key_plural: "items"

// ✅ After
key: "{count, plural, one {# item} other {# items}}"
```

### Hardcoded support URLs → Separate keys
```javascript
// ❌ Before
<a href="https://support.wix.com/en/article/123">Learn more</a>

// ✅ After
<a href={t('help.feature.linkURL')}>{t('help.feature.linkText')}</a>
```

## Do NOT Fix These

- Spaces or formatting inside key values
- Key value capitalization or length
- URLs with dynamic locale variables (`${locale}`, etc.)
- Non-support URLs
- Anything not covered by `rules.md`

## Output Format

```
🔧 Fixing localization issues

Issue 1: Hardcoded punctuation in code (line 24)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Before: <label>{t('email')}</label>:
After:  <label>{t('auth.login.emailLabel')}</label>
New key value: "Email:"

Issue 2: Legacy plural suffix (line 45)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Before: key_plural pattern
After:  ICU format
New key: "{count, plural, one {# user} other {# users}}"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Summary: 2 issues fixed
```
