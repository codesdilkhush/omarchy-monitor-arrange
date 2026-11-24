#!/usr/bin/env python3
import sys
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

def get_status():
    try:
        monitors_raw = subprocess.check_output(["hyprctl", "-j", "monitors", "all"]).decode()
        monitors = json.loads(monitors_raw)
    except Exception:
        monitors = []

    output = []
    for m in monitors:
        name = m.get("name", "")
        is_internal = name.startswith("eDP") or name.startswith("LVDS") or name.startswith("DSI")
        brightness = 100
        try:
            if is_internal:
                b_out = subprocess.check_output(["omarchy", "brightness", "display", "--monitor", name], stderr=subprocess.DEVNULL).decode().strip()
                brightness = int(b_out)
            else:
                b_out = subprocess.check_output(["omarchy-brightness-display-ddc", name], stderr=subprocess.DEVNULL).decode().strip()
                brightness = int(b_out)
        except Exception:
            brightness = 100

        # Filter and simplify available modes
        modes_raw = m.get("availableModes", [])
        clean_modes = []
        seen = set()
        for mode in modes_raw:
            cleaned = mode.replace("Hz", "")
            if cleaned not in seen:
                clean_modes.append(cleaned)
                seen.add(cleaned)

        width = m.get("width", 1920)
        height = m.get("height", 1080)
        # For disabled monitors, Hyprland might report 0x0; fall back to first available mode
        if (width == 0 or height == 0) and clean_modes:
            try:
                first_mode = clean_modes[0].split("@")[0]
                wh = first_mode.split("x")
                width = int(wh[0])
                height = int(wh[1])
            except Exception:
                pass

        output.append({
            "id": m.get("id", 0),
            "name": name,
            "description": m.get("description", name),
            "width": width,
            "height": height,
            "refreshRate": round(float(m.get("refreshRate", 60)), 2),
            "x": m.get("x", 0),
            "y": m.get("y", 0),
            "scale": m.get("scale", 1.0),
            "transform": m.get("transform", 0),
            "focused": m.get("focused", False),
            "disabled": m.get("disabled", False),
            "isInternal": is_internal,
            "brightness": brightness,
            "availableModes": clean_modes
        })

    print(json.dumps(output))

def set_brightness(name, percent):
    is_internal = name.startswith("eDP") or name.startswith("LVDS") or name.startswith("DSI")
    val = f"{int(percent)}%"
    try:
        if is_internal:
            subprocess.run(["omarchy", "brightness", "display", "--monitor", name, val], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            subprocess.run(["omarchy-brightness-display-ddc", name, val], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("ok")
    except Exception as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(1)

def make_rule(m):
    name = m["name"]
    if m.get("disabled", False):
        return f'hl.monitor({{ output = "{name}", disabled = true }})'
    width = m["width"]
    height = m["height"]
    hz = m["refreshRate"]
    x = m["x"]
    y = m["y"]
    scale = m["scale"]
    transform = m.get("transform", 0)
    return f'hl.monitor({{ output = "{name}", mode = "{width}x{height}@{hz}", position = "{x}x{y}", scale = {scale}, transform = {transform} }})'

def update_monitors_lua_content(existing_content, monitors_data):
    """
    Updates monitor rules in monitors.lua safely:
    - In-place updates for monitors currently being configured.
    - Strictly preserves ALL existing rules for absent or disabled displays (e.g. projectors).
    - Strictly preserves all user comments, documentation, and existing config lines.
    - Appends any newly configured display rules cleanly before GDK_SCALE.
    - Updates GDK_SCALE dynamically based on the minimum active scale.
    """
    output_to_rule = {m["name"]: make_rule(m) for m in monitors_data}
    updated_outputs = set()

    rule_regex = re.compile(r"^(\s*)hl\.monitor\s*\(\s*\{([^}]+)\}\s*\)")
    output_attr_regex = re.compile(r"""output\s*=\s*["']([^"']*)["']""")

    lines = existing_content.splitlines() if existing_content.strip() else []
    new_lines = []
    last_monitor_idx = -1
    catch_all_idx = -1

    for line in lines:
        stripped = line.strip()
        if stripped.startswith("--"):
            # Comment line: preserve exactly as-is
            new_lines.append(line)
            continue

        m_rule = rule_regex.match(line)
        if m_rule:
            content_inside = m_rule.group(2)
            m_out = output_attr_regex.search(content_inside)
            if m_out:
                out_name = m_out.group(1)
                if out_name == "":
                    # Catch-all rule: preserve
                    catch_all_idx = len(new_lines)
                    new_lines.append(line)
                    continue
                elif out_name in output_to_rule:
                    # Update active monitor rule in place!
                    new_lines.append(output_to_rule[out_name])
                    updated_outputs.add(out_name)
                    last_monitor_idx = len(new_lines) - 1
                    continue
            # Rule for an output not in the current payload (e.g. unplugged/disabled projector)
            # PRESERVE IT UNTOUCHED!
            new_lines.append(line)
            last_monitor_idx = len(new_lines) - 1
            continue

        new_lines.append(line)

    # If the file didn't exist or had no structure, provide standard Omarchy baseline
    if not new_lines:
        new_lines = [
            "-- See https://wiki.hypr.land/Configuring/Basics/Monitors/",
            "-- List current monitors and supported resolutions with: hyprctl monitors all",
            "",
            'local omarchy_monitor_scale = "auto"',
            'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })',
            ""
        ]
        catch_all_idx = 4

    # Any monitor in monitors_data that was not already present in the file must be inserted
    missing_monitors = [m["name"] for m in monitors_data if m["name"] not in updated_outputs]
    if missing_monitors:
        insert_idx = len(new_lines)
        if last_monitor_idx != -1:
            insert_idx = last_monitor_idx + 1
        elif catch_all_idx != -1:
            insert_idx = catch_all_idx + 1
        else:
            for i, l in enumerate(new_lines):
                if "omarchy_gdk_scale" in l or "GDK_SCALE" in l:
                    insert_idx = i
                    break

        to_insert = [output_to_rule[name] for name in missing_monitors]
        new_lines[insert_idx:insert_idx] = to_insert

    # Update GDK_SCALE (minimum scale among active non-disabled monitors)
    scales = [float(m.get("scale", 1.0)) for m in monitors_data if not m.get("disabled", False)]
    min_scale = min(scales) if scales else 1.0
    gdk_scale = max(1, int(min_scale + 0.5))

    final_lines = []
    has_gdk_def = False
    has_gdk_env = False
    for line in new_lines:
        if re.match(r"^(\s*)local\s+omarchy_gdk_scale\s*=", line):
            final_lines.append(f"local omarchy_gdk_scale = {gdk_scale}")
            has_gdk_def = True
        elif re.match(r"""^(\s*)hl\.env\s*\(\s*["']GDK_SCALE["']\s*,""", line):
            final_lines.append('hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))')
            has_gdk_env = True
        else:
            final_lines.append(line)

    if not has_gdk_def:
        final_lines.append("")
        final_lines.append(f"local omarchy_gdk_scale = {gdk_scale}")
    if not has_gdk_env:
        final_lines.append('hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))')

    return "\n".join(final_lines).rstrip() + "\n"

def save_layout(payload):
    try:
        data = json.loads(payload)
        monitors_lua = Path.home() / ".config/hypr/monitors.lua"
        monitors_lua.parent.mkdir(parents=True, exist_ok=True)

        existing_content = ""
        if monitors_lua.exists():
            try:
                existing_content = monitors_lua.read_text()
            except Exception:
                existing_content = ""

        new_content = update_monitors_lua_content(existing_content, data)

        # Atomic write via temporary file
        tmp_file = monitors_lua.with_suffix(f".tmp.{os.getpid()}")
        try:
            tmp_file.write_text(new_content)
            if monitors_lua.exists():
                shutil.copymode(monitors_lua, tmp_file)
            os.replace(tmp_file, monitors_lua)
        finally:
            if tmp_file.exists():
                try:
                    tmp_file.unlink()
                except Exception:
                    pass

        # Apply atomically via Hyprland reload
        subprocess.run(["hyprctl", "reload"], check=True, stdout=subprocess.DEVNULL)
        subprocess.run(["hyprctl", "dismissnotify"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("saved")
    except Exception as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(1)

def apply_layout(payload):
    save_layout(payload)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        get_status()
    elif sys.argv[1] == "status":
        get_status()
    elif sys.argv[1] == "set-brightness" and len(sys.argv) >= 4:
        set_brightness(sys.argv[2], sys.argv[3])
    elif sys.argv[1] == "apply" and len(sys.argv) >= 3:
        apply_layout(sys.argv[2])
    elif sys.argv[1] == "save" and len(sys.argv) >= 3:
        save_layout(sys.argv[2])
    else:
        print("Usage: backend.py [status|set-brightness <name> <pct>|apply <json>|save <json>]", file=sys.stderr)
        sys.exit(1)
