# Lost Minions — Admin Tools

This folder contains automation scripts and configuration JSONs that unify issue labels, issue types, secrets, and `.github` templates across all organization repositories.

---

## 🧩 Scripts

| Script | Description |
|--------|-------------|
| `sync-core.sh` | Master controller — runs all sync operations (files, labels, issue types, secrets) across enabled repos in `repos.json`. |
| `sync-files.sh` | Syncs `.github` templates and community files (CODE_OF_CONDUCT, CONTRIBUTING, SECURITY). |
| `sync-labels.sh` | Syncs standardized labels across all repos listed in `repos.json`. |
| `sync-issue-types.sh` | Syncs organization-wide Issue Types via the GitHub GraphQL API. |
| `sync-secrets.sh` | Propagates org secrets (e.g., `GH_TOKEN`) into all private repos. |

### Example usage

```bash
bash .github/admin/sync-core.sh
````

Each script can also be run individually:

```bash
bash .github/admin/sync-files.sh <org/repo>
bash .github/admin/sync-labels.sh <org/repo>
bash .github/admin/sync-issue-types.sh <org/repo>
bash .github/admin/sync-secrets.sh <org/repo>
```

---

## 🗂 JSON Configuration Files

| File               | Purpose                                                                   |
| ------------------ | ------------------------------------------------------------------------- |
| `repos.json`       | List of all organization repositories, including whether sync is enabled. |
| `labels.json`      | Canonical label definitions and colors.                                   |
| `issue-types.json` | Canonical org Issue Types.                                                |

---

## 🔑 Token & Permissions

All scripts require an authenticated `gh` (GitHub CLI) session and a token with the following scopes:

```
admin:org
repo
workflow
read:org
```

Before running any script:

```bash
gh auth login
export GH_TOKEN="your_personal_token"
```

---

## 🧰 Dependencies

The following must be installed and available in `PATH`:

* `gh` — GitHub CLI
* `jq` — JSON processor
* `perl` — used for stripping comments
* `git` — used for repo cloning and committing updates

---

## 🧾 Maintenance Notes

* Commit and push changes to JSON files before running any sync.
* Avoid running sync scripts from forks (they require admin or `write:org` permissions).
* Logs print label, issue-type, and secret operations for transparency.
* The `sync-core.sh` script can be integrated into scheduled GitHub Actions for weekly org maintenance.

---

**Quick Start:**

```bash
# Run all syncs
bash .github/admin/sync-core.sh

# Or run a single repo’s label sync
bash .github/admin/sync-labels.sh ThePortalRealm/ThePortalRealm.com
```
