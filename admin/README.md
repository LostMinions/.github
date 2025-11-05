# 🧩 Lost Minions — Admin Tools

This folder contains automation scripts and JSON configs that keep every repository in the **LostMinions** and **ThePortalRealm** organizations consistent — covering issue templates, labels, issue types, secrets, and `.github` policy files.

---

## ⚙️ Overview

| Script | Description |
|--------|-------------|
| `sync-core.sh` | Master controller — runs all sync operations (files, labels, issue types, secrets) across enabled repos in `repos.json`. |
| `sync-files.sh` | Syncs `.github` templates and community files (CODE_OF_CONDUCT, CONTRIBUTING, SECURITY). |
| `sync-issue-types.sh` | Syncs organization-wide Issue Types via the GitHub GraphQL API. |
| `sync-labels.sh` | Syncs standardized labels across all repos listed in `repos.json`. |
| `sync-secrets.sh` | Propagates org secrets (e.g., `GH_TOKEN`) into all private repos. |                                 |
| `sync-workflows.sh`   | Syncs shared GitHub Actions workflow files (e.g., `publish.yml`, `test-compile.yml`, `auto-sync.yml`) across all enabled repos.     |

All scripts log actions to the console for transparency and skip any repo marked `"enabled": false` in `repos.json`.

---

## 🚀 Example Usage

Run the master sync (recommended):

```bash
bash .github/admin/sync-core.sh
```

Or run a specific module:

```bash
bash .github/admin/sync-files.sh <org/repo>
bash .github/admin/sync-issue-types.sh <org/repo>
bash .github/admin/sync-labels.sh <org/repo>
bash .github/admin/sync-secrets.sh <org/repo>
bash .github/admin/sync-workflows.sh <org/repo>
```

---

## 🗂 JSON Configuration Files

| File               | Purpose                                                                            |
| ------------------ | ---------------------------------------------------------------------------------- |
| `repos.json`       | Lists all repositories with fields for org, name, description, and `enabled` flag. |
| `labels.json`      | Canonical label definitions (name, color, description, emoji).                     |
| `issue-types.json` | Canonical organization-wide issue type templates.                                  |

> 💡 Changes to these files should be committed and pushed **before** running any sync, since scripts read directly from the current repo state.

---

## 🔐 Tokens & Permissions

All scripts require:

* A valid **GitHub CLI** session (`gh auth login`)
* An environment variable `GH_TOKEN` with at least these scopes:

```
admin:org
repo
workflow
read:org
```

Set up once per session:

```bash
gh auth login
export GH_TOKEN="your_personal_token"
```

> 🧠 For scheduled automation, store `GH_TOKEN` as a GitHub Actions secret with the same scopes.

---

## 🧰 Dependencies

Make sure the following tools are installed and available in your `PATH`:

| Tool   | Purpose                           |
| ------ | --------------------------------- |
| `gh`   | GitHub CLI (API + GraphQL calls)  |
| `jq`   | JSON parsing and filtering        |
| `perl` | Comment stripping from JSON files |
| `git`  | Repo validation and commit sync   |

> Scripts automatically detect OS (Windows, Linux, macOS) and write credentials to the correct path (`$USERPROFILE` or `$HOME`).

---

## 🧾 Maintenance Notes

* Commit any local JSON changes before syncing.
* Only run from a repo with **admin or write-org** permissions.
* Each script prints colored status lines showing what changed, skipped, or failed.
* `sync-core.sh` can be scheduled via GitHub Actions (e.g., weekly) for automated org maintenance.
* Secrets are only written if missing or mismatched; redundant updates are skipped automatically.

---

### 🧩 Quick Start

```bash
# Run everything
bash .github/admin/sync-core.sh

# Or just refresh issue labels for one repo
bash .github/admin/sync-labels.sh ThePortalRealm/ThePortalRealmBot
```
