import QtQuick
import qs.Commons
import qs.Ui

// Native rendering of the ZeroTier mark: a rounded hexagon with a centre dot,
// stroked in the theme foreground. Canvas keeps it crisp in tiny bar slots
// where a scaled-down SVG would smear.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property color badgeColor: Color.urgent
  property bool crossed: false
  property bool warning: false

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Canvas {
    id: canvas
    anchors.fill: parent
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var w = width
      var h = height
      var cx = w / 2
      var cy = h / 2
      var r = Math.min(w, h) / 2 - Math.max(1, w * 0.08)
      var stroke = Math.max(1.4, w * 0.11)

      ctx.strokeStyle = root.color
      ctx.fillStyle = root.color
      ctx.lineJoin = "round"
      ctx.lineWidth = stroke

      // Pointy-top hexagon.
      ctx.beginPath()
      for (var i = 0; i < 6; i++) {
        var a = Math.PI / 180 * (60 * i - 90)
        var px = cx + r * Math.cos(a)
        var py = cy + r * Math.sin(a)
        if (i === 0) ctx.moveTo(px, py)
        else ctx.lineTo(px, py)
      }
      ctx.closePath()
      ctx.stroke()

      // Centre dot.
      ctx.beginPath()
      ctx.arc(cx, cy, Math.max(1.4, w * 0.16), 0, Math.PI * 2)
      ctx.fill()
    }

    Connections {
      target: root
      function onColorChanged() { canvas.requestPaint() }
    }
  }

  Rectangle {
    visible: root.crossed
    anchors.centerIn: parent
    width: parent.width * 1.22
    height: Math.max(2, parent.height * 0.14)
    radius: height / 2
    color: root.color
    rotation: -45
  }

  BorderSurface {
    visible: root.warning
    width: Math.max(7, parent.width * 0.42)
    height: width
    radius: width / 2
    color: root.badgeColor
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    borderSpec: Border.flat(Color.popups.background, 1)

    Text {
      anchors.centerIn: parent
      text: "!"
      color: Color.background
      font.family: Style.font.family
      font.pixelSize: Math.max(6, parent.height * 0.72)
      font.bold: true
    }
  }
}
