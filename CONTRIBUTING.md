# Contributing to Lost Minions Projects

Thank you for helping expand **Lost Minions**!

This file is shared across multiple repositories under the `LostMinions` umbrella:
3D prints, websites, tools, libraries, and other experiments.
Each repo may have its own README or docs with project-specific details — always read those first.

---

## 🧭 Where to Start

- **New idea or feature request?**
  Open an issue in the target repo and describe:
  - What you want to add or improve
  - Why it’s useful (for players, makers, or minions)
  - Any mockups, references, or related projects

- **Bug fix or small improvement?**
  Check existing issues first. If nothing matches, open a new issue with:
  - Steps to reproduce
  - Expected vs actual behavior
  - Logs, screenshots, or error messages if available

- **Docs, README, or content updates?**
  You can usually open a PR directly. If you’re changing behavior, APIs, or public workflows, please link or create an issue.

---

## 🧱 Types of Repositories

Lost Minions covers a few main clusters:

- **3D & creative assets** – printable models, STLs, art packs, and related docs
- **Websites & portals** – main site, landing pages, and community hubs
- **Libraries & utilities** – shared C# / Python / scripting helpers
- **Automation & tooling** – GitHub Actions, scripts, and glue code

For each repo:

- Check the **README** for setup, build, or print instructions.
- Look for a **`/docs`** folder or wiki for extra details.
- Follow any repo-specific contribution notes there.

---

## 📝 How to Contribute

1. **Fork or branch from `main`**
   - External contributors: fork the repo on GitHub.
   - Collaborators: create a feature branch from `main`.

2. **Create or link an issue**
   - Reference an existing issue if one already tracks your change.
   - Otherwise, open a new issue and outline:
     - What you’re changing
     - Why it’s needed
     - Any potential impact (other tools, workflows, or assets)

3. **Make focused, readable commits**
   - Group related changes together.
   - Use clear messages that explain *why* as well as *what*.
   - If the repo uses commit tags (e.g. `[skip ci]`, `[publish]`, `[publish-zip]`),
     follow any conventions noted in the README.

4. **Add tests or checks where appropriate**
   - For code: add or update unit/integration tests if the project has them.
   - For workflows or scripts: consider simple validation steps or dry-run modes.
   - For 3D assets: note scale, orientation, and any special print considerations.

5. **Open a Pull Request**
   - Clearly describe the change and link the related issue.
   - Mention if your change affects:
     - CI / GitHub Actions
     - Shared libraries or templates
     - Multiple repos in the Lost Minions ecosystem

6. **Respond to review**
   - Keep feedback constructive and focused on the work.
   - It’s fine to push follow-up commits — just keep them tidy and readable.

---

## ⚖️ Code of Conduct

All contributions must follow the [Lost Minions Code of Conduct](./CODE_OF_CONDUCT.md).

We expect respect, patience, and collaboration — whether you’re editing a small script or adding a whole new set of 3D models.

---

## 🔒 Security & Vulnerabilities

If you discover a security issue in a Lost Minions project:

- **Do not** open a public issue.
- Report privately via [GitHub Security Advisories](../../security/advisories) or email:
  **security@lostminions.org**

Please include:

- A clear description of the problem
- Steps or scripts to reproduce
- Any potential impact you’re aware of

We’ll coordinate fixes here and in any related repositories.

---

## 💡 Need Help?

If you’re unsure about anything:

- Which repo is the right place for your change
- How a script, workflow, or site is supposed to behave
- What impact your update might have on other projects

Open a **“Question”** issue in the relevant repo with as much context as you can.

Lost Minions is meant to be a playground for builders, not a maze — it’s always okay to ask before you dive in.
