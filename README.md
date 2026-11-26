# Display Studio for Omarchy

Interactive drag-and-drop monitor arrangement, display resolution, refresh rate, scaling, orientation, and hardware brightness controls for Omarchy on Hyprland.

![Display Studio Preview](preview.png)

## Features

- **Drag-and-Drop Arrangement Canvas** — Visually drag monitors into position with automatic edge snapping and overlap reconciliation so active screens always sit flush.
- **Internal & External Brightness** — Adjusts laptop panel backlights via `omarchy brightness display` and external displays via DDC/CI (`omarchy-brightness-display-ddc`).
- **Per-Monitor Mode Controls** — Select supported resolutions and refresh rates (`Hz`), display scaling presets (`100%`–`200%`), orientation (`0° Landscape`, `90° Portrait`, `180° Inverted`), and enable/disable outputs.
- **Safe Non-Destructive Saving** — Updates matching `hl.monitor(...)` rules and `GDK_SCALE` atomically in `~/.config/hypr/monitors.lua`, preserving comments, catch-all rules, and disconnected/external monitor rules, then reloads Hyprland (`hyprctl reload`).

## Requirements

- Omarchy 4 (Quattro) or later (`omarchy-shell`) on Hyprland (`hyprctl`)
- `python3` (included by default with Omarchy; uses only the Python standard library in [backend.py](backend.py))
- Optional: `omarchy-brightness-display-ddc` (`ddcutil`) for brightness control on external monitors

## Install

```bash
omarchy plugin add https://github.com/codesdilkhush/omarchy-monitor-arrange --enable
```

To move the widget to another bar section:

```bash
omarchy bar move codesdilkhush.monitor-arrange --section center
```

## Uninstall

```bash
omarchy plugin remove codesdilkhush.monitor-arrange
```

Uninstalling the plugin does not revert your saved `~/.config/hypr/monitors.lua` display configuration.

## Controls

| Action | Mouse / Keyboard |
|---|---|
| Open / close Display Studio | Left click bar icon (`omarchy-shell codesdilkhush.monitor-arrange toggle`) |
| Select a monitor | Click monitor card on the canvas |
| Reposition monitors | Drag monitor card and release to snap & apply |
| Adjust brightness | Drag or click the brightness slider |
| Change mode, scale, or orientation | Pick from Resolution / Refresh Rate dropdowns or preset buttons |
| Close popup | Click outside or press `Esc` |

Optional Hyprland keybinding in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + SHIFT + P", "Display Studio", "omarchy-shell codesdilkhush.monitor-arrange toggle")
```

## Configuration & Safety

- Reads display topology and available modes on demand via `hyprctl -j monitors all` (no background polling when closed).
- Writes `~/.config/hypr/monitors.lua` only when you reposition a monitor or change display settings, using an atomic temporary-file swap (`os.replace`) while keeping existing rules for unplugged outputs untouched.

## License

[MIT](LICENSE)
