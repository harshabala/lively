---
name: Lively
description: Native macOS menu-bar utility for per-Space video wallpapers — Mist Reef palette, SF Pro, calm glass
colors:
  background-light: "#F2FFFE"
  background-dark: "#031116"
  card-light: "#FFFFFF"
  card-dark: "#0B1D24"
  primary-light: "#007078"
  primary-dark: "#55CAD0"
  primary-foreground-light: "#FFFFFF"
  primary-foreground-dark: "#030303"
  primary-soft-light: "#43B6BB"
  primary-soft-dark: "#9FE8EA"
  foreground-light: "#0B1B20"
  foreground-dark: "#F0FBFC"
  muted-foreground-light: "#516970"
  muted-foreground-dark: "#8CAAB1"
  border-light: "#C8DADA"
  border-dark: "#2B4952"
  accent-light: "#E3F2F1"
  accent-dark: "#12313A"
  destructive: "#FF0000"
typography:
  title:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "18px"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "normal"
  section:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: "normal"
  body:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "13px"
    fontWeight: 400
    lineHeight: 1.4
    letterSpacing: "normal"
  caption:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "12px"
    fontWeight: 500
    lineHeight: 1.3
    letterSpacing: "normal"
  footnote:
    fontFamily: "SF Pro, system-ui, sans-serif"
    fontSize: "11px"
    fontWeight: 400
    lineHeight: 1.3
    letterSpacing: "normal"
  mono:
    fontFamily: "SF Mono, ui-monospace, monospace"
    fontSize: "12px"
    fontWeight: 500
    lineHeight: 1.3
    letterSpacing: "normal"
rounded:
  sm: "6px"
  md: "10px"
  lg: "14px"
  full: "9999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  xl: "24px"
components:
  card-surface:
    backgroundColor: "{colors.card-light}"
    textColor: "{colors.foreground-light}"
    rounded: "{rounded.lg}"
    padding: "16px"
  pill-tab-selected:
    backgroundColor: "{colors.card-light}"
    textColor: "{colors.foreground-light}"
    rounded: "{rounded.sm}"
    padding: "8px 14px"
  pill-tab-unselected:
    backgroundColor: "transparent"
    textColor: "{colors.muted-foreground-light}"
    rounded: "{rounded.sm}"
    padding: "8px 14px"
  drop-zone-idle:
    backgroundColor: "{colors.accent-light}"
    textColor: "{colors.muted-foreground-light}"
    rounded: "{rounded.md}"
    padding: "12px"
  drop-zone-targeted:
    backgroundColor: "{colors.primary-light}"
    textColor: "{colors.foreground-light}"
    rounded: "{rounded.md}"
    padding: "12px"
---

## Overview

Lively is a **product-register** native macOS settings popover (480×560pt) for assigning video wallpapers per display and Space. Visual identity is **Mist Reef**: cool cyan-teal on quiet near-white (light) or deep blue-green (dark). Implementation lives in `LivelyBrand.swift`, `PillTabBar.swift`, and `brand.md`. Canonical OKLCH values are in `brand.md`; hex above is for tooling compatibility.

## Colors

**Strategy:** restrained — tinted neutrals with teal accent ≤10% of surface area.

| Role | Light OKLCH | Dark OKLCH | Use |
|------|-------------|------------|-----|
| background | oklch(0.985 0.012 195) | oklch(0.120 0.018 210) | Popover shell, subtle gradient |
| card | oklch(1 0 0) | oklch(0.170 0.024 205) | Display cards, settings sections |
| primary | oklch(0.470 0.130 190) | oklch(0.760 0.140 190) | Actions, selection, sliders |
| muted-foreground | oklch(0.420 0.018 210) | oklch(0.670 0.015 205) | Helper text, metadata |
| border | oklch(0.885 0.017 195) | oklch(0.270 0.034 205) | Card strokes, dividers |

**Contrast:** Core pairs pass WCAG AA (see `brand.md` contrast table). Do not lighten muted text below verified ratios. Labels on primary fills use `primary-foreground` (`LivelyBrand.onPrimary`). Dark primary `#55CAD0` is too light for a white label; light primary `#007078` may keep white.

**Gradients:** `backgroundGradient` and `accentGradient` only — barely perceptible shell gradient; accent gradient for small rewards only, never under body text.

## Typography

Single family: **SF Pro** (`.system`) for all UI. **SF Mono** only for file names, versions, and log lines.

| Token | Size / weight | Use |
|-------|---------------|-----|
| title | 18pt semibold | Display names, app title |
| section | 13pt semibold | Settings section headers |
| body | 13pt regular | Controls, descriptions |
| caption | 12pt medium | Drop zones, buttons |
| footnote | 11pt regular | Helper lines |
| mono | 12pt medium monospaced | Paths, version strings |

No decorative font pairing. Hierarchy via size, weight, and opacity — not typeface switching.

## Elevation

- **Window chrome:** `ultraThinMaterial` over `backgroundGradient` at ~72% opacity — one glass layer at the shell only
- **Cards:** opaque `card` fill at 88% + `border` stroke — no nested `liquidGlass` on cards or drop zones
- **Shadows:** avoid ghost-card pattern (border + wide shadow). Prefer border-only or a single subtle shadow, never both
- **Radius:** sm 6pt (pills, chips), md 10pt (drop zones), lg 14pt (cards). Concentric nesting: inner radius ≈ outer − padding

## Components

| Component | Pattern |
|-----------|---------|
| Primary tabs | `PillTabBar` — Displays / Settings |
| Mode tabs | `PillTabBar` — Wallpaper / Light & Dark |
| Display card | Header + mode tabs + drop zone(s) + inline scale/mute/volume |
| Drop zone | Dashed border when empty; tinted fill on drag; thumbnail + filename when assigned |
| Settings row | Section label + content in unified card surface |
| Destructive actions | `confirmationDialog` or `.alert` — never popover for remove |
| Error toast | Destructive fill, top of card, auto-dismiss 5s + VoiceOver announcement |
| Motion | `LivelyBrand.Motion.fast` (0.2s) / `normal` (0.3s), bounce 0; nil when `reduceMotion` |

## Do's and Don'ts

**Do**

- Map all colors through `LivelyBrand` tokens
- Keep hit targets ≥32pt on tabs, pause, mute, trash
- Use utility copy: "Fill", "Fit", "Muted", "Drop a video, or click to browse"
- Gate animations on `@Environment(\.accessibilityReduceMotion)`
- Show assigned video filename in card header, not macOS desktop wallpaper path

**Don't**

- Stack glass (`liquidGlass`) on cards and drop zones
- Use `Color.primary` / `.secondary` / `.accentColor` instead of brand tokens
- Fake update checks or overclaim log health
- Use uppercase section eyebrows or marketing exclamation copy
- Apply bounce springs on drag targets or list stagger >50ms/item
- Nest cards inside cards in Settings (About is inline, not double-wrapped)