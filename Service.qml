import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Tracks NetworkManager VPN and WireGuard profiles through nmcli.
// Profiles are addressed by UUID, so duplicate names and names containing
// characters nmcli escapes (":" and "\") work correctly.
Item {
  id: root

  property var settings: ({})
  // Commons.Translations instance owned by the panel.
  property var strings: null

  // [{ type, uuid, name, state: "activated" | "activating" | "deactivating" | "" }, ...]
  property var vpns: []
  property string busyUuid: ""   // profile currently being (dis)connected
  property string busyName: ""
  property string busyKind: ""   // "connect" | "disconnect"
  property string lastError: ""  // last connect/disconnect failure
  property string listError: ""  // failure reading the profile list
  // nm-connection-editor ships with network-manager-applet, which stock
  // Omarchy does not install.
  property bool editorAvailable: false

  // nmcli gives up on an activation after this many seconds instead of its 90 s default.
  readonly property int actionTimeoutSec: 30
  // Changes arrive through `nmcli monitor`; polling is only a fallback.
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 60, 10, 600)
  readonly property var activeVpns: Model.namesInState(vpns, "activated")
  readonly property var activatingVpns: Model.namesInState(vpns, "activating")
  readonly property bool connected: activeVpns.length > 0
  readonly property bool connecting: activatingVpns.length > 0

  function tr(key) {
    return strings ? strings.t(key) : key
  }

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function notify(body, critical) {
    var cmd = ["notify-send"]
    if (critical) cmd.push("-u", "critical")
    cmd.push("VPN", Model.escapeMarkup(body))
    Quickshell.execDetached(cmd)
  }

  function openEditor() {
    if (editorAvailable) Quickshell.execDetached(["nm-connection-editor"])
    else notify(tr("editor.missing"), false)
  }

  property bool _refreshPending: false

  function refresh() {
    if (listProc.running) { _refreshPending = true; return }
    _refreshPending = false
    _listDone = 0
    listProc.running = true
  }

  function find(uuid) {
    for (var i = 0; i < vpns.length; i++) if (vpns[i].uuid === uuid) return vpns[i]
    return null
  }

  property bool _cancelled: false

  function toggle(uuid) {
    if (busyUuid !== "") {
      if (uuid === busyUuid && busyKind === "connect") cancel()
      return
    }
    var entry = find(uuid)
    if (!entry) return
    if (entry.state === "activated" || entry.state === "activating") run(entry, "disconnect")
    else run(entry, "connect")
  }

  // Aborts the activation nmcli is waiting on; the pending `up` then exits
  // with an error, which actionProc reports as a cancellation.
  function cancel() {
    if (busyUuid === "" || busyKind !== "connect" || cancelProc.running) return
    _cancelled = true
    cancelProc.command = ["nmcli", "connection", "down", "uuid", busyUuid]
    cancelProc.running = true
  }

  function run(entry, kind) {
    _cancelled = false
    busyUuid = entry.uuid
    busyName = entry.name
    busyKind = kind
    lastError = ""
    notify(tr(kind === "connect" ? "notify.connecting" : "notify.disconnecting").arg(entry.name), false)
    actionProc.command = ["nmcli", "--wait", String(actionTimeoutSec), "connection", kind === "connect" ? "up" : "down", "uuid", entry.uuid]
    actionProc.running = true
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  // The list is applied only after both the process exit and the end of its
  // output have been seen, whichever arrives last.
  property int _listDone: 0
  property int _listExitCode: 0

  function finishList() {
    if (++_listDone < 2) return
    if (_listExitCode === 0) {
      vpns = Model.parseVpns(listStdout.text)
      listError = ""
    } else {
      var err = String(listStderr.text || "").trim()
      listError = err || tr("error.listFailed").arg(_listExitCode)
    }
    if (_refreshPending) Qt.callLater(refresh)
  }

  Process {
    id: listProc
    running: false
    command: ["nmcli", "-t", "-f", "TYPE,UUID,STATE,NAME", "connection", "show"]
    stdout: StdioCollector {
      id: listStdout
      waitForEnd: true
      onStreamFinished: root.finishList()
    }
    stderr: StdioCollector { id: listStderr; waitForEnd: true }
    onExited: function(exitCode) {
      root._listExitCode = exitCode
      root.finishList()
    }
  }

  Process {
    id: actionProc
    running: false
    command: []
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var name = root.busyName
      var kind = root.busyKind
      if (exitCode === 0) {
        root.lastError = ""
        if (kind === "connect") root.notify(root.tr("notify.connected").arg(name), false)
      } else if (root._cancelled) {
        root.lastError = ""
        root.notify(root.tr("notify.cancelled").arg(name), false)
      } else {
        var err = String(actionStderr.text || "").trim()
        var summary = root.tr(kind === "connect" ? "notify.connectFailed" : "notify.disconnectFailed")
        root.lastError = Model.isSecretsError(err) ? root.tr("error.secrets") : (err || summary)
        root.notify(summary, true)
      }
      root.busyUuid = ""
      root.busyName = ""
      root.busyKind = ""
      root._cancelled = false
      root.refresh()
    }
  }

  Process {
    id: cancelProc
    running: false
    command: []
  }

  Process {
    id: editorCheck
    running: true
    command: ["sh", "-c", "command -v nm-connection-editor >/dev/null"]
    onExited: function(exitCode) { root.editorAvailable = exitCode === 0 }
  }

  // Event-driven updates: `nmcli monitor` prints a line on every
  // NetworkManager change; bursts are coalesced into one refresh.
  Timer {
    id: monitorDebounce
    interval: 300
    onTriggered: root.refresh()
  }

  Timer {
    id: monitorRestart
    interval: 5000
    onTriggered: monitorProc.running = true
  }

  Process {
    id: monitorProc
    running: true
    command: ["nmcli", "monitor"]
    stdout: SplitParser {
      onRead: function(line) { monitorDebounce.restart() }
    }
    onExited: function(exitCode) {
      console.warn("bvm.vpn: nmcli monitor exited with code " + exitCode + ", restarting in 5 s")
      monitorRestart.restart()
    }
  }
}
