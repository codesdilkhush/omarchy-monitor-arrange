import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "codesdilkhush.monitor-arrange"
  ipcTarget: "codesdilkhush.monitor-arrange"
  manageIpc: false

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property bool vertical: root.bar ? root.bar.vertical : false
  readonly property color foreground: root.barForeground
  readonly property color accentColor: Commons.Color.accent
  readonly property color urgentColor: root.bar ? root.bar.urgent : Commons.Color.urgent
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  ShellIpc {
    target: "codesdilkhush.monitor-arrange"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  property var monitors: []
  property int selectedIndex: 0
  readonly property var selectedMonitor: monitors.length > selectedIndex && selectedIndex >= 0 ? monitors[selectedIndex] : null
  property string statusMessage: ""
  property real canvasScale: 0.055

  function parseStatus(raw) {
    try {
      var data = JSON.parse(raw)
      if (Array.isArray(data)) {
        monitors = data
        if (selectedIndex >= monitors.length) selectedIndex = 0
      }
    } catch (e) {
      // ignore parse error
    }
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  function setBrightness(name, pct) {
    if (brightnessProc.running) return
    brightnessProc.command = [
      String(Qt.resolvedUrl("backend.py")).replace(/^file:\/\//, ""),
      "set-brightness",
      name,
      String(Math.round(pct))
    ]
    brightnessProc.running = true
  }

  function applyLayout() {
    if (applyProc.running) return
    applyProc.command = [
      String(Qt.resolvedUrl("backend.py")).replace(/^file:\/\//, ""),
      "apply",
      JSON.stringify(monitors)
    ]
    applyProc.running = true
    statusMessage = strings.t("display.applied")
    clearStatusTimer.restart()
  }

  function saveLayout() {
    if (saveProc.running) return
    saveProc.command = [
      String(Qt.resolvedUrl("backend.py")).replace(/^file:\/\//, ""),
      "save",
      JSON.stringify(monitors)
    ]
    saveProc.running = true
    statusMessage = strings.t("display.saved")
    clearStatusTimer.restart()
  }

  function swapHorizontal() {
    if (monitors.length < 2) return
    var copy = JSON.parse(JSON.stringify(monitors))
    if (copy[0].x === 0 && copy[1].x > 0) {
      // Move screen 0 to the right of screen 1
      copy[1].x = 0
      copy[0].x = Math.round(copy[1].width / copy[1].scale)
    } else {
      // Move screen 1 to the right of screen 0
      copy[0].x = 0
      copy[1].x = Math.round(copy[0].width / copy[0].scale)
    }
    monitors = copy
  }

  function swapVertical() {
    if (monitors.length < 2) return
    var copy = JSON.parse(JSON.stringify(monitors))
    if (copy[0].y === 0 && copy[1].y > 0) {
      copy[1].y = 0
      copy[0].y = Math.round(copy[1].height / copy[1].scale)
    } else {
      copy[0].y = 0
      copy[1].y = Math.round(copy[0].height / copy[0].scale)
    }
    monitors = copy
  }

  function setScale(scaleVal) {
    if (!selectedMonitor) return
    var copy = JSON.parse(JSON.stringify(monitors))
    copy[selectedIndex].scale = scaleVal
    monitors = copy
  }

  function setTransform(transVal) {
    if (!selectedMonitor) return
    var copy = JSON.parse(JSON.stringify(monitors))
    copy[selectedIndex].transform = transVal
    monitors = copy
  }

  function cycleMode(delta) {
    if (!selectedMonitor || !selectedMonitor.availableModes || selectedMonitor.availableModes.length === 0) return
    var modes = selectedMonitor.availableModes
    var currentStr = selectedMonitor.width + "x" + selectedMonitor.height + "@" + selectedMonitor.refreshRate.toFixed(2)
    var idx = 0
    for (var i = 0; i < modes.length; i++) {
      if (modes[i].indexOf(selectedMonitor.width + "x" + selectedMonitor.height) === 0) {
        idx = i
        break
      }
    }
    var nextIdx = (idx + delta + modes.length) % modes.length
    var modeStr = modes[nextIdx] // format: 2560x1440@59.95
    var parts = modeStr.split("@")
    if (parts.length === 2) {
      var wh = parts[0].split("x")
      var copy = JSON.parse(JSON.stringify(monitors))
      copy[selectedIndex].width = parseInt(wh[0])
      copy[selectedIndex].height = parseInt(wh[1])
      copy[selectedIndex].refreshRate = parseFloat(parts[1])
      monitors = copy
    }
  }

  onOpenedChanged: {
    if (opened) {
      statusMessage = ""
      refresh()
    }
  }

  Timer {
    id: clearStatusTimer
    interval: 3500
    onTriggered: root.statusMessage = ""
  }

  Process {
    id: statusProc
    command: [String(Qt.resolvedUrl("backend.py")).replace(/^file:\/\//, ""), "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseStatus(text)
    }
  }

  Process { id: brightnessProc }
  Process { id: applyProc }
  Process { id: saveProc }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf108"
    slotSize: Style.bar.iconSlot
    tooltipText: strings.t("display.tooltip")
    active: root.opened
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(450))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      implicitHeight: contentColumn.implicitHeight
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // Hero Header
        Row {
          width: parent.width
          spacing: Style.space(12)

          Text {
            textFormat: Text.PlainText
            text: "\uf108"
            color: root.accentColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: strings.t("display.title")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              textFormat: Text.PlainText
              text: strings.t("display.subtitle")
              color: root.foreground
              opacity: 0.65
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        // Interactive Arrangement Canvas
        Rectangle {
          id: canvas
          width: parent.width
          height: Style.space(145)
          radius: Style.cornerRadius > 0 ? Style.cornerRadius : 8
          color: Qt.rgba(0, 0, 0, 0.22)
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
          border.width: 1
          clip: true

          // Center positioning offsets
          readonly property real originX: Style.space(35)
          readonly property real originY: Style.space(25)

          Repeater {
            model: root.monitors

            Item {
              id: monitorCard
              required property var modelData
              required property int index

              readonly property bool isSelected: root.selectedIndex === index
              readonly property real w: Math.max(Style.space(80), modelData.width * root.canvasScale)
              readonly property real h: Math.max(Style.space(50), modelData.height * root.canvasScale)

              x: canvas.originX + (modelData.x * root.canvasScale)
              y: canvas.originY + (modelData.y * root.canvasScale)
              width: w
              height: h

              Rectangle {
                anchors.fill: parent
                radius: 6
                color: monitorCard.isSelected ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.2) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08)
                border.color: monitorCard.isSelected ? root.accentColor : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.3)
                border.width: monitorCard.isSelected ? 2 : 1

                Behavior on color { ColorAnimation { duration: Style.duration(180) } }
                Behavior on border.color { ColorAnimation { duration: Style.duration(180) } }

                Column {
                  anchors.centerIn: parent
                  spacing: Style.space(2)

                  Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Style.space(4)

                    Text {
                      textFormat: Text.PlainText
                      text: modelData.name || ""
                      color: monitorCard.isSelected ? root.accentColor : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.bold: true
                    }

                    Text {
                      textFormat: Text.PlainText
                      visible: modelData.isInternal
                      text: "★"
                      color: root.accentColor
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: modelData.width + "x" + modelData.height
                    color: root.foreground
                    opacity: 0.75
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.horizontalCenter: parent.horizontalCenter
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: modelData.scale + "x · " + modelData.refreshRate.toFixed(0) + "Hz"
                    color: root.foreground
                    opacity: 0.55
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    anchors.horizontalCenter: parent.horizontalCenter
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectedIndex = index
              }
            }
          }

          // Canvas Arrangement Helpers (Swap Left/Right, Swap Top/Bottom)
          Row {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.margins: Style.space(8)
            spacing: Style.space(6)

            Button {
              text: "⇄ Swap Sides"
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.swapHorizontal()
            }

            Button {
              text: "⇅ Stack"
              fontSize: Style.font.caption
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.swapVertical()
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        // Selected Monitor Settings Panel
        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.selectedMonitor !== null

          // Monitor Info Line
          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              text: (root.selectedMonitor ? root.selectedMonitor.name : "") + " (" + (root.selectedMonitor ? root.selectedMonitor.description : "") + ")"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
              width: Style.space(310)
            }

            Item {
              width: Math.max(0, parent.width - Style.space(310) - tagBadge.implicitWidth)
              height: 1
            }

            Rectangle {
              id: tagBadge
              height: Style.space(18)
              width: tagText.implicitWidth + Style.space(10)
              radius: 4
              color: Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.15)

              Text {
                id: tagText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: root.selectedMonitor && root.selectedMonitor.isInternal ? strings.t("display.internal") : strings.t("display.external")
                color: root.accentColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }
          }

          // Hardware Brightness Slider
          Column {
            width: parent.width
            spacing: Style.space(4)

            Row {
              width: parent.width
              Text {
                textFormat: Text.PlainText
                text: strings.t("display.brightness")
                color: root.foreground
                opacity: 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              Item {
                width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth)
                height: 1
              }
              Text {
                textFormat: Text.PlainText
                text: (root.selectedMonitor ? root.selectedMonitor.brightness : 100) + "%"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }
            }

            Rectangle {
              id: bSliderTrack
              width: parent.width
              height: Style.space(18)
              radius: height / 2
              color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

              Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height
                radius: parent.radius
                color: root.accentColor
                width: Math.max(parent.height, parent.width * ((root.selectedMonitor ? root.selectedMonitor.brightness : 100) / 100.0))

                Behavior on width { NumberAnimation { duration: Style.duration(80) } }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: function(mouse) {
                  if (pressed && root.selectedMonitor) {
                    var pct = Math.max(1, Math.min(100, Math.round((mouse.x / width) * 100)))
                    root.selectedMonitor.brightness = pct
                    root.setBrightness(root.selectedMonitor.name, pct)
                  }
                }
                onPressed: function(mouse) {
                  if (root.selectedMonitor) {
                    var pct = Math.max(1, Math.min(100, Math.round((mouse.x / width) * 100)))
                    root.selectedMonitor.brightness = pct
                    root.setBrightness(root.selectedMonitor.name, pct)
                  }
                }
              }
            }
          }

          // Resolution & Refresh Rate Mode Selector
          Row {
            width: parent.width
            spacing: Style.space(8)

            Column {
              width: Style.space(260)
              spacing: Style.space(2)

              Text {
                textFormat: Text.PlainText
                text: strings.t("display.mode")
                color: root.foreground
                opacity: 0.7
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Text {
                textFormat: Text.PlainText
                text: root.selectedMonitor ? (root.selectedMonitor.width + "x" + root.selectedMonitor.height + " @ " + root.selectedMonitor.refreshRate.toFixed(2) + "Hz") : ""
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }

            Row {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              Button {
                text: "◀ Prev"
                fontSize: Style.font.caption
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                onClicked: root.cycleMode(-1)
              }

              Button {
                text: "Next ▶"
                fontSize: Style.font.caption
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                onClicked: root.cycleMode(1)
              }
            }
          }

          // Scale Selector Row
          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              text: strings.t("display.scale") + ":"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(60)
            }

            Row {
              spacing: Style.space(6)
              Repeater {
                model: [1.0, 1.25, 1.5, 1.75, 2.0]
                Button {
                  required property var modelData
                  text: (modelData * 100) + "%"
                  fontSize: Style.font.caption
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  bordered: true
                  active: root.selectedMonitor && Math.abs(root.selectedMonitor.scale - modelData) < 0.05
                  onClicked: root.setScale(modelData)
                }
              }
            }
          }

          // Orientation Row
          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              text: strings.t("display.orientation") + ":"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(60)
            }

            Row {
              spacing: Style.space(6)

              Button {
                text: "0° Landscape"
                fontSize: Style.font.caption
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                active: root.selectedMonitor && root.selectedMonitor.transform === 0
                onClicked: root.setTransform(0)
              }

              Button {
                text: "90° Portrait"
                fontSize: Style.font.caption
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                active: root.selectedMonitor && root.selectedMonitor.transform === 1
                onClicked: root.setTransform(1)
              }

              Button {
                text: "180° Inverted"
                fontSize: Style.font.caption
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                active: root.selectedMonitor && root.selectedMonitor.transform === 2
                onClicked: root.setTransform(2)
              }
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        // Action Buttons Row & Status Label
        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            text: strings.t("display.apply")
            iconText: "\uf00c"
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            onClicked: root.applyLayout()
          }

          Button {
            text: strings.t("display.save")
            iconText: "\uf0c7"
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            onClicked: root.saveLayout()
          }

          Text {
            textFormat: Text.PlainText
            text: root.statusMessage
            color: root.accentColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }
        }
      }
    }
  }
}
