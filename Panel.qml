import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

Panel {
  id: root
  moduleName: "valentinbasin.vpn"
  ipcTarget: "valentinbasin.vpn"
  // Owning our own IpcHandler (below) so we can add a "refresh" method
  // alongside the standard open/close/show/hide/toggle.
  manageIpc: false

  readonly property color dim: Qt.darker(barForeground, 1.4)
  readonly property color barIconColor: vpn.connected ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property string connectedIcon: ""
  readonly property string disconnectedIcon: ""

  // --- keyboard navigation --------------------------------------------------
  property bool cursorActive: false
  property string focusSection: "vpns"   // "vpns" | "editor"
  property int vpnIndex: 0

  function ensureCursor() {
    if (vpn.vpns.length === 0 && focusSection === "vpns") focusSection = "editor"
    if (vpnIndex >= vpn.vpns.length) vpnIndex = Math.max(0, vpn.vpns.length - 1)
    if (vpnIndex < 0) vpnIndex = 0
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy !== 0) {
      if (focusSection === "vpns") {
        if (dy < 0) {
          if (vpnIndex > 0) vpnIndex--
        } else {
          if (vpnIndex < vpn.vpns.length - 1) vpnIndex++
          else focusSection = "editor"
        }
      } else if (focusSection === "editor") {
        if (dy < 0 && vpn.vpns.length > 0) {
          focusSection = "vpns"
          vpnIndex = vpn.vpns.length - 1
        }
      }
    }
    ensureCursor()
    scrollCursorIntoView()
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "vpns") {
      var entry = vpn.vpns[vpnIndex]
      if (entry) {
        vpn.toggle(entry.uuid)
        // Get out of the way so the result notification is visible.
        root.close()
      }
    } else if (focusSection === "editor" && vpn.editorAvailable) {
      vpn.openEditor()
      root.close()
    }
  }

  function setVpnCursor(index) {
    cursorActive = true
    focusSection = "vpns"
    vpnIndex = index
  }

  function setEditorCursor() {
    cursorActive = true
    focusSection = "editor"
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    if (focusSection === "vpns" && vpnRepeater && vpnIndex >= 0 && vpnIndex < vpnRepeater.count) scrollItemIntoView(vpnRepeater.itemAt(vpnIndex))
    else if (focusSection === "editor" && editorRowItem) scrollItemIntoView(editorRowItem)
  }

  Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  Service {
    id: vpn
    settings: root.settings
    strings: strings
  }

  Connections {
    target: vpn
    function onVpnsChanged() { root.ensureCursor() }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { vpn.refresh(); return "ok" }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    focusSection = vpn.vpns.length > 0 ? "vpns" : "editor"
    vpnIndex = 0
    if (panelFlick) panelFlick.contentY = 0
    vpn.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: {
      var parts = []
      if (vpn.connected) parts.push(strings.t("tooltip.connected").arg(vpn.activeVpns.join("\n")))
      if (vpn.connecting) parts.push(strings.t("tooltip.connecting").arg(vpn.activatingVpns.join("\n")))
      if (parts.length === 0) parts.push(strings.t("status.disconnected"))
      if (vpn.listError !== "") parts.push(strings.t("tooltip.error").arg(vpn.listError))
      return parts.join("\n\n")
    }
    // Use the built-in glyph path so the icon gets the same optical centering as other bar icons.
    text: vpn.connected ? root.connectedIcon : root.disconnectedIcon
    foreground: root.barIconColor
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) vpn.openEditor()
      else if (buttonCode === Qt.MiddleButton) vpn.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(300))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(420))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "VPN"
            meta: vpn.connected ? strings.t("status.connectedTo").arg(vpn.activeVpns.join(", "))
              : vpn.connecting ? strings.t("status.connectingTo").arg(vpn.activatingVpns.join(", "))
              : strings.t("status.disconnected")
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            iconOpacity: vpn.connected ? 1.0 : 0.5
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: vpn.connected ? root.connectedIcon : root.disconnectedIcon
                color: root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.display
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            text: [vpn.listError, vpn.lastError].filter(function(e) { return e !== "" }).join("\n")
            color: root.bar ? root.bar.urgent : Color.urgent
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator { foreground: root.barForeground }

          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: strings.t("section.connections").toUpperCase()
              foreground: root.barForeground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            }

            Text {
              textFormat: Text.PlainText
              visible: vpn.vpns.length === 0 && vpn.listError === ""
              width: parent.width
              text: strings.t(vpn.editorAvailable ? "list.empty" : "list.emptyNoEditor")
              color: root.dim
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Column {
              id: vpnColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                id: vpnRepeater
                model: vpn.vpns
                VpnRow {
                  required property var modelData
                  required property int index
                  width: vpnColumn.width
                  entry: modelData
                  rowIndex: index
                }
              }
            }
          }

          PanelSeparator { foreground: root.barForeground }

          EditorRow {
            id: editorRowItem
            width: parent.width
          }
        }
      }
    }
  }

  component VpnRow: CursorSurface {
    id: vpnRow
    property var entry: null
    property int rowIndex: 0
    readonly property string vpnState: entry ? String(entry.state || "") : ""
    readonly property bool active: vpnState === "activated"
    readonly property bool activating: vpnState === "activating"
    readonly property string vpnName: entry ? String(entry.name || "") : ""
    readonly property string vpnUuid: entry ? String(entry.uuid || "") : ""
    readonly property bool busy: vpn.busyUuid !== "" && vpn.busyUuid === vpnUuid
    // A connection this plugin started can be cancelled from its row.
    readonly property bool cancellable: busy && vpn.busyKind === "connect"
    readonly property bool clickable: vpn.busyUuid === "" || cancellable

    hasCursor: root.cursorActive && root.focusSection === "vpns" && root.vpnIndex === rowIndex
    foreground: root.barForeground
    current: active
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: rowInner.implicitHeight + Style.spacing.xl

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: vpnRow.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
      enabled: vpnRow.clickable
      onEntered: root.setVpnCursor(vpnRow.rowIndex)
      onClicked: {
        vpn.toggle(vpnRow.vpnUuid)
        root.close()
      }
    }

    Row {
      id: rowInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: vpnRow.active ? root.connectedIcon : root.disconnectedIcon
        color: vpnRow.active ? root.barForeground : root.dim
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: vpnRow.vpnName
        color: root.barForeground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        font.bold: vpnRow.active
        elide: Text.ElideRight
        width: parent.width - Style.space(22) - Style.space(90) - 2 * parent.spacing
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: vpnRow.cancellable || (!vpnRow.busy && vpnRow.activating) ? strings.t("row.cancel")
          : vpnRow.busy ? strings.t("row.disconnecting")
          : strings.t(vpnRow.active ? "row.disconnect" : "row.connect")
        color: root.dim
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.caption
        width: Style.space(90)
        horizontalAlignment: Text.AlignRight
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  component EditorRow: CursorSurface {
    id: editorRow
    hasCursor: root.cursorActive && root.focusSection === "editor" && vpn.editorAvailable
    foreground: root.barForeground
    fill: root.hoverFill
    implicitHeight: editorInner.implicitHeight + Style.spacing.xl

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      enabled: vpn.editorAvailable
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setEditorCursor()
      onClicked: { vpn.openEditor(); root.close() }
    }

    Row {
      id: editorInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: ""
        color: root.barForeground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }

      Text {
        textFormat: Text.PlainText
        text: strings.t(vpn.editorAvailable ? "editor.open" : "editor.missing")
        color: vpn.editorAvailable ? root.barForeground : root.dim
        width: parent.width - Style.space(30)
        wrapMode: Text.WordWrap
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }
    }
  }
}
