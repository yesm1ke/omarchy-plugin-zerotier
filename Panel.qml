import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.michallote.zerotier"
  ipcTarget: "io.github.michallote.zerotier"
  manageIpc: false

  property string focusSection: "header"
  property int networkIndex: 0
  property int memberIndex: 0
  property int peerIndex: 0
  property bool cursorActive: false
  property bool copyMenuOpen: false
  property bool joinEditing: false
  property bool centralEditing: false
  property bool joinOpen: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color barIconColor: zt.active ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property color iconColor: zt.active ? foreground : dim
  readonly property color hoverFill: bar ? Style.hoverFillFor(bar.foreground, Color.accent) : "transparent"
  readonly property color selectedFill: bar ? Style.selectedFillFor(bar.foreground, Color.accent) : "transparent"

  readonly property bool showNetworks: zt.installed && zt.networks.length > 0
  readonly property bool showMembers: zt.installed && zt.members.length > 0
  // Local peers are only shown as a fallback when Central is not configured —
  // once we have the member list it is strictly more useful.
  readonly property bool showPeers: zt.installed && zt.active && zt.peers.length > 0 && !zt.centralConfigured
  readonly property string toggleHint: zt.active ? "Stop the ZeroTier service" : "Start the ZeroTier service"

  // Ordered list of scrollable sections currently on screen, each with its
  // index property name and item count. Navigation walks this generically.
  readonly property var navSections: {
    var out = []
    if (showNetworks) out.push({ name: "networks", count: zt.networks.length })
    if (showMembers) out.push({ name: "members", count: zt.members.length })
    if (showPeers) out.push({ name: "peers", count: zt.peers.length })
    return out
  }

  function sectionCount(name) {
    for (var i = 0; i < navSections.length; i++) if (navSections[i].name === name) return navSections[i].count
    return 0
  }
  function sectionIndex(name) {
    if (name === "networks") return networkIndex
    if (name === "members") return memberIndex
    if (name === "peers") return peerIndex
    return 0
  }
  function setSectionIndex(name, value) {
    if (name === "networks") networkIndex = value
    else if (name === "members") memberIndex = value
    else if (name === "peers") peerIndex = value
  }

  function selectedNetwork() {
    if (zt.networks.length === 0) return null
    return zt.networks[Math.max(0, Math.min(networkIndex, zt.networks.length - 1))]
  }

  function selectedMember() {
    if (zt.members.length === 0) return null
    return zt.members[Math.max(0, Math.min(memberIndex, zt.members.length - 1))]
  }

  function selectedPeer() {
    if (zt.peers.length === 0) return null
    return zt.peers[Math.max(0, Math.min(peerIndex, zt.peers.length - 1))]
  }

  function ensureCursor() {
    if (networkIndex >= zt.networks.length) networkIndex = Math.max(0, zt.networks.length - 1)
    if (memberIndex >= zt.members.length) memberIndex = Math.max(0, zt.members.length - 1)
    if (peerIndex >= zt.peers.length) peerIndex = Math.max(0, zt.peers.length - 1)
    if (focusSection !== "header" && sectionCount(focusSection) === 0)
      focusSection = navSections.length > 0 ? navSections[0].name : "header"
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) return
    if (focusSection === "header") {
      if (dy > 0 && navSections.length > 0) focusSection = navSections[0].name
      ensureCursor(); scrollCursorIntoView(); return
    }
    var pos = -1
    for (var i = 0; i < navSections.length; i++) if (navSections[i].name === focusSection) pos = i
    if (pos === -1) { ensureCursor(); return }
    var idx = sectionIndex(focusSection)
    if (dy < 0) {
      if (idx > 0) setSectionIndex(focusSection, idx - 1)
      else if (pos === 0) focusSection = "header"
      else { var prev = navSections[pos - 1]; focusSection = prev.name; setSectionIndex(prev.name, Math.max(0, prev.count - 1)) }
    } else {
      if (idx < navSections[pos].count - 1) setSectionIndex(focusSection, idx + 1)
      else if (pos < navSections.length - 1) { focusSection = navSections[pos + 1].name; setSectionIndex(navSections[pos + 1].name, 0) }
    }
    ensureCursor()
    scrollCursorIntoView()
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "header") zt.toggleService()
    else if (focusSection === "networks") openRowCopyMenu(networkColumn, networkIndex)
    else if (focusSection === "members") openRowCopyMenu(memberColumn, memberIndex)
    else if (focusSection === "peers") openRowCopyMenu(peerColumn, peerIndex)
  }

  function openRowCopyMenu(col, index) {
    if (!col || index < 0 || index >= col.children.length) return
    var item = col.children[index]
    if (item && item.openCopyMenu) item.openCopyMenu()
  }

  function setNetworkCursor(index) { cursorActive = true; focusSection = "networks"; networkIndex = index }
  function setMemberCursor(index) { cursorActive = true; focusSection = "members"; memberIndex = index }
  function setPeerCursor(index) { cursorActive = true; focusSection = "peers"; peerIndex = index }

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
    var col = focusSection === "networks" ? networkColumn
      : focusSection === "members" ? memberColumn
      : focusSection === "peers" ? peerColumn : null
    if (!col) return
    var idx = sectionIndex(focusSection)
    if (idx >= 0 && idx < col.children.length) scrollItemIntoView(col.children[idx])
  }

  function latencyLabel(ms) {
    if (typeof ms !== "number" || ms < 0) return ""
    return Math.round(ms) + " ms"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    joinEditing = false
    centralEditing = false
    joinOpen = false
    if (panelFlick) panelFlick.contentY = 0
    zt.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onNetworkIndexChanged: scrollCursorIntoView()
  onMemberIndexChanged: scrollCursorIntoView()
  onPeerIndexChanged: scrollCursorIntoView()
  onShowNetworksChanged: ensureCursor()
  onShowMembersChanged: ensureCursor()
  onShowPeersChanged: ensureCursor()

  Service {
    id: zt
    settings: root.settings
  }

  Connections {
    target: zt
    function onNetworksChanged2() { root.ensureCursor() }
    function onMembersChanged2() { root.ensureCursor() }
    function onPeersChanged2() { root.ensureCursor() }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { zt.refresh(); return "ok" }
    function up(): string { zt.startService(); return "ok" }
    function down(): string { zt.stopService(); return "ok" }
    function status(): string { return zt.statusText }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        ZeroTierIcon {
          anchors.centerIn: parent
          iconSize: Style.space(11)
          color: root.barIconColor
          badgeColor: root.urgent
          crossed: zt.installed && !zt.active
          warning: zt.tokenError || (zt.installed && zt.active && !zt.online)
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) zt.toggleService()
      else if (buttonCode === Qt.MiddleButton) zt.refresh()
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
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.copyMenuOpen || root.joinEditing || root.centralEditing
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "t" || t === "T") zt.toggleService()
        else if (t === "r" || t === "R") zt.refresh()
        else if (t === "c" || t === "C") {
          if (root.focusSection === "members") {
            var m = root.selectedMember()
            if (m) zt.copyToClipboard(m.ip4 || m.nodeId)
          } else if (root.focusSection === "peers") {
            var peer = root.selectedPeer()
            if (peer) zt.copyToClipboard(peer.endpoint || peer.address)
          } else {
            var net = root.selectedNetwork()
            if (net) zt.copyToClipboard(net.primaryIp || net.id)
          }
        }
      }

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

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            readonly property bool ringVisible: root.cursorActive && root.focusSection === "header" && zt.installed
            function focusHero() { root.cursorActive = true; root.focusSection = "header" }

            PanelHero {
              id: hero
              width: parent.width
              title: zt.installed && zt.nodeAddress !== "" ? (zt.localName !== "" ? zt.localName : zt.nodeAddress) : "ZeroTier"
              meta: !zt.installed ? "Not installed"
                : zt.tokenError ? "Auth token not readable"
                : zt.active ? ((zt.online ? "Online" + (zt.version ? " · v" + zt.version : "") : "Service up · node offline")
                  + (zt.localName !== "" && zt.nodeAddress !== "" ? " · " + zt.nodeAddress : ""))
                : "Service stopped"
              detail: {
                if (!zt.installed) return ""
                if (zt.members.length > 0) {
                  var on = 0
                  for (var i = 0; i < zt.members.length; i++) if (zt.members[i].online) on++
                  return on + "/" + zt.members.length + " online"
                }
                if (zt.networks.length > 0) return zt.networks.length + (zt.networks.length === 1 ? " network" : " networks")
                return ""
              }
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: zt.active ? 1.0 : 0.5
              iconComponent: Component {
                ZeroTierIcon {
                  iconSize: Style.font.display
                  color: root.iconColor
                  badgeColor: root.urgent
                  crossed: zt.installed && !zt.active
                  warning: zt.tokenError
                }
              }
              trailingControl: Component {
                ToggleSwitch {
                  id: powerSwitch
                  visible: zt.installed
                  checked: zt.active
                  busy: zt.busy
                  hasCursor: header.ringVisible
                  foreground: hero.foreground
                  onHovered: function(on) { if (on) header.focusHero() }
                  onToggled: zt.toggleService()

                  PanelToolTip {
                    visible: powerSwitch.containsMouse
                    text: root.toggleHint
                    fontFamily: hero.fontFamily
                  }
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: zt.actionStatus !== "" || zt.lastError !== ""
            width: parent.width
            text: zt.actionStatus !== "" ? zt.actionStatus : zt.lastError
            color: zt.lastError !== "" && zt.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          // Not installed — nothing the widget can do about that.
          CursorSurface {
            visible: !zt.installed
            width: parent.width
            implicitHeight: missingText.implicitHeight + Style.spacing.rowPaddingX
            foreground: root.foreground

            Text {
              id: missingText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.margins: Style.space(12)
              text: "zerotier-cli is not installed or not on PATH.\nInstall the zerotier-one package to use this widget."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          // Daemon token unreadable — one click runs the privileged copy
          // through polkit, no terminal needed.
          CursorSurface {
            id: authRow
            visible: zt.installed && zt.tokenError
            width: parent.width
            implicitHeight: authRowInner.implicitHeight + Style.spacing.rowPaddingX
            foreground: root.foreground
            hasCursor: authMouse.containsMouse && !zt.busy

            MouseArea {
              id: authMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: zt.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
              enabled: !zt.busy
              onClicked: zt.setupLocalAccess()
            }

            RowLayout {
              id: authRowInner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              spacing: Style.space(10)

              Text {
                text: "󰌆"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.heading
                Layout.alignment: Qt.AlignVCenter
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(1)

                Text {
                  Layout.fillWidth: true
                  text: "Authorize ZeroTier access"
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                Text {
                  Layout.fillWidth: true
                  text: "Copies the daemon API token so this widget can read it (asks for your password once)"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }
            }
          }

          // ---- Networks --------------------------------------------------
          PanelSeparator {
            visible: zt.installed && !zt.tokenError
            foreground: root.foreground
          }

          Column {
            visible: zt.installed && !zt.tokenError
            width: parent.width
            spacing: Style.space(10)

            RowLayout {
              width: parent.width
              spacing: Style.space(6)

              PanelSectionHeader {
                text: "NETWORKS"
                foreground: root.foreground
                fontFamily: root.fontFamily
                Layout.alignment: Qt.AlignVCenter
              }

              Item { Layout.fillWidth: true }

              PanelActionButton {
                iconText: root.joinOpen ? "󰅖" : "󰐕"
                tooltipText: root.joinOpen ? "Cancel" : "Join a network"
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                Layout.alignment: Qt.AlignVCenter
                onClicked: {
                  root.joinOpen = !root.joinOpen
                  if (root.joinOpen) Qt.callLater(function() { if (joinField) joinField.forceActiveFocus() })
                  else { joinField.text = ""; keyCatcher.forceActiveFocus() }
                }
              }
            }

            Text {
              visible: zt.networks.length === 0 && !root.joinOpen
              width: parent.width
              text: "You have not joined any ZeroTier networks."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: networkColumn
              visible: root.showNetworks
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: zt.networks
                NetworkRow {
                  required property var modelData
                  required property int index
                  width: networkColumn.width
                  network: modelData
                  rowIndex: index
                }
              }
            }

            // Join a network — revealed by the + button on the section header.
            BorderSurface {
              visible: root.joinOpen
              width: parent.width
              implicitHeight: joinRow.implicitHeight + Style.space(10)
              color: "transparent"
              borderSpec: Border.controlSpec(joinField.activeFocus ? "focus" : "normal", root.foreground, Color.accent)
              radius: Style.cornerRadius

              RowLayout {
                id: joinRow
                anchors.fill: parent
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(6)
                spacing: Style.space(8)

                TextField {
                  id: joinField
                  Layout.fillWidth: true
                  foreground: root.foreground
                  placeholderText: "Network ID — 16 hex characters"
                  onActiveFocusChanged: root.joinEditing = activeFocus
                  Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                      text = ""
                      root.joinOpen = false
                      keyCatcher.forceActiveFocus()
                      event.accepted = true
                    }
                  }
                  onAccepted: {
                    if (/^[0-9a-fA-F]{16}$/.test(text.trim())) {
                      zt.joinNetwork(text)
                      text = ""
                      root.joinOpen = false
                    }
                    keyCatcher.forceActiveFocus()
                  }
                }

                PanelActionButton {
                  iconText: "󰄾"
                  tooltipText: "Join network"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  enabled: /^[0-9a-fA-F]{16}$/.test(joinField.text.trim())
                  Layout.alignment: Qt.AlignVCenter
                  onClicked: {
                    zt.joinNetwork(joinField.text)
                    joinField.text = ""
                    root.joinOpen = false
                    keyCatcher.forceActiveFocus()
                  }
                }
              }
            }
          }

          // ---- Members (ZeroTier Central) -----------------------------
          PanelSeparator {
            visible: zt.installed && zt.active && !zt.tokenError
            foreground: root.foreground
          }

          Column {
            visible: zt.installed && zt.active && !zt.tokenError
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "MEMBERS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            // No token yet, or the saved one was rejected: let the user paste
            // one straight into the panel — the widget writes the file.
            Column {
              visible: !zt.centralConfigured || (zt.membersError !== "" && zt.members.length === 0)
              width: parent.width
              spacing: Style.space(6)

              Text {
                width: parent.width
                text: zt.membersError !== ""
                  ? zt.membersError + " — paste a valid token below."
                  : "Paste a ZeroTier Central API token to list members with their names and ZeroTier IPs. Create one at my.zerotier.com → Account → API Access."
                color: zt.membersError !== "" ? root.urgent : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }

              BorderSurface {
                width: parent.width
                implicitHeight: tokenRow.implicitHeight + Style.space(10)
                color: "transparent"
                borderSpec: Border.controlSpec(tokenField.activeFocus ? "focus" : "normal", root.foreground, Color.accent)
                radius: Style.cornerRadius

                RowLayout {
                  id: tokenRow
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(6)
                  spacing: Style.space(8)

                  TextField {
                    id: tokenField
                    Layout.fillWidth: true
                    foreground: root.foreground
                    password: true
                    placeholderText: "Paste API token"
                    onActiveFocusChanged: root.centralEditing = activeFocus
                    Keys.onPressed: function(event) {
                      if (event.key === Qt.Key_Escape) {
                        text = ""
                        keyCatcher.forceActiveFocus()
                        event.accepted = true
                      }
                    }
                    onAccepted: {
                      if (text.trim() !== "") { zt.saveCentralToken(text); text = "" }
                      keyCatcher.forceActiveFocus()
                    }
                  }

                  PanelActionButton {
                    iconText: "󰄾"
                    tooltipText: "Save token"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    enabled: tokenField.text.trim().length > 0 && !zt.savingCentralToken
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: {
                      zt.saveCentralToken(tokenField.text)
                      tokenField.text = ""
                      keyCatcher.forceActiveFocus()
                    }
                  }
                }
              }
            }

            Text {
              visible: zt.centralConfigured && zt.members.length === 0 && zt.membersError === "" && zt.membersLoading
              width: parent.width
              text: "Loading members…"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: memberColumn
              visible: root.showMembers
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: zt.members
                MemberRow {
                  required property var modelData
                  required property int index
                  width: memberColumn.width
                  member: modelData
                  rowIndex: index
                  multiNetwork: zt.networks.length > 1
                }
              }
            }
          }

          // ---- Peers (fallback when Central is not configured) --------
          PanelSeparator {
            visible: root.showPeers
            foreground: root.foreground
          }

          Column {
            visible: root.showPeers
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "PEERS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              id: peerColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: zt.peers
                PeerRow {
                  required property var modelData
                  required property int index
                  width: peerColumn.width
                  peer: modelData
                  rowIndex: index
                }
              }
            }
          }
        }
      }
    }
  }

  Timer {
    id: panelRefreshTimer
    interval: 8000
    running: root.opened
    repeat: true
    onTriggered: zt.refresh()
  }

  // ==== Network row =============================================================
  component NetworkRow: CursorSurface {
    id: networkRow
    property var network: null
    property int rowIndex: 0
    readonly property string netName: network ? String(network.displayName || "Unnamed network") : "Unnamed network"
    readonly property string netId: network ? String(network.id || "") : ""
    readonly property var netIps: network && network.assigned ? network.assigned : []
    readonly property string netIp4: network && network.ipv4 && network.ipv4.length > 0 ? String(network.ipv4[0]) : ""
    readonly property bool netOk: network && network.ok === true
    property int copyIndex: 0

    readonly property var copyOptions: {
      var options = []
      if (netId !== "") options.push({ kind: "id", label: netId })
      if (network && network.name && network.name !== "") options.push({ kind: "name", label: network.name })
      var ipv4 = network && network.ipv4 ? network.ipv4 : []
      for (var i = 0; i < ipv4.length; i++) options.push({ kind: "ip", label: String(ipv4[i]) })
      var ipv6 = network && network.ipv6 ? network.ipv6 : []
      for (var j = 0; j < ipv6.length; j++) options.push({ kind: "ip", label: String(ipv6[j]) })
      return options
    }

    hasCursor: root.cursorActive && root.focusSection === "networks" && root.networkIndex === rowIndex
    foreground: root.foreground
    implicitHeight: Math.max(netContent.implicitHeight, netCopyButton.implicitHeight) + Style.spacing.rowPaddingX

    function clampCopyIndex() { copyIndex = Math.max(0, Math.min(copyIndex, copyOptions.length - 1)) }
    function openCopyMenu() {
      if (copyOptions.length === 0) return
      clampCopyIndex()
      netCopyPopup.open()
    }
    function moveCopyCursor(delta) {
      if (copyOptions.length === 0) return
      copyIndex = Math.max(0, Math.min(copyOptions.length - 1, copyIndex + delta))
    }
    function copyCurrentOption() {
      clampCopyIndex()
      if (copyOptions.length === 0) return
      zt.copyToClipboard(copyOptions[copyIndex].label)
      netCopyPopup.close()
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      hoverEnabled: true
      onContainsMouseChanged: if (containsMouse) root.setNetworkCursor(networkRow.rowIndex)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Rectangle {
        width: Style.space(8)
        height: Style.space(8)
        radius: width / 2
        color: networkRow.netOk ? root.foreground : root.urgent
        opacity: networkRow.netOk ? 0.9 : 1.0
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: netContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: networkRow.netName
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: {
            var parts = []
            if (networkRow.netIp4 !== "") parts.push(networkRow.netIp4)
            else if (network && network.ipv6 && network.ipv6.length > 0) parts.push(String(network.ipv6[0]))
            if (!networkRow.netOk && network) parts.push(network.statusLabel)
            parts.push(networkRow.netId)
            return parts.join(" · ")
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        id: leaveButton
        iconText: "󰩹"
        tooltipText: "Leave network"
        foreground: root.foreground
        hoverColor: root.urgent
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: zt.leaveNetwork(networkRow.netId)
      }

      PanelActionButton {
        id: netCopyButton
        iconText: "󰆏"
        tooltipText: "Copy…"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: networkRow.copyOptions.length > 0
        Layout.alignment: Qt.AlignVCenter
        onClicked: networkRow.openCopyMenu()
      }

      Popup {
        id: netCopyPopup
        x: netCopyButton.x + netCopyButton.width - width
        y: netCopyButton.y + netCopyButton.height + Style.space(4)
        width: Style.space(300)
        padding: 0
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        function handleKey(event) {
          if (event.key === Qt.Key_Escape) { close(); event.accepted = true; return }
          if (event.key === Qt.Key_Down || event.text === "j") { networkRow.moveCopyCursor(1); event.accepted = true; return }
          if (event.key === Qt.Key_Up || event.text === "k") { networkRow.moveCopyCursor(-1); event.accepted = true; return }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            networkRow.copyCurrentOption(); event.accepted = true
          }
        }
        onOpenedChanged: {
          root.copyMenuOpen = opened
          if (opened) {
            networkRow.clampCopyIndex()
            Qt.callLater(function() { netCopyPopupContent.forceActiveFocus() })
          } else if (root.opened) {
            Qt.callLater(function() { keyCatcher.forceActiveFocus() })
          }
        }
        background: BorderSurface {
          color: Color.popups.background
          borderSpec: Border.flat(root.dim, 1)
          radius: Style.cornerRadius
        }
        contentItem: Column {
          id: netCopyPopupContent
          width: parent.width
          focus: true
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) { netCopyPopup.handleKey(event) }

          Repeater {
            model: networkRow.copyOptions
            CopyChoice {
              required property var modelData
              required property int index
              width: parent.width
              label: String(modelData.label || "")
              selected: networkRow.copyIndex === index
              onHovered: networkRow.copyIndex = index
              onChosen: { zt.copyToClipboard(String(modelData.label || "")); netCopyPopup.close() }
            }
          }
        }
      }
    }
  }

  // ==== Peer row ===============================================================
  component PeerRow: CursorSurface {
    id: peerRow
    property var peer: null
    property int rowIndex: 0
    readonly property string addr: peer ? String(peer.address || "") : ""
    readonly property string endpoint: peer ? String(peer.endpoint || "") : ""
    property int copyIndex: 0

    readonly property var copyOptions: {
      var options = []
      if (addr !== "") options.push({ kind: "addr", label: addr })
      if (endpoint !== "") options.push({ kind: "endpoint", label: endpoint })
      return options
    }

    hasCursor: root.cursorActive && root.focusSection === "peers" && root.peerIndex === rowIndex
    foreground: root.foreground
    implicitHeight: Math.max(peerContent.implicitHeight, peerCopyButton.implicitHeight) + Style.spacing.rowPaddingX

    function clampCopyIndex() { copyIndex = Math.max(0, Math.min(copyIndex, copyOptions.length - 1)) }
    function openCopyMenu() {
      if (copyOptions.length === 0) return
      clampCopyIndex()
      peerCopyPopup.open()
    }
    function moveCopyCursor(delta) {
      if (copyOptions.length === 0) return
      copyIndex = Math.max(0, Math.min(copyOptions.length - 1, copyIndex + delta))
    }
    function copyCurrentOption() {
      clampCopyIndex()
      if (copyOptions.length === 0) return
      zt.copyToClipboard(copyOptions[copyIndex].label)
      peerCopyPopup.close()
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      hoverEnabled: true
      onContainsMouseChanged: if (containsMouse) root.setPeerCursor(peerRow.rowIndex)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Rectangle {
        width: Style.space(8)
        height: Style.space(8)
        radius: width / 2
        color: peerRow.peer && peerRow.peer.direct ? root.foreground : root.dim
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: peerContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: peerRow.addr
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: {
            if (!peerRow.peer) return ""
            var parts = []
            parts.push(peerRow.peer.direct ? "Direct" : "Relayed")
            if (peerRow.endpoint !== "") parts.push(peerRow.endpoint)
            var lat = root.latencyLabel(peerRow.peer.latency)
            if (lat !== "") parts.push(lat)
            if (peerRow.peer.version !== "") parts.push("v" + peerRow.peer.version)
            return parts.join(" · ")
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        id: peerCopyButton
        iconText: "󰆏"
        tooltipText: "Copy…"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: peerRow.copyOptions.length > 0
        Layout.alignment: Qt.AlignVCenter
        onClicked: peerRow.openCopyMenu()
      }

      Popup {
        id: peerCopyPopup
        x: peerCopyButton.x + peerCopyButton.width - width
        y: peerCopyButton.y + peerCopyButton.height + Style.space(4)
        width: Style.space(300)
        padding: 0
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        function handleKey(event) {
          if (event.key === Qt.Key_Escape) { close(); event.accepted = true; return }
          if (event.key === Qt.Key_Down || event.text === "j") { peerRow.moveCopyCursor(1); event.accepted = true; return }
          if (event.key === Qt.Key_Up || event.text === "k") { peerRow.moveCopyCursor(-1); event.accepted = true; return }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            peerRow.copyCurrentOption(); event.accepted = true
          }
        }
        onOpenedChanged: {
          root.copyMenuOpen = opened
          if (opened) {
            peerRow.clampCopyIndex()
            Qt.callLater(function() { peerCopyPopupContent.forceActiveFocus() })
          } else if (root.opened) {
            Qt.callLater(function() { keyCatcher.forceActiveFocus() })
          }
        }
        background: BorderSurface {
          color: Color.popups.background
          borderSpec: Border.flat(root.dim, 1)
          radius: Style.cornerRadius
        }
        contentItem: Column {
          id: peerCopyPopupContent
          width: parent.width
          focus: true
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) { peerCopyPopup.handleKey(event) }

          Repeater {
            model: peerRow.copyOptions
            CopyChoice {
              required property var modelData
              required property int index
              width: parent.width
              label: String(modelData.label || "")
              selected: peerRow.copyIndex === index
              onHovered: peerRow.copyIndex = index
              onChosen: { zt.copyToClipboard(String(modelData.label || "")); peerCopyPopup.close() }
            }
          }
        }
      }
    }
  }

  // ==== Member row (ZeroTier Central) =========================================
  component MemberRow: CursorSurface {
    id: memberRow
    property var member: null
    property int rowIndex: 0
    property bool multiNetwork: false
    property int copyIndex: 0
    readonly property string mName: member ? String(member.displayName || member.nodeId || "Unknown") : "Unknown"
    readonly property string mNode: member ? String(member.nodeId || "") : ""
    readonly property string mIp4: member ? String(member.ip4 || "") : ""
    readonly property var mIps: member && member.ips ? member.ips : []
    readonly property bool mOnline: member && member.online === true
    readonly property bool mAuthorized: member && member.authorized === true

    readonly property var copyOptions: {
      var options = []
      if (member && member.name && member.name !== "") options.push(member.name)
      for (var i = 0; i < mIps.length; i++) options.push(String(mIps[i]))
      if (mNode !== "") options.push(mNode)
      if (member && member.physicalAddress && member.physicalAddress !== "") options.push(String(member.physicalAddress))
      return options
    }

    hasCursor: root.cursorActive && root.focusSection === "members" && root.memberIndex === rowIndex
    foreground: root.foreground
    implicitHeight: Math.max(memberContent.implicitHeight, memberCopyButton.implicitHeight) + Style.spacing.rowPaddingX

    function clampCopyIndex() { copyIndex = Math.max(0, Math.min(copyIndex, copyOptions.length - 1)) }
    function openCopyMenu() {
      if (copyOptions.length === 0) return
      clampCopyIndex()
      memberCopyPopup.open()
    }
    function moveCopyCursor(delta) {
      if (copyOptions.length === 0) return
      copyIndex = Math.max(0, Math.min(copyOptions.length - 1, copyIndex + delta))
    }
    function copyCurrentOption() {
      clampCopyIndex()
      if (copyOptions.length === 0) return
      zt.copyToClipboard(copyOptions[copyIndex])
      memberCopyPopup.close()
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      hoverEnabled: true
      onContainsMouseChanged: if (containsMouse) root.setMemberCursor(memberRow.rowIndex)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Rectangle {
        width: Style.space(8)
        height: Style.space(8)
        radius: width / 2
        color: !memberRow.mAuthorized ? root.urgent : (memberRow.mOnline ? root.foreground : root.dim)
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        id: memberContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: memberRow.mName
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: memberRow.mOnline
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: {
            if (!memberRow.member) return ""
            var parts = []
            if (memberRow.mIp4 !== "") parts.push(memberRow.mIp4)
            parts.push(memberRow.mNode)
            if (!memberRow.mAuthorized) parts.push("not authorized")
            else if (!memberRow.mOnline) {
              var ago = Model.agoLabel(memberRow.member.lastOnline)
              parts.push(ago !== "" ? ago : "offline")
            }
            if (memberRow.member.version !== "") parts.push("v" + memberRow.member.version)
            if (memberRow.multiNetwork && memberRow.member.networkName !== "") parts.push(memberRow.member.networkName)
            return parts.join(" · ")
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        id: memberCopyButton
        iconText: "󰆏"
        tooltipText: "Copy…"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: memberRow.copyOptions.length > 0
        Layout.alignment: Qt.AlignVCenter
        onClicked: memberRow.openCopyMenu()
      }

      Popup {
        id: memberCopyPopup
        x: memberCopyButton.x + memberCopyButton.width - width
        y: memberCopyButton.y + memberCopyButton.height + Style.space(4)
        width: Style.space(300)
        padding: 0
        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        function handleKey(event) {
          if (event.key === Qt.Key_Escape) { close(); event.accepted = true; return }
          if (event.key === Qt.Key_Down || event.text === "j") { memberRow.moveCopyCursor(1); event.accepted = true; return }
          if (event.key === Qt.Key_Up || event.text === "k") { memberRow.moveCopyCursor(-1); event.accepted = true; return }
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            memberRow.copyCurrentOption(); event.accepted = true
          }
        }
        onOpenedChanged: {
          root.copyMenuOpen = opened
          if (opened) {
            memberRow.clampCopyIndex()
            Qt.callLater(function() { memberCopyPopupContent.forceActiveFocus() })
          } else if (root.opened) {
            Qt.callLater(function() { keyCatcher.forceActiveFocus() })
          }
        }
        background: BorderSurface {
          color: Color.popups.background
          borderSpec: Border.flat(root.dim, 1)
          radius: Style.cornerRadius
        }
        contentItem: Column {
          id: memberCopyPopupContent
          width: parent.width
          focus: true
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) { memberCopyPopup.handleKey(event) }

          Repeater {
            model: memberRow.copyOptions
            CopyChoice {
              required property var modelData
              required property int index
              width: parent.width
              label: String(modelData || "")
              selected: memberRow.copyIndex === index
              onHovered: memberRow.copyIndex = index
              onChosen: { zt.copyToClipboard(String(modelData || "")); memberCopyPopup.close() }
            }
          }
        }
      }
    }
  }

  // ==== Shared copy-menu choice ===============================================
  component CopyChoice: CursorSurface {
    id: copyChoice
    signal chosen()
    signal hovered()
    property string label: ""
    property bool selected: false

    visible: enabled
    foreground: root.foreground
    hasCursor: selected
    implicitHeight: Style.space(44)
    radius: 0

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: copyChoice.hovered()
      onClicked: copyChoice.chosen()
    }

    RowLayout {
      anchors.fill: parent
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(10)

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: copyChoice.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        text: "󰆏"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }
}
