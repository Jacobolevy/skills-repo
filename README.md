# Localization Skills

Claude Code / Codex skills for the localization workflow at Wix.

## Install

```bash
git clone git@github.com:Jacobolevy/skills-repo.git
cd skills-repo
./install.sh
```

The installer will ask whether to install for **Claude**, **Codex**, or **both**.

To update after a `git pull`:
```bash
./install.sh --target both
```

---

## Skills

### Orchestrator

| Skill | Description |
|---|---|
| `localization-workflow` | End-to-end orchestrator: Jira / Slack input → Smartling tags → Babel screenshots → job → Monday → authorize |

### Sub-skills (invoked by localization-workflow)

| Skill | Description |
|---|---|
| `babel-figma-screenshots` | Maps Babel key names to Figma design sections and uploads screenshots for context |
| `content-scoring-framework` | Assigns a content score (company, impact, complexity) to a localization task |
| `jira-reader` | Reads a Jira ticket and extracts keys, Figma URLs, feature toggles, and sprint metadata |
| `monday-localizer` | Creates Monday items and subitems for localization tasks |
| `smartling-job-manager` | Creates and authorizes Smartling jobs |
| `smartling-post-auth` | Runs post-authorization steps (Green/Yellow/Red LLM workflow) |
| `smartling-tag-manager` | Adds Smartling tags to strings by key list, spreadsheet, or export |

### Standalone

| Skill | Description |
|---|---|
| `localization-keys-creator` | Creates, reviews, and fixes localization keys in Babel following Wix best practices |
| `localization-slack-on-call` | Handles Slack on-call localization requests end-to-end |
