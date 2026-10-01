import QtQuick

// Makes a bar widget hide together with the system tray drawer.
//
// omarchy.tray only hosts application status icons, so a bar widget cannot be
// put inside its drawer. This helper makes a widget follow the drawer from
// the outside instead: `reveal` animates 0..1 with the same timing as the
// tray's own drawer, and the widget multiplies its bar extent by it.
//
//   TrayFollower { id: follower; extraHold: root.opened }
//   property alias trayFollower: follower          // lets siblings find it
//   implicitWidth: Math.round(naturalWidth * follower.reveal)
//
// This file is copied verbatim into every plugin that uses it
// (omarchy-plugin-zerotier, -tailscale, -bluetooth) so each plugin installs
// on its own; keep the copies identical.
//
// The widget (and any other follower) must sit right after the tray in the
// layout: io.github.yesm1ke.tray (recommended) or the stock omarchy.tray.
// While the pointer is on any follower, or `extraHold` is set (e.g. its panel
// is open), the whole group — tray drawer included — stays open.
//
// This reaches into bar internals: ModuleSlot.moduleName / activeItem /
// hovered and Tray.expanded. If any of them is missing after an Omarchy
// update, `usable` turns false and the widget simply stays visible.
Item {
  id: follower

  property Item widget: parent
  property bool active: true
  property bool extraHold: false

  // The ModuleSlot that hosts the widget (widget -> Loader -> ModuleSlot).
  readonly property var slot: {
    var p = widget ? widget.parent : null
    for (var i = 0; i < 4 && p; i++) {
      if (p.moduleName !== undefined && p.activeItem !== undefined) return p
      p = p.parent
    }
    return null
  }
  readonly property var siblings: slot && slot.parent ? slot.parent.children : []
  // io.github.yesm1ke.tray wraps the stock tray and keeps its chevron while
  // the tray is empty; with plain omarchy.tray an empty tray hides itself and
  // the widget then stays visible (see `usable`).
  readonly property var trayIds: ["io.github.yesm1ke.tray", "omarchy.tray"]
  readonly property var traySlot: {
    for (var i = 0; i < siblings.length; i++)
      if (siblings[i] && trayIds.indexOf(siblings[i].moduleName) !== -1) return siblings[i]
    return null
  }
  readonly property var tray: traySlot ? traySlot.activeItem : null
  readonly property bool usable: active && tray !== null && tray !== undefined
    && tray.visible === true && tray.expanded !== undefined

  readonly property bool selfHold: (slot ? slot.hovered === true : false) || extraHold
  readonly property bool groupHold: {
    if (selfHold) return true
    for (var i = 0; i < siblings.length; i++) {
      var item = siblings[i] ? siblings[i].activeItem : null
      var other = item ? item.trayFollower : null
      if (other && other !== follower && other.selfHold === true) return true
    }
    return false
  }
  readonly property bool shown: !usable || tray.expanded === true || groupHold || linger.running

  // Same duration and easing as the tray drawer's own reveal.
  property real reveal: shown ? 1 : 0
  Behavior on reveal {
    NumberAnimation { duration: 600; easing.type: Easing.OutCubic }
  }

  onGroupHoldChanged: {
    if (!usable) return
    if (groupHold) {
      linger.stop()
      tray.expanded = true
    } else {
      linger.restart()
    }
  }

  // The tray closes its drawer as soon as the pointer leaves its own area;
  // reopen it while a follower is holding the group open.
  Connections {
    target: follower.usable ? follower.tray : null
    function onExpandedChanged() {
      if (follower.tray && follower.tray.expanded !== true && follower.groupHold) follower.tray.expanded = true
    }
  }

  // Released: hand the drawer back to the tray's own hover state.
  Timer {
    id: linger
    interval: 200
    repeat: false
    onTriggered: {
      if (!follower.usable || follower.groupHold) return
      follower.tray.expanded = follower.traySlot ? follower.traySlot.hovered === true : false
    }
  }
}
