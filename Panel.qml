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

  property var monitors: []
  property int selectedIndex: 0
  readonly property var selectedMonitor: monitors.length > selectedIndex && selectedIndex >= 0 ? monitors[selectedIndex] : null

  property int liveBrightness: selectedMonitor ? selectedMonitor.brightness : 100
  onSelectedMonitorChanged: {
    if (selectedMonitor) liveBrightness = selectedMonitor.brightness
  }

  property string statusMessage: ""
  property real canvasScale: 0.052

  readonly property real groupBoundsMinX: {
    if (monitors.length === 0) return 0
    var m = monitors[0].x
    for (var i = 1; i < monitors.length; i++) m = Math.min(m, monitors[i].x)
    return m
  }
  readonly property real groupBoundsMaxX: {
    if (monitors.length === 0) return 1920
    var m = monitors[0].x + monitors[0].width
    for (var i = 1; i < monitors.length; i++) m = Math.max(m, monitors[i].x + monitors[i].width)
    return m
  }
  readonly property real groupBoundsMinY: {
    if (monitors.length === 0) return 0
    var m = monitors[0].y
    for (var i = 1; i < monitors.length; i++) m = Math.min(m, monitors[i].y)
    return m
  }
  readonly property real groupBoundsMaxY: {
    if (monitors.length === 0) return 1080
    var m = monitors[0].y + monitors[0].height
    for (var i = 1; i < monitors.length; i++) m = Math.max(m, monitors[i].y + monitors[i].height)
    return m
  }
  property real canvasWidth: Style.space(450)
  property real canvasHeight: Style.space(155)
  readonly property real canvasOffsetX: Math.max(Style.space(20), (canvasWidth - (groupBoundsMaxX - groupBoundsMinX) * canvasScale) / 2)
  readonly property real canvasOffsetY: Math.max(Style.space(18), (canvasHeight - (groupBoundsMaxY - groupBoundsMinY) * canvasScale) / 2)

  readonly property var resolutionOptions: {
    if (!selectedMonitor || !selectedMonitor.availableModes) return []
    var list = []
    var seen = {}
    for (var i = 0; i < selectedMonitor.availableModes.length; i++) {
      var parts = selectedMonitor.availableModes[i].split("@")
      var res = parts[0]
      if (!seen[res]) {
        seen[res] = true
        var wh = res.split("x")
        list.push({
          value: res,
          label: wh[0] + " × " + wh[1]
        })
      }
    }
    return list
  }

  readonly property string currentResolutionValue: {
    if (!selectedMonitor) return ""
    return selectedMonitor.width + "x" + selectedMonitor.height
  }

  function getAvailableRatesForResolution(m, resStr) {
    if (!m || !m.availableModes) return []
    var list = []
    var seen = {}
    var prefix = resStr + "@"
    for (var i = 0; i < m.availableModes.length; i++) {
      var mode = m.availableModes[i]
      if (mode.indexOf(prefix) === 0) {
        var hzStr = mode.substring(prefix.length)
        var hzNum = parseFloat(hzStr)
        if (!seen[hzStr]) {
          seen[hzStr] = true
          var cleanLabel = (hzNum % 1 === 0 ? hzNum.toFixed(0) : hzNum.toFixed(2)) + " Hz"
          list.push({
            value: hzStr,
            label: cleanLabel
          })
        }
      }
    }
    return list
  }

  readonly property var rateOptions: {
    if (!selectedMonitor) return []
    return getAvailableRatesForResolution(selectedMonitor, currentResolutionValue)
  }

  readonly property string currentRateValue: {
    if (!selectedMonitor) return ""
    var curr = selectedMonitor.refreshRate
    for (var i = 0; i < rateOptions.length; i++) {
      var optHz = parseFloat(rateOptions[i].value)
      if (Math.abs(optHz - curr) < 0.05) return rateOptions[i].value
    }
    return String(curr)
  }

  function parseStatus(raw) {
    try {
      var data = JSON.parse(raw)
      monitors = data
      if (selectedIndex >= data.length) selectedIndex = 0
    } catch (e) {
      // ignore parse error
    }
  }

  function refresh() {
    if (!statusProc.running) statusProc.running = true
  }

  property string pendingBrightnessMonitor: ""
  property int pendingBrightnessVal: -1

  Timer {
    id: brightnessDebounceTimer
    interval: 80
    repeat: false
    onTriggered: root.flushBrightness()
  }

  function queueBrightness(name, val) {
    pendingBrightnessMonitor = name
    pendingBrightnessVal = val
    if (!brightnessDebounceTimer.running && !brightnessProc.running) {
      flushBrightness()
    } else if (!brightnessDebounceTimer.running) {
      brightnessDebounceTimer.start()
    }
  }

  function flushBrightness() {
    if (pendingBrightnessVal < 0 || pendingBrightnessMonitor === "") return
    if (brightnessProc.running) return

    var name = pendingBrightnessMonitor
    var val = pendingBrightnessVal
    pendingBrightnessVal = -1

    brightnessProc.command = [
      String(Qt.resolvedUrl("backend.py")).replace(/^file:\/\//, ""),
      "set-brightness",
      name,
      String(val)
    ]
    brightnessProc.running = true
  }

  function forceBrightness(name, val) {
    pendingBrightnessMonitor = name
    pendingBrightnessVal = val
    if (!brightnessProc.running) {
      flushBrightness()
    }
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

  property bool pendingSave: false

  function saveLayout() {
    if (saveProc.running) {
      pendingSave = true
      return
    }
    pendingSave = false
    saveProc.command = [
      String(Qt.resolvedUrl("backend.py")).replace(/^file:\/\//, ""),
      "save",
      JSON.stringify(monitors)
    ]
    saveProc.running = true
    statusMessage = strings.t("display.saved")
    clearStatusTimer.restart()
  }

  function onCardDropped(draggedIdx, dropX, dropY) {
    if (monitors.length < 2) return

    var otherIdx = (draggedIdx === 0) ? 1 : 0
    var dMon = monitors[draggedIdx]
    var oMon = monitors[otherIdx]
    if (!dMon || !oMon) return

    var dW = Math.max(Style.space(80), dMon.width * root.canvasScale)
    var dH = Math.max(Style.space(50), dMon.height * root.canvasScale)
    var oW = Math.max(Style.space(80), oMon.width * root.canvasScale)
    var oH = Math.max(Style.space(50), oMon.height * root.canvasScale)

    var otherTargetX = root.canvasOffsetX + (oMon.x - root.groupBoundsMinX) * root.canvasScale
    var otherTargetY = root.canvasOffsetY + (oMon.y - root.groupBoundsMinY) * root.canvasScale

    var dropCenterX = dropX + dW / 2.0
    var dropCenterY = dropY + dH / 2.0
    var otherCenterX = otherTargetX + oW / 2.0
    var otherCenterY = otherTargetY + oH / 2.0

    var dx = dropCenterX - otherCenterX
    var dy = dropCenterY - otherCenterY

    var normX = dx / ((dW + oW) / 2.0)
    var normY = dy / ((dH + oH) / 2.0)

    console.log("Card dropped: index=" + draggedIdx + " dropX=" + dropX + " normX=" + normX.toFixed(2) + " normY=" + normY.toFixed(2))

    var copy = JSON.parse(JSON.stringify(monitors))
    var cdMon = copy[draggedIdx]
    var coMon = copy[otherIdx]

    if (Math.abs(normX) >= Math.abs(normY)) {
      var dH = Math.round(dMon.height / dMon.scale)
      var oH = Math.round(oMon.height / oMon.scale)
      var dY = 0
      var oY = 0
      if (dH < oH) {
        dY = Math.round((oH - dH) / 2.0)
      } else if (oH < dH) {
        oY = Math.round((dH - oH) / 2.0)
      }

      if (normX > 0) {
        // Dragged placed to the RIGHT of other monitor (centered vertically)
        coMon.x = 0
        coMon.y = oY
        cdMon.x = Math.round(coMon.width / coMon.scale)
        cdMon.y = dY
      } else {
        // Dragged placed to the LEFT of other monitor (centered vertically)
        cdMon.x = 0
        cdMon.y = dY
        coMon.x = Math.round(cdMon.width / cdMon.scale)
        coMon.y = oY
      }
    } else {
      var dW = Math.round(dMon.width / dMon.scale)
      var oW = Math.round(oMon.width / oMon.scale)
      var dX = 0
      var oX = 0
      if (dW < oW) {
        dX = Math.round((oW - dW) / 2.0)
      } else if (oW < dW) {
        oX = Math.round((dW - oW) / 2.0)
      }

      if (normY > 0) {
        // Dragged placed BELOW other monitor (centered horizontally)
        coMon.x = oX
        coMon.y = 0
        cdMon.x = dX
        cdMon.y = Math.round(coMon.height / coMon.scale)
      } else {
        // Dragged placed ABOVE other monitor (centered horizontally)
        cdMon.x = dX
        cdMon.y = 0
        coMon.x = oX
        coMon.y = Math.round(cdMon.height / cdMon.scale)
      }
    }

    monitors = copy
    root.saveLayout()
  }

  function onResolutionSelected(resVal) {
    if (!resVal || resVal === "" || !selectedMonitor) return
    var wh = resVal.split("x")
    if (wh.length !== 2) return
    var w = parseInt(wh[0])
    var h = parseInt(wh[1])
    if (w === selectedMonitor.width && h === selectedMonitor.height) return

    var copy = JSON.parse(JSON.stringify(monitors))
    copy[selectedIndex].width = w
    copy[selectedIndex].height = h

    var availRates = getAvailableRatesForResolution(copy[selectedIndex], resVal)
    if (availRates.length > 0) {
      copy[selectedIndex].refreshRate = parseFloat(availRates[0].value)
    }

    monitors = copy
    root.saveLayout()
  }

  function onRateSelected(rateVal) {
    if (!rateVal || rateVal === "" || !selectedMonitor) return
    var hz = parseFloat(rateVal)
    if (isNaN(hz) || hz === selectedMonitor.refreshRate) return

    var copy = JSON.parse(JSON.stringify(monitors))
    copy[selectedIndex].refreshRate = hz
    monitors = copy
    root.saveLayout()
  }

  function setScale(scaleVal) {
    if (!selectedMonitor) return
    var copy = JSON.parse(JSON.stringify(monitors))
    copy[selectedIndex].scale = scaleVal
    monitors = copy
    root.saveLayout()
  }

  function setTransform(transVal) {
    if (!selectedMonitor) return
    var copy = JSON.parse(JSON.stringify(monitors))
    copy[selectedIndex].transform = transVal
    monitors = copy
    root.saveLayout()
  }

  function toggleSelectedMonitorEnabled() {
    if (!selectedMonitor) return
    if (saveProc.running) return
    var copy = JSON.parse(JSON.stringify(monitors))
    var curr = copy[selectedIndex].disabled || false
    var enabledCount = 0
    for (var i = 0; i < copy.length; i++) {
      if (!copy[i].disabled) enabledCount++
    }
    if (!curr && enabledCount <= 1) return

    copy[selectedIndex].disabled = !curr
    monitors = copy
    root.saveLayout()
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

  Process {
    id: brightnessProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.pendingBrightnessVal >= 0) {
          root.flushBrightness()
        }
      }
    }
  }

  Process { id: applyProc }
  Process {
    id: saveProc
    onExited: (exitCode, exitStatus) => {
      if (root.pendingSave) {
        root.saveLayout()
      } else {
        root.refresh()
      }
    }
  }

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
    centerOnBar: true
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(475))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      implicitHeight: contentColumn.implicitHeight
      blocked: (typeof resDropdown !== "undefined" && resDropdown.popupOpen) || (typeof rateDropdown !== "undefined" && rateDropdown.popupOpen)
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
              text: root.statusMessage !== "" ? root.statusMessage : strings.t("display.subtitle")
              color: root.statusMessage !== "" ? root.accentColor : root.foreground
              opacity: root.statusMessage !== "" ? 1.0 : 0.65
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: root.statusMessage !== ""
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        // Interactive Drag-and-Drop Arrangement Canvas
        Rectangle {
          id: canvas
          width: parent.width
          height: Style.space(155)
          radius: Style.cornerRadius > 0 ? Style.cornerRadius : 8
          color: Qt.rgba(0, 0, 0, 0.25)
          border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.15)
          border.width: 1
          clip: true

          Text {
            textFormat: Text.PlainText
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottomMargin: Style.space(6)
            text: "✦ Drag screens to position · Release to snap & save"
            color: root.foreground
            opacity: 0.45
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }

          Repeater {
            id: monitorRepeater
            model: root.monitors

            Item {
              id: monitorCard
              required property var modelData
              required property int index

              readonly property bool isSelected: root.selectedIndex === index
              readonly property real w: Math.max(Style.space(80), modelData.width * root.canvasScale)
              readonly property real h: Math.max(Style.space(50), modelData.height * root.canvasScale)

              readonly property real targetX: root.canvasOffsetX + (modelData.x - root.groupBoundsMinX) * root.canvasScale
              readonly property real targetY: root.canvasOffsetY + (modelData.y - root.groupBoundsMinY) * root.canvasScale

              x: dragArea.drag.active ? x : targetX
              y: dragArea.drag.active ? y : targetY

              onXChanged: {
                if (dragArea.drag.active) dragArea.lastX = x
              }
              onYChanged: {
                if (dragArea.drag.active) dragArea.lastY = y
              }

              Behavior on x {
                enabled: !dragArea.drag.active
                NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic }
              }
              Behavior on y {
                enabled: !dragArea.drag.active
                NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic }
              }

              width: w
              height: h
              opacity: (modelData.disabled || false) ? 0.45 : 1.0
              z: dragArea.drag.active ? 100 : (isSelected ? 10 : 1)
              scale: dragArea.drag.active ? 1.05 : 1.0

              Behavior on scale {
                NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
              }

              Rectangle {
                anchors.fill: parent
                radius: 6
                color: monitorCard.isSelected ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.22) : (dragArea.drag.active ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.14) : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.08))
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

                  Text {
                    textFormat: Text.PlainText
                    visible: modelData.disabled || false
                    text: strings.t("display.disabled")
                    color: root.urgentColor
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    anchors.horizontalCenter: parent.horizontalCenter
                  }
                }
              }

              MouseArea {
                id: dragArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                drag.target: monitorCard
                drag.axis: Drag.XAndYAxis
                drag.minimumX: Style.space(4)
                drag.maximumX: root.canvasWidth - monitorCard.width - Style.space(4)
                drag.minimumY: Style.space(4)
                drag.maximumY: root.canvasHeight - monitorCard.height - Style.space(4)

                property real lastX: monitorCard.x
                property real lastY: monitorCard.y

                onPressed: {
                  root.selectedIndex = index
                  lastX = monitorCard.x
                  lastY = monitorCard.y
                }

                onReleased: {
                  root.onCardDropped(index, lastX, lastY)
                }
              }
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
          Item {
            width: parent.width
            implicitHeight: Math.max(monitorNameText.implicitHeight, badgeRow.implicitHeight)

            Text {
              id: monitorNameText
              anchors.left: parent.left
              anchors.right: badgeRow.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: (root.selectedMonitor ? root.selectedMonitor.name : "") + " (" + (root.selectedMonitor ? root.selectedMonitor.description : "") + ")"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
            }

            Row {
              id: badgeRow
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Rectangle {
                id: tagBadge
                anchors.verticalCenter: parent.verticalCenter
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

              ToggleSwitch {
                id: monitorEnableSwitch
                visible: root.selectedMonitor && root.monitors.length > 1
                anchors.verticalCenter: parent.verticalCenter
                trackHeight: Style.space(18)
                checked: root.selectedMonitor ? !root.selectedMonitor.disabled : true
                busy: saveProc.running
                accent: root.accentColor
                foreground: root.foreground
                onToggled: root.toggleSelectedMonitorEnabled()
              }
            }
          }

          // Hardware Brightness Slider (Thin Track & Live Feedback)
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
                anchors.verticalCenter: parent.verticalCenter
              }
              Item {
                width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth)
                height: 1
              }
              Text {
                textFormat: Text.PlainText
                text: root.liveBrightness + "%"
                color: root.accentColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Item {
              id: sliderContainer
              width: parent.width
              height: Style.space(20)

              Rectangle {
                id: bTrack
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: Style.space(5)
                radius: height / 2
                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)

                Rectangle {
                  id: bFill
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  radius: parent.radius
                  color: root.accentColor
                  width: Math.max(parent.radius, bTrack.width * (Math.max(1, Math.min(100, root.liveBrightness)) / 100.0))
                }
              }

              Rectangle {
                id: bThumb
                width: Style.space(14)
                height: Style.space(14)
                radius: width / 2
                color: root.accentColor
                border.color: root.foreground
                border.width: 1
                anchors.verticalCenter: parent.verticalCenter
                x: Math.max(0, Math.min(sliderContainer.width - width, bTrack.width * (root.liveBrightness / 100.0) - width / 2))
                scale: bMouseArea.pressed ? 1.25 : (bMouseArea.containsMouse ? 1.1 : 1.0)

                Behavior on scale {
                  NumberAnimation { duration: Style.duration(100); easing.type: Easing.OutCubic }
                }
              }

              MouseArea {
                id: bMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                function updateBrightnessFromMouse(mouseX) {
                  if (!root.selectedMonitor) return
                  var pct = Math.max(1, Math.min(100, Math.round((mouseX / width) * 100)))
                  root.liveBrightness = pct
                  root.queueBrightness(root.selectedMonitor.name, pct)
                }

                onPressed: function(mouse) {
                  updateBrightnessFromMouse(mouse.x)
                }

                onPositionChanged: function(mouse) {
                  if (pressed) {
                    updateBrightnessFromMouse(mouse.x)
                  }
                }

                onReleased: function(mouse) {
                  if (!root.selectedMonitor) return
                  var pct = Math.max(1, Math.min(100, Math.round((mouse.x / width) * 100)))
                  root.liveBrightness = pct
                  var copy = JSON.parse(JSON.stringify(root.monitors))
                  copy[root.selectedIndex].brightness = pct
                  root.monitors = copy
                  root.forceBrightness(root.selectedMonitor.name, pct)
                }
              }
            }
          }

          // Resolution Dropdown Row
          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              text: strings.t("display.resolution") + ":"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(85)
            }

            Dropdown {
              id: resDropdown
              width: parent.width - Style.space(93)
              fontFamily: root.fontFamily
              showLabel: false
              options: root.resolutionOptions
              value: root.currentResolutionValue
              onChanged: function(v) {
                root.onResolutionSelected(v)
              }
            }
          }

          // Refresh Rate Dropdown Row
          Row {
            width: parent.width
            spacing: Style.space(8)

            Text {
              textFormat: Text.PlainText
              text: strings.t("display.refreshRate") + ":"
              color: root.foreground
              opacity: 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(85)
            }

            Dropdown {
              id: rateDropdown
              width: parent.width - Style.space(93)
              fontFamily: root.fontFamily
              showLabel: false
              options: root.rateOptions
              value: root.currentRateValue
              onChanged: function(v) {
                root.onRateSelected(v)
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
              width: Style.space(85)
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
              width: Style.space(85)
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
      }
    }
  }
}
