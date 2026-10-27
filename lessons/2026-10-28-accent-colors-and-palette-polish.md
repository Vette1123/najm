# 2026-10-28: accent colours and palette polish

## What

The chrome accent is configurable: `window-accent` (`default`, `system` for the Windows accent,
or one of twenty named colours from the Windows swatches) and `window-accent-color` (any hex or
X11 colour, which wins). Settings > Appearance > Accent color offers the same choices with live
preview. One function, `withAccent` in `src/apprt/win32.zig`, derives every accent role from the
chosen colour: menu and palette edges and highlight, check marks, focus rings, the focused split,
active and primary buttons, overlay labels, and Settings. Each role keeps a contrast floor.

The palette also got polish from an audit. The selected row has a WinUI-style accent indicator,
so selection is no longer shown by a tint alone. Disabled commands dim their title and keycaps.
In High Contrast, a selected destructive row uses the highlight text colour. Keycaps grow with
Windows "Text size" instead of staying 22 px.

## Mistakes

- **Picked white or `#1B1B1B` for text on a filled accent.** That pair only guarantees about
  4.15:1. Mid-tone fills sit where the two contrast curves cross. Pure black guarantees 4.58:1.
  The test over every preset plus the worst cases caught it before it shipped.
- **Nearly revived `accent-follow-system`.** #596 had deliberately taken the accent out of the
  tab strip, and reviving the key would have quietly brought the tab accent back. A new key with
  a clear scope (menus, palette, focus, buttons; never the tab strip) avoids that.
- **First tried to make one union-typed key take both the presets and any hex colour.** The
  Settings dropdown machinery (`field_model.Combo`) only takes enum keys and checks that it
  covers every variant. Splitting it into an enum key plus an optional colour key fits both the
  dropdown and the config file.
- The audit listed eight findings. I did not apply four of them: 12 px keycap text matches
  DESIGN.md's secondary size; the faint pill on disabled menu rows is the keyboard position;
  native-style fill-only selection stays in menus; and the pill and edge pixel geometry needs a
  visible check before it changes.

## What worked

- Reusing the removed `resolveSystemAccentColor` and the "move toward white or black only as far
  as it takes" rule from git history (`c0b0db725^`), instead of inventing new ones.
- The existing `ImmersiveColorSet` refresh, which re-runs `resolveTheme`, so `system` follows a
  Windows accent change with no new message handling.

## Rules

- Accent-coloured paint reads a role from `withAccent`, never a literal or a preset.
- Text on a computed fill picks between pure white and pure black.
- A Settings dropdown needs an enum key. Put free-form values in a second key that overrides it.
