# 🧩 Lost Minions — Brand Assets

Central repository of official artwork, avatars, and branding for **Lost Minions**, the creature-workshop behind all our chaotic experiments and creative projects.

---

## 🎯 Purpose

This directory is the **single source of truth** for every visual element used across the **Lost Minions** organization — GitHub, social profiles, storefronts, and partner sites.

All assets here are safe to use for:

* GitHub org and team avatars
* Social banners (Reddit, Discord, etc.)
* Etsy / merch imagery and product cards
* Website headers and promotional art
* Cross-project or partner collaborations

---

## 🗂 Structure

```
brand-assets/
├── avatars/        → Org and team icons
├── banners/        → Header art (desktop + mobile)
├── logo/           → Official wordmarks and symbols (SVG + PNG)
├── palette.json    → Color palette and theme definitions
└── README.md       → This file
```

---

## 🎨 Brand Palette

All official colors are defined in [`palette.json`](./palette.json).
Each entry includes HEX, RGB, and usage notes for consistent application across digital and print.

Example:

```json
{
  "primary": "#8BFF4A",
  "secondary": "#A24AFF",
  "accent": "#FFE44A",
  "dark": "#111216",
  "light": "#F4F4F6"
}
```

| Role         | Color                   | Example Use                       |
| ------------ | ----------------------- | --------------------------------- |
| 🧫 Primary   | Slime Green `#8BFF4A`   | Core glow, buttons, slime effects |
| ☠️ Secondary | Toxic Purple `#A24AFF`  | Depth shadows, light edges        |
| 💡 Accent    | Minion Yellow `#FFE44A` | Highlights, eyes, teeth           |
| 🌑 Dark      | Lab Black `#111216`     | Backgrounds, outlines             |
| 🦴 Light     | Bone White `#F4F4F6`    | Text and contrast areas           |

---

## 🖼 Usage Guidelines

* **Do not edit** existing image files directly — propose changes via PR.
* **Preferred formats:**

 * `.svg` for scalable vectors (web, headers, UI)
 * `.png` for raster or social use
* **Aspect ratios:**

 * Avatars 1 : 1
 * Banners 3 : 1 (1072 × 128 px minimum for Reddit/desktop)

---

## 🧩 Integration Example

Use a raw GitHub link to embed the official logo anywhere:

```markdown
![Lost Minions Logo](https://raw.githubusercontent.com/LostMinions/.github/main/brand-assets/logo/lostminions.png)
```

---

## ⚙️ Versioning

Increment version and date inside `palette.json` whenever brand colors or logo marks are updated.
Commit message convention:

```
chore(brand): update lostminions palette v1.1
```

---

## 🧙 Credits

All artwork © Lost Minions.
Design and direction by the **Monster Makers Guild** and the **Developer Team**.

---

*Version 1.0 — maintained in `.github/brand-assets/`*
