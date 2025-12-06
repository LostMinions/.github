# 🧩 Lost Minions / TheKrush — Admin Tools

This folder contains automation scripts and JSON configs that keep repos across

- **TheKrush**
- **LostMinions**
- **LostMinionsGames**
- **ThePortalRealm**

in sync — covering workflows, actions, templates, labels, community files,
tools, editor configs, and more.

Changes here are **infrastructure-level** and can fan out to many repos at once.

---

## ⚙️ Script Overview

All scripts assume you run them from the repo root, e.g.:

```bash
bash .github/admin/sync-core.sh
````

### Orchestration

| Script           | Description                                                                                                                                                                                                 |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `sync-core.sh`   | Master controller — iterates over all enabled repos in `repos.json` and runs the appropriate sync modules (community, workflows, actions, templates, tools, editor, labels, issue types, secrets, scripts). |
| `sync-admin.sh`  | Convenience wrapper for running a focused admin sync for org-level `.github` repos. See the script header for the exact set it calls.                                                                       |
| `sync-common.sh` | Shared helper functions (JSON cleaning, discovery helpers, deprecation handling, etc.) used by the other scripts.                                                                                           |

### GitHub Assets & CI

| Script              | Description                                                                                                                                       |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| `sync-workflows.sh` | Syncs shared GitHub Actions workflow files (e.g. compile/publish/controller/update-submodules/publish-zip) from this repo into all enabled repos. |
| `sync-actions.sh`   | Syncs composite actions under `.github/actions/` (e.g. `publish-dotnet-release`, `publish-github-release`, `check-org-usage`, `cleanup-runner`).  |
| `sync-templates.sh` | Syncs `.github` templates (issue templates, PR templates, FUNDING, etc.) based on `manifest.json` + `repos.json`.                                 |
| `sync-scripts.sh`   | Syncs helper scripts under `.github/scripts/` into target repos (e.g. runner utilities, packaging helpers).                                       |

### Repo Metadata & Community Files

| Script                | Description                                                                                                                                                                                                                                                              |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `sync-community.sh`   | Syncs root-level community + license files: `CODE_OF_CONDUCT`, `CONTRIBUTING`, `SECURITY`, `LICENSE` / `NOTICE_PRIVATE.md`. For non-`.github` repos it maps `CONTRIBUTING.project.md` → `CONTRIBUTING.md` so admin and child repos can have different CONTRIBUTING text. |
| `sync-labels.sh`      | Syncs standardized GitHub labels across all enabled repos.                                                                                                                                                                                                               |
| `sync-issue-types.sh` | Syncs organization-wide Issue Types via the GitHub GraphQL API.                                                                                                                                                                                                          |
| `sync-secrets.sh`     | Propagates org-level secrets (e.g., `GH_TOKEN`) into all repos configured in `repos.json` (respecting visibility and flags).                                                                                                                                             |

### Code, Tools & Editor Config

| Script           | Description                                                                                                                                                                                          |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `sync-tools.sh`  | Syncs the top-level `tools/` folder into repos, using `manifest.json` + `repos.json` for `tools`, `extra_tools`, per-repo excludes, and deprecated entries. Handles `.github` admin repos specially. |
| `sync-editor.sh` | Syncs editor-related files (e.g. `.editorconfig`, `CodeMaid.config`, and other configured files) into repos that opt in via `repos.json`.                                                            |

---

## 🗂 JSON Configuration Files

| File                      | Purpose                                                                                                                                                                                           |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `repos.json`              | Main registry of all managed repositories. Includes owner, name, description, `enabled` flag, license type, and per-repo overrides (community files, tools, editor files, excludes, etc.).        |
| `labels.json`             | Canonical label definitions (name, color, description, emoji) shared across repos.                                                                                                                |
| `issue-types.json`        | Canonical organization-wide Issue Type templates.                                                                                                                                                 |
| `manifest.json`           | Master defaults/overrides for sync behavior. Defines default lists, deprecated entries, and global excludes for community files, workflows, templates, tools, actions, scripts, and editor files. |
| `CONTRIBUTING.project.md` | Shared **project-level** CONTRIBUTING template; `sync-community.sh` maps this to `CONTRIBUTING.md` in non-`.github` repos so admin repos can keep their own infra CONTRIBUTING.                   |

> 💡 Changes to these files should be committed and pushed **before** running any sync, since scripts read directly from the current repo state.

---

## 🚀 Example Usage

### Run the master sync (all enabled repos)

```bash
bash .github/admin/sync-core.sh
```

### Run a specific sync module for a single repo

```bash
# Sync only community + license files
bash .github/admin/sync-community.sh TheKrush/Stock-Analysis

# Sync only workflows
bash .github/admin/sync-workflows.sh LostMinions/.github

# Sync only tools
bash .github/admin/sync-tools.sh TheKrush/Sanctuary.DiscordBot
```

### Admin repo focused sync

```bash
# Run the admin-focused sync for all org-level .github repos
bash .github/admin/sync-admin.sh
```

(See the script header for exactly which modules it runs.)

---

## 🔐 Tokens & Permissions

Most scripts expect:

* A valid **GitHub CLI** session (`gh auth login`)
* An environment variable `GH_TOKEN` with at least:

```text
admin:org
repo
workflow
read:org
```

Set up once per shell session:

```bash
gh auth login
export GH_TOKEN="your_personal_token"
```

For scheduled automation, store `GH_TOKEN` as a GitHub Actions secret with the same scopes.

---

## 🧰 Dependencies

Make sure these tools are installed and on your `PATH`:

| Tool   | Purpose                           |
| ------ | --------------------------------- |
| `gh`   | GitHub CLI (REST + GraphQL calls) |
| `jq`   | JSON parsing and filtering        |
| `perl` | Comment stripping from JSON files |
| `git`  | Repo validation and staging       |
| `bash` | Shell for all sync scripts        |

Scripts automatically handle `$HOME` / `$USERPROFILE` differences across platforms when writing credentials.

---

## 🧾 Maintenance Notes

* Commit any local JSON or script changes **before** running sync.
* Only run from an account with **admin or write-org** permissions on the affected repos.
* Each script logs what it changed, skipped, or failed.
* Deprecated entries in `manifest.json` are actively removed from target repos.
* Global vs per-repo excludes are respected so you can opt repos in or out of specific assets.

---

### 🧩 Quick Start

```bash
# Run everything for all enabled repos
bash .github/admin/sync-core.sh

# Refresh labels for a single repo
bash .github/admin/sync-labels.sh ThePortalRealm/ThePortalRealmBot

# Sync tools into a single repo
bash .github/admin/sync-tools.sh TheKrush/Stock-Analysis
```
