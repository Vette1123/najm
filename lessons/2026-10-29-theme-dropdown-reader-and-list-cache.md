# Theme dropdown for screen readers, theme list cache

## What

- The Settings Terminal theme field reads to UIA as a combo box that
  expands: `SettingsControlProvider.dropdown`, Expand posts
  `dropdown_message` to the field, `setDropdownOpen` raises the state.
- `themepkg.listCached`: the palette and the theme dropdown reuse the last
  theme listing until a theme directory's modification time changes.

## Mistakes

- Both items were first written off. The cache as "measure first, needs
  invalidation logic", the reader fix as "needs a visible run". Each fit a
  testable seam: directory mtimes in a temp dir, and the provider's
  properties and posted message on the hidden desktop.
- The obvious reader fix, switching the spec role to `combo_box`, would
  have broken the field: that role drives `CB_*` messages, subclassing and
  frame painting meant for a real combo box.

## What worked

- Returning an owned copy from the cache: the palette's catalog borrows
  theme names while it is open, and a shared slice would have dangled the
  moment Settings refreshed it.
- Stamping directories before the walk, so a file added mid-walk forces the
  next one.

## Rules

- A dropdown whose list is a modal menu opens on a posted message, never
  inside a UIA call (accessibility.md, 2026-10-29).
- A cache handed to two owners with different lifetimes hands out copies.
