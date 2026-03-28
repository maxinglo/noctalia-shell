import QtQuick
import Quickshell
import Quickshell.Niri
import qs.Commons
import qs.Services.Keyboard

Item {
  id: root

  property int floatingWindowPosition: Number.MAX_SAFE_INTEGER

  property ListModel workspaces: ListModel {}
  property var windows: []
  property int focusedWindowIndex: -1

  property bool overviewActive: false

  property var keyboardLayouts: []

  signal workspaceChanged
  signal activeWindowChanged
  signal windowListChanged
  signal displayScalesChanged

  property var outputCache: ({})
  property var workspaceCache: ({})
  property var displayBackend: ({
    generateRevertCmds: function (snap, curSnap) {
      let pending = [];
      let onOffCmds = [];
      for (const outputName in snap) {
        const s = snap[outputName];
        const cur = curSnap[outputName] || {};

        if (s.enabled !== cur.enabled) {
          onOffCmds.push(["niri", "msg", "output", outputName, s.enabled ? "on" : "off"]);
        }

        if (s.enabled === false)
          continue;

        if (s.modeStr && s.modeStr !== cur.modeStr) {
          pending.push(["niri", "msg", "output", outputName, "mode", s.modeStr]);
        }
        if (s.scale !== cur.scale) {
          pending.push(["niri", "msg", "output", outputName, "scale", String(s.scale)]);
        }
        if (s.transform !== cur.transform) {
          const tMap = {
            "Normal": "normal",
            "90": "90",
            "180": "180",
            "270": "270",
            "Flipped": "flipped",
            "Flipped90": "flipped-90",
            "Flipped180": "flipped-180",
            "Flipped270": "flipped-270"
          };
          pending.push(["niri", "msg", "output", outputName, "transform", tMap[s.transform] || "normal"]);
        }
        if (Math.round(s.x) !== Math.round(cur.x) || Math.round(s.y) !== Math.round(cur.y)) {
          pending.push(["niri", "msg", "output", outputName, "position", "set", "--", String(Math.round(s.x)), String(Math.round(s.y))]);
        }
        if (s.vrr_enabled !== cur.vrr_enabled) {
          pending.push(["niri", "msg", "output", outputName, "vrr", s.vrr_enabled ? "on" : "off"]);
        }
      }
      return onOffCmds.concat(pending);
    },
    parseFetch: function (rawData) {
      const data = {};

      function normalizeRefreshMilli(value) {
        const r = Number(value);
        if (!isFinite(r) || r <= 0)
          return 60000;
        // Tolerate Hz-style refresh values defensively.
        return r < 1000 ? Math.round(r * 1000) : Math.round(r);
      }

      function normalizeModes(mon) {
        const sourceModes = Array.isArray(mon && mon.modes) ? mon.modes : [];
        const normalized = [];
        let currentIdx = -1;

        for (let i = 0; i < sourceModes.length; i++) {
          const m = sourceModes[i] || {};
          const entry = {
            width: Number(m.width) || 0,
            height: Number(m.height) || 0,
            refresh_rate: normalizeRefreshMilli(m.refresh_rate !== undefined ? m.refresh_rate : m.refresh)
          };
          normalized.push(entry);
          if (m.is_current === true || m.current === true)
            currentIdx = normalized.length - 1;
        }

        const cur = mon ? mon.current_mode : null;
        if (Number.isInteger(cur) && cur >= 0 && cur < normalized.length) {
          currentIdx = cur;
        } else if (cur && typeof cur === "object" && normalized.length > 0) {
          const cw = Number(cur.width) || 0;
          const ch = Number(cur.height) || 0;
          const cr = normalizeRefreshMilli(cur.refresh_rate !== undefined ? cur.refresh_rate : cur.refresh);
          for (let i = 0; i < normalized.length; i++) {
            const m = normalized[i];
            const sameSize = m.width === cw && m.height === ch;
            const sameRate = Math.abs(m.refresh_rate - cr) < 2;
            if (sameSize && sameRate) {
              currentIdx = i;
              break;
            }
          }
        }

        if (currentIdx < 0 && normalized.length > 0) {
          const logical = mon && mon.logical ? mon.logical : {};
          const lw = Number(logical.width) || 0;
          const lh = Number(logical.height) || 0;
          for (let i = 0; i < normalized.length; i++) {
            if (normalized[i].width === lw && normalized[i].height === lh) {
              currentIdx = i;
              break;
            }
          }
        }

        if (currentIdx < 0 && normalized.length > 0)
          currentIdx = 0;

        return {
          modes: normalized,
          currentMode: currentIdx
        };
      }

      function resolveEnabled(mon) {
        if (!mon)
          return false;
        if (mon.enabled !== undefined)
          return mon.enabled !== false;
        if (mon.active !== undefined)
          return mon.active === true;
        if (mon.logical === null || mon.current_mode === null)
          return false;
        return true;
      }

      if (Array.isArray(rawData)) {
        for (let i = 0; i < rawData.length; i++) {
          const mon = rawData[i];
          if (!mon || !mon.name)
            continue;
          const normalized = normalizeModes(mon);
          mon.modes = normalized.modes;
          mon.current_mode = normalized.currentMode;
          mon.enabled = resolveEnabled(mon);
          data[mon.name] = mon;
        }
        return data;
      }

      if (rawData && typeof rawData === "object") {
        for (const outputName in rawData) {
          const mon = rawData[outputName];
          if (!mon)
            continue;
          if (!mon.name)
            mon.name = outputName;
          const normalized = normalizeModes(mon);
          mon.modes = normalized.modes;
          mon.current_mode = normalized.currentMode;
          mon.enabled = resolveEnabled(mon);
          data[mon.name] = mon;
        }
        return data;
      }

      return {};
    },
    buildSetModeCmd: function (outputName, cfg) {
      return [["niri", "msg", "output", outputName, "mode", cfg.modeStr]];
    },
    buildSetScaleCmd: function (outputName, cfg) {
      return [["niri", "msg", "output", outputName, "scale", String(cfg.scale)]];
    },
    buildSetTransformCmd: function (outputName, cfg) {
      const tMap = {
        "Normal": "normal",
        "90": "90",
        "180": "180",
        "270": "270",
        "Flipped": "flipped",
        "Flipped90": "flipped-90",
        "Flipped180": "flipped-180",
        "Flipped270": "flipped-270"
      };
      return [["niri", "msg", "output", outputName, "transform", tMap[cfg.transform] || "normal"]];
    },
    buildSetVrrCmd: function (outputName, cfg) {
      return [["niri", "msg", "output", outputName, "vrr", cfg.vrr_enabled ? "on" : "off"]];
    },
    buildToggleOutputCmd: function (outputName, enabled) {
      return [["niri", "msg", "output", outputName, enabled ? "on" : "off"]];
    },
    buildPositionsCmds: function (targetConfig) {
      let pending = [];
      for (const name in targetConfig) {
        const cfg = targetConfig[name];
        if (cfg.enabled === false)
          continue;
        pending.push(["niri", "msg", "output", name, "position", "set", "--", String(Math.round(cfg.x)), String(Math.round(cfg.y))]);
      }
      return pending;
    },
    _transformToNiri: function (transform) {
      const tMap = {
        "normal": "normal",
        "Normal": "normal",
        "90": "90",
        "180": "180",
        "270": "270",
        "flipped": "flipped",
        "Flipped": "flipped",
        "flipped-90": "flipped-90",
        "Flipped90": "flipped-90",
        "flipped-180": "flipped-180",
        "Flipped180": "flipped-180",
        "flipped-270": "flipped-270",
        "Flipped270": "flipped-270"
      };
      return tMap[String(transform || "normal")] || "normal";
    },
    _escapeKdlString: function (text) {
      return String(text || "").replace(/\\/g, "\\\\").replace(/"/g, '\\"');
    },
    getPersistenceConfigPath: function () {
      const xdg = Quickshell.env("XDG_CONFIG_HOME");
      const home = Quickshell.env("HOME");
      const base = (xdg && xdg.length > 0) ? xdg : ((home && home.length > 0) ? home + "/.config" : "~/.config");
      return base + "/niri/config.kdl";
    },
    getPersistenceMarkers: function () {
      return {
        begin: "// >>> NOCTALIA DISPLAY CONFIG >>>",
        end: "// <<< NOCTALIA DISPLAY CONFIG <<<"
      };
    },
    getPersistenceLegacyMode: function () {
      return "niri";
    },
    getPersistenceLegacyCommentStyle: function () {
      return "block";
    },
    getPersistenceBlockCommentStart: function () {
      return "/* NOCTALIA_DISABLED_DISPLAY_BEGIN";
    },
    getPersistenceBlockCommentEnd: function () {
      return "NOCTALIA_DISABLED_DISPLAY_END */";
    },
    buildPersistencePayload: function (targetConfig) {
      const lines = ["// Managed by Noctalia monitor settings."];
      const names = Object.keys(targetConfig || {}).sort((a, b) => String(a).localeCompare(String(b)));

      function toNiriMode(modeStr) {
        const raw = String(modeStr || "").trim();
        if (raw === "")
          return "preferred";
        const at = raw.split("@");
        if (at.length !== 2)
          return raw;
        const hz = Number(at[1]);
        if (!isFinite(hz) || hz <= 0)
          return raw;
        return at[0] + "@" + hz.toFixed(3);
      }

      for (const name of names) {
        const cfg = targetConfig[name] || {};
        const outName = this._escapeKdlString(name);

        lines.push("output \"" + outName + "\" {");
        if (cfg.enabled === false) {
          lines.push("    off");
          lines.push("}");
          lines.push("");
          continue;
        }

        const x = Math.round(cfg.x || 0);
        const y = Math.round(cfg.y || 0);
        const mode = toNiriMode(cfg.modeStr);
        const scale = String(cfg.scale !== undefined ? cfg.scale : 1);
        const transform = this._transformToNiri(cfg.transform);

        lines.push("    mode \"" + this._escapeKdlString(mode) + "\"");
        lines.push("    scale " + this._escapeKdlString(scale));
        lines.push("    transform \"" + this._escapeKdlString(transform) + "\"");
        if (cfg.vrr_enabled !== undefined)
          lines.push("    variable-refresh-rate on-demand=" + (cfg.vrr_enabled ? "true" : "false"));
        lines.push("    position x=" + x + " y=" + y);
        lines.push("}");
        lines.push("");
      }

      while (lines.length > 0 && lines[lines.length - 1] === "")
        lines.pop();
      return lines.join("\n") + "\n";
    }
  })

  function initialize() {
    Niri.refreshOutputs();
    Niri.refreshWorkspaces();
    Niri.refreshWindows();

    Qt.callLater(() => {
                   safeUpdateOutputs();
                   safeUpdateWorkspaces();
                   safeUpdateWindows();
                   queryDisplayScales();
                 });

    Logger.i("NiriService", "Service started");
  }

  // Connections to the C++ Niri IPC module
  Connections {
    target: Niri
    function onWorkspacesUpdated() {
      safeUpdateWorkspaces();
      workspaceChanged();
    }
    function onWindowsUpdated() {
      safeUpdateWindows();
      windowListChanged();
      activeWindowChanged();
    }
    function onOutputsUpdated() {
      safeUpdateOutputs();
      queryDisplayScales();
    }
    function onOverviewActiveChanged() {
      overviewActive = Niri.overviewActive;
    }
    function onKeyboardLayoutsChanged() {
      keyboardLayouts = Niri.keyboardLayoutNames;
      const layoutName = Niri.currentKeyboardLayoutName;
      if (layoutName) {
        KeyboardLayoutService.setCurrentLayout(layoutName);
      }
      Logger.d("NiriService", "Keyboard layouts changed:", keyboardLayouts.toString());
    }
    function onKeyboardLayoutSwitched() {
      const layoutName = Niri.currentKeyboardLayoutName;
      if (layoutName) {
        KeyboardLayoutService.setCurrentLayout(layoutName);
      }
      Logger.d("NiriService", "Keyboard layout switched:", layoutName);
    }
  }

  function safeUpdateOutputs() {
    const niriOutputs = Niri.outputs.values;
    outputCache = {};

    for (var i = 0; i < niriOutputs.length; i++) {
      const output = niriOutputs[i];
      outputCache[output.name] = {
        "name": output.name,
        "connected": output.connected,
        "scale": output.scale,
        "width": output.width,
        "height": output.height,
        "x": output.x,
        "y": output.y,
        "physical_width": output.physicalWidth,
        "physical_height": output.physicalHeight,
        "refresh_rate": output.refreshRate,
        "vrr_supported": output.vrrSupported,
        "vrr_enabled": output.vrrEnabled,
        "transform": output.transform
      };
    }
  }

  function safeUpdateWorkspaces() {
    const niriWorkspaces = Niri.workspaces.values;
    workspaceCache = {};

    const workspacesList = [];
    for (var i = 0; i < niriWorkspaces.length; i++) {
      const ws = niriWorkspaces[i];
      const wsData = {
        "id": ws.id,
        "idx": ws.idx,
        "name": ws.name,
        "output": ws.output,
        "isFocused": ws.focused,
        "isActive": ws.active,
        "isUrgent": ws.urgent,
        "isOccupied": ws.occupied
      };
      workspacesList.push(wsData);
      workspaceCache[ws.id] = wsData;
    }

    // Workspaces come pre-sorted from C++ (by output then idx)
    workspaces.clear();
    for (var j = 0; j < workspacesList.length; j++) {
      workspaces.append(workspacesList[j]);
    }
  }

  function getWindowOutput(win) {
    for (var i = 0; i < workspaces.count; i++) {
      if (workspaces.get(i).id === win.workspaceId) {
        return workspaces.get(i).output;
      }
    }
    return null;
  }

  function toSortedWindowList(windowList) {
    return windowList.map(win => {
                            const workspace = workspaceCache[win.workspaceId];
                            const output = (workspace && workspace.output) ? outputCache[workspace.output] : null;

                            return {
                              window: win,
                              workspaceIdx: workspace ? workspace.idx : 0,
                              outputX: output ? output.x : 0,
                              outputY: output ? output.y : 0
                            };
                          }).sort((a, b) => {
                                    // Sort by output position first
                                    if (a.outputX !== b.outputX) {
                                      return a.outputX - b.outputX;
                                    }
                                    if (a.outputY !== b.outputY) {
                                      return a.outputY - b.outputY;
                                    }
                                    // Then by workspace index
                                    if (a.workspaceIdx !== b.workspaceIdx) {
                                      return a.workspaceIdx - b.workspaceIdx;
                                    }
                                    // Then by window position
                                    if (a.window.position.x !== b.window.position.x) {
                                      return a.window.position.x - b.window.position.x;
                                    }
                                    if (a.window.position.y !== b.window.position.y) {
                                      return a.window.position.y - b.window.position.y;
                                    }
                                    // Finally by window ID to ensure consistent ordering
                                    return a.window.id - b.window.id;
                                  }).map(info => info.window);
  }

  function safeUpdateWindows() {
    const niriWindows = Niri.windows.values;
    const windowsList = [];

    for (var i = 0; i < niriWindows.length; i++) {
      const win = niriWindows[i];
      windowsList.push({
                         "id": win.id,
                         "title": win.title || "",
                         "appId": win.appId || "",
                         "workspaceId": win.workspaceId || -1,
                         "isFocused": win.focused,
                         "output": win.output || getWindowOutput(win) || "",
                         "position": {
                           "x": win.isFloating ? floatingWindowPosition : win.positionX,
                           "y": win.isFloating ? floatingWindowPosition : win.positionY
                         }
                       });
    }

    windows = toSortedWindowList(windowsList);
    safeUpdateFocusedWindow();
  }

  function safeUpdateFocusedWindow() {
    focusedWindowIndex = -1;
    for (var i = 0; i < windows.length; i++) {
      if (windows[i].isFocused) {
        focusedWindowIndex = i;
        break;
      }
    }
  }

  function queryDisplayScales() {
    if (CompositorService && CompositorService.onDisplayScalesUpdated) {
      CompositorService.onDisplayScalesUpdated(outputCache);
    }
  }

  function switchToWorkspace(workspace) {
    try {
      Niri.dispatch(["focus-workspace", workspace.idx.toString()]);
    } catch (e) {
      Logger.e("NiriService", "Failed to switch workspace:", e);
    }
  }

  function scrollWorkspaceContent(direction) {
    try {
      var action = direction < 0 ? "focus-column-left" : "focus-column-right";
      Niri.dispatch([action]);
    } catch (e) {
      Logger.e("NiriService", "Failed to scroll workspace content:", e);
    }
  }

  function focusWindow(window) {
    try {
      Niri.dispatch(["focus-window", "--id", window.id.toString()]);
    } catch (e) {
      Logger.e("NiriService", "Failed to switch window:", e);
    }
  }

  function closeWindow(window) {
    try {
      Niri.dispatch(["close-window", "--id", window.id.toString()]);
    } catch (e) {
      Logger.e("NiriService", "Failed to close window:", e);
    }
  }

  function turnOffMonitors() {
    try {
      Niri.dispatch(["power-off-monitors"]);
    } catch (e) {
      Logger.e("NiriService", "Failed to turn off monitors:", e);
    }
  }

  function turnOnMonitors() {
    try {
      Niri.dispatch(["power-on-monitors"]);
    } catch (e) {
      Logger.e("NiriService", "Failed to turn on monitors:", e);
    }
  }

  function logout() {
    try {
      Niri.dispatch(["quit", "--skip-confirmation"]);
    } catch (e) {
      Logger.e("NiriService", "Failed to logout:", e);
    }
  }

  function cycleKeyboardLayout() {
    try {
      Niri.dispatch(["switch-layout", "next"]);
    } catch (e) {
      Logger.e("NiriService", "Failed to cycle keyboard layout:", e);
    }
  }

  function getFocusedScreen() {
    // On niri the code below only works when you have an actual app selected on that screen.
    return null;
  }

  function spawn(command) {
    try {
      const niriArgs = ["spawn", "--"].concat(command);
      Logger.d("NiriService", "Calling niri spawn: niri msg action " + niriArgs.join(" "));
      Niri.dispatch(niriArgs);
    } catch (e) {
      Logger.e("NiriService", "Failed to spawn command:", e);
    }
  }
}
