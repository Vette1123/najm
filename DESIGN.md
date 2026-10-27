# noctty design system

This is the target visual and interaction contract for noctty's native
Windows shell. Existing implementation tokens remain authoritative until a
surface is migrated; new work should converge on this contract without
regressing platform behavior or accessibility.

## Direction

Compact, adaptive, terminal-first. The design target is a developer who
moves between a bright office, a dim home workspace, and mixed-DPI monitors
while a long-running PowerShell or WSL session stays visible. That means
light, dark, system, and High Contrast modes are equal product states, not
variants of one preferred theme.

Color stays restrained. Neutral chrome carries the interface; Windows accent
and semantic colors communicate selection, focus, warning, and failure. No
decorative glass or persistent color fields.

## Foundations

### Typography

- UI family: Segoe UI Variable where available, then Segoe UI.
- Terminal font: user-configured and independent from shell chrome.
- UI scale: 12 px secondary labels, 13 px controls/body, 14 px emphasized
  body, 16 px section titles, 20 px exceptional dialog titles.
- Weights: 400 regular, 600 semibold. Avoid display weights and all-caps
  labels.
- Prose measure: 65–75 characters. Dense lists may use available width.

### Spacing and geometry

- Base unit: 4 px; allowed micro-step: 2 px.
- Control heights: 28 px compact, 32 px standard, 36 px touch-friendlier.
- Chrome padding: 8 px standard; 12–16 px for dialogs and settings panes.
- Corners: 4 px controls, 6 px overlays, 8 px dialogs. Use native window
  corners where Windows owns the frame.
- Borders: 1 px separators and control frames. Active pane: a thin semantic
  focus indicator, not a persistent header.
- Minimum pointer target: 32×32 px in dense chrome; 44×44 px where touch is
  a primary interaction.

### Color roles

Current RGB values in `src/apprt/win32_theme.zig` seed the system. Preserve
role names rather than copying literal colors into components.

| Role              | Light seed | Dark seed | Use                                     |
| ----------------- | ---------- | --------- | --------------------------------------- |
| Chrome background | `#F3F3F3`  | `#181818` | Window shell and tab strip              |
| Elevated surface  | `#F9F9F9`  | `#1C1C1E` | Palette, menus, settings panes          |
| Primary text      | `#1B1B1B`  | `#DCDCE0` | Labels and primary content              |
| Secondary text    | `#606060`  | `#9E9EA4` | Hints and metadata                      |
| Accent            | `#0078D4`  | `#749CE0` | Focus, active selection, primary action |
| Error             | `#C42B1C`  | `#FF8484` | Errors and destructive outcomes         |

The accent is the one role a user may change (`window-accent`,
`window-accent-color`, Settings > Appearance > Accent color). Every accent
role derives from that one color in `withAccent` (`src/apprt/win32.zig`):
the accent itself is held to 3:1 against the chrome and elevated surfaces,
accent-tinted labels to 4.5:1, and text on a filled accent is white or black.
Components read the role, never the preset. Semantic overlay colors (search,
rename, confirm) do not follow it.

### Accessibility targets

These are the canonical accessibility targets for application chrome:

- WCAG 2.2 AA-equivalent contrast: at least 4.5:1 for body text, at least
  3:1 for large text and essential non-text/focus indicators.
- Never use color as the only state cue.
- Complete keyboard operation with visible focus; pointer actions require a
  keyboard or palette equivalent.
- Windows High Contrast uses system colors and suppresses nonessential
  custom styling.
- Reduced motion, UI Automation exposure, and 100–300% DPI support.
- Validate with Narrator and NVDA.

## Components

Every interactive component defines default, hover, focused, pressed,
selected, disabled, loading, warning, and error behavior where applicable.
Focus is never represented by hover styling.

### Tabs and panes

- One adaptive tab row with readable minimum widths and searchable overflow.
- Preserve the active and recently used tabs longest during compression.
- Active tab treatment is restrained but visible in active and inactive
  windows. The active tab takes its terminal's background and runs on into
  the terminal, with no accent colour; its `* ` label marker is the essential
  cue, so the background (often under 3:1 against the tab row) is extra, and
  the label keeps 4.5:1 on any terminal background.
- Active pane uses a thin accent indicator. Direction and size labels appear
  only while navigating or resizing.
- Drag previews appear only during drag and name the resulting operation.
- Split dividers maximize hit target without increasing painted thickness.

### Menus

- Every popup menu goes through `src/apprt/win32/fancy_menu.zig`: a real
  Win32 menu underneath (keyboard, submenus, dismissal, screen readers) with
  rows drawn by Najm.
- The card: elevated surface, rounded corners and theme border from DWM, a
  2 px accent edge across the top. Rows are 32 px with a Fluent icon column,
  a rounded accent-wash highlight, and shortcuts as keycaps.
- Sizes follow the system menu font, so Windows "Text size" grows them; the
  text never drops below 14 px.
- A pointer opening uses the system menu animation; a keyboard opening shows
  at once. High Contrast gets the plain system menu.

### Universal palette

- Input and results are one card: the overlay panel carries the accent edge
  across its top, and the result list hangs from it flush with its sides,
  on the same surface, with a hairline under the input and rounded bottom
  corners. The shared highlight and keycaps come from the menus.
- Every overlay mode keeps the accent as a top edge; there is no coloured
  left bar.

- Single search field and blended result list, with discoverable scoped
  filters.
- Rows expose title, category, description, shortcut, disabled reason, and
  destructive status as needed.
- Selection, query changes, empty results, and execution outcomes are
  announced through UI Automation.
- Dedicated scrollback search remains a separate task surface.

The shipped palette feature set is tracked in the
[capability matrix notes](docs/windows-capability-matrix.md#universal-palette).

### Settings

- Inline validation and conflict resolution take precedence over modal
  dialogs.
- Reversible appearance changes may preview immediately; behavioral changes
  remain staged until Apply.
- Advanced always exposes the plain-text configuration escape hatch and a
  source-preserving diff.

The shipped section list and save semantics are tracked in the
[capability matrix notes](docs/windows-capability-matrix.md#native-settings).

### Feedback and recovery

- Banners are local, concise, and actionable; toasts are supplementary.
- Destructive actions name what will be lost and require an explicit action.
- Recovery surfaces favor: retry normally, launch safely, inspect
  quarantined data, open settings/config, export diagnostics.
- Empty states teach the next useful action rather than merely reporting
  absence.

## Motion

- Default duration: 120–200 ms; 240 ms maximum for large spatial
  transitions.
- Ease out with a quart/quint curve. No bounce or elastic motion.
- Animate compositor-friendly properties; do not animate terminal geometry
  when it delays viewport correctness.
- Motion communicates a state change: selection, focus transfer, reveal,
  dismissal, drag, or completion. It is never decoration.
- Reduced Motion makes transitions instant or uses a minimal crossfade.
- Settled UI has no animation or rendering heartbeat.

## Windows adaptation

- Windows 11 may use supported backdrop, corner, Snap Layout, and
  composition capabilities when they improve hierarchy.
- Windows 10 uses polished solid surfaces with identical geometry,
  workflows, and information.
- Native semantics win over visual uniformity for menus, IME, focus,
  keyboard navigation, touch, DPI, system theme, and accessibility.
- Device or composition failure must retain a readable native recovery
  path.

## Verification

Golden captures cover:

- Windows 10 and 11
- light, dark, system, and High Contrast modes
- 100 / 150 / 200 / 300% DPI
- 60 and 120 Hz
- active and inactive windows
- all component states, overflow, nested splits, palette, settings, drag
  previews, and recovery surfaces

Reject clipping, overlap, stale pixels, ambiguous focus, hidden state, or
terminal viewport loss. Pair visual checks with:

- keyboard traversal
- UI Automation inspection
- Narrator and NVDA
- reduced-motion and contrast validation
