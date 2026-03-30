# Display Control Plugin

This plugin contains the display configuration work that previously lived in the native `Display` settings tab.

## Why It May Not Load

Noctalia only scans plugins in `~/.config/noctalia/plugins/` (or `$NOCTALIA_CONFIG_DIR/plugins`).
Keeping this folder only inside the repository does not auto-register it.

## Install (Docs-Aligned)

Run the installer from this plugin directory. It will:

- symlink this plugin into the active Noctalia plugins directory
- create/patch `plugins.json` using the current v2 format
- enable `display-control`

```bash
cd Plugins/display-control
./install.sh
```

Then restart Noctalia:

```bash
killall qs
qs -c noctalia-shell
```

## Verify Registration

```bash
cat ~/.config/noctalia/plugins.json
ls -la ~/.config/noctalia/plugins/display-control
```

`plugins.json` should contain:

- `version: 2`
- `states.display-control.enabled: true`
- `states.display-control.sourceUrl`

## Included

- Monitor topology editor (drag/snap)
- Resolution / refresh mode switching
- Scale / transform / VRR controls
- EDID read + decode actions

## Development note

`MonitorSettings.qml` and `DisplayServiceModel.qml` are migrated from the native implementation.

