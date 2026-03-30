import QtQuick
import QtQuick.Layouts
import qs.Commons

ColumnLayout {
  id: root

  property var pluginApi: null

  // The plugin settings popup sets Loader.width, so mirror it here
  // to prevent nested layouts from collapsing to 0 width.
  width: parent ? parent.width : implicitWidth
  spacing: Style.marginM

  MonitorSettings {
    pluginApi: root.pluginApi
    id: monitorSettings
    Layout.fillWidth: true
    // Let the popup scroll view size from real content height.
    Layout.preferredHeight: implicitHeight
  }

  implicitHeight: monitorSettings.implicitHeight

  function saveSettings() {
    // This plugin currently edits compositor/runtime state directly.
    // Keep a no-op save function so the plugin settings dialog can close cleanly.
    if (pluginApi)
      pluginApi.saveSettings();
  }
}


