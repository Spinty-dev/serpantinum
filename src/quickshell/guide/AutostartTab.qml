import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../"
import "../reusables"
import "../singletons"

Item {
    id: autostartTabRoot
    required property var rootObj
    required property int tabIndex

    anchors.fill: parent
    visible: rootObj.currentTab === tabIndex
    opacity: visible ? 1.0 : 0.0
    property real slideY: visible ? 0 : rootObj.s(10)

    Behavior on slideY { NumberAnimation { duration: 250; easing.type: Easing.OutQuart } }
    transform: Translate { y: slideY }
    Behavior on opacity { NumberAnimation { duration: 250 } }

    property var defaultAutostartSettings: ({
        "enabled": true,
        "entries": []
    })

    property var autostartSettings: defaultAutostartSettings
    property bool masterEnabled: true
    property var entriesList: []

    function syncSettings() {
        let s = (typeof Config !== "undefined" && Config.rawSettings && Config.rawSettings["autostart"])
            ? Config.rawSettings["autostart"]
            : ((typeof Config !== "undefined" && typeof Config.getSetting === "function")
                ? Config.getSetting("autostart", autostartTabRoot.defaultAutostartSettings)
                : autostartTabRoot.defaultAutostartSettings);
        autostartTabRoot.autostartSettings = s || autostartTabRoot.defaultAutostartSettings;
        autostartTabRoot.masterEnabled = (s && s.enabled !== undefined) ? s.enabled : true;
        autostartTabRoot.entriesList = (s && Array.isArray(s.entries)) ? s.entries : [];
    }

    property int activePickerIndex: -1
    property var collapsedEntriesMap: ({})
    property var liveStatusMap: ({})

    // Log viewer modal state
    property bool logModalVisible: false
    property string logModalTitle: ""
    property string logModalContent: ""
    property string logModalStatus: ""
    property int logModalExitCode: 0

    readonly property string autostartRunDir: ((typeof Caching !== "undefined" && Caching.runDir) ? Caching.runDir : ((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/serpantinum")) + "/autostart"

    function toggleCollapsed(entryId) {
        if (!entryId) return;
        let map = Object.assign({}, autostartTabRoot.collapsedEntriesMap);
        map[entryId] = !map[entryId];
        autostartTabRoot.collapsedEntriesMap = map;
        if (typeof Sounds !== "undefined") {
            Sounds.playSfx("reusables/button/click.wav");
        }
    }

    Timer {
        id: debounceTimer
        interval: 350
        repeat: false
        onTriggered: {
            Config.setSetting("autostart", autostartTabRoot.autostartSettings);
        }
    }

    function updateEntrySilent(index, key, val) {
        if (!Array.isArray(entriesList) || index < 0 || index >= entriesList.length) return;
        entriesList[index][key] = val;
        let current = {
            "enabled": autostartTabRoot.masterEnabled,
            "entries": entriesList
        };
        autostartTabRoot.autostartSettings = current;
        debounceTimer.restart();
    }

    function flushEntry(index, key, val) {
        if (!Array.isArray(entriesList) || index < 0 || index >= entriesList.length) return;
        entriesList[index][key] = val;
        let current = {
            "enabled": autostartTabRoot.masterEnabled,
            "entries": entriesList
        };
        autostartTabRoot.autostartSettings = current;
        Config.setSetting("autostart", current);
    }

    function toggleMasterEnabled(val) {
        autostartTabRoot.masterEnabled = val;
        let current = {
            "enabled": val,
            "entries": entriesList
        };
        autostartTabRoot.autostartSettings = current;
        Config.setSetting("autostart", current);
    }

    function addEntry() {
        let list = Array.isArray(entriesList) ? entriesList.slice() : [];
        let newEntry = {
            "id": "auto_" + Date.now().toString(36) + Math.random().toString(36).substr(2, 4),
            "name": "",
            "exec": "",
            "enabled": true,
            "delay": 0,
            "count": 1,
            "repeatDelay": 0,
            "workspace": 0,
            "silent": false,
            "condition": "always",
            "restartOnCrash": false
        };
        list.push(newEntry);
        autostartTabRoot.entriesList = list;
        let current = {
            "enabled": autostartTabRoot.masterEnabled,
            "entries": list
        };
        autostartTabRoot.autostartSettings = current;
        Config.setSetting("autostart", current);
    }

    function deleteEntry(index) {
        let list = Array.isArray(entriesList) ? entriesList.slice() : [];
        if (index < 0 || index >= list.length) return;
        list.splice(index, 1);
        autostartTabRoot.entriesList = list;
        let current = {
            "enabled": autostartTabRoot.masterEnabled,
            "entries": list
        };
        autostartTabRoot.autostartSettings = current;
        Config.setSetting("autostart", current);
    }

    function testRunEntry(execCmd, delay, count, repeatDelay, workspace, silent) {
        if (!execCmd || execCmd.trim() === "") return;
        let d = (delay !== undefined && delay !== null) ? Math.max(0, parseInt(delay)) : 0;
        let c = (count !== undefined && count !== null) ? Math.max(1, parseInt(count)) : 1;
        let r = (repeatDelay !== undefined && repeatDelay !== null) ? Math.max(0, parseInt(repeatDelay)) : 0;
        let ws = (workspace !== undefined && workspace !== null && parseInt(workspace) > 0) ? parseInt(workspace) : 0;
        let isSilent = (silent === true);

        let finalExec = execCmd;
        if (ws > 0 || isSilent) {
            let rules = "[";
            if (ws > 0) rules += "workspace " + ws + " ";
            if (isSilent) rules += "silent ";
            rules = rules.trim() + "]";
            finalExec = "hyprctl dispatch 'hl.dsp.exec_cmd(\\\"" + rules + " " + execCmd + "\\\")' 2>/dev/null || hyprctl dispatch exec \\\"" + rules + " " + execCmd + "\\\"";
        }

        let script = "";
        if (d > 0) {
            script += "sleep " + d + " && ";
        }
        if (c > 1) {
            script += "for ((i=0; i<" + c + "; i++)); do if (( i > 0 && " + r + " > 0 )); then sleep " + r + "; fi; (" + finalExec + ") & done";
        } else {
            script += "(" + finalExec + ") &";
        }

        Quickshell.execDetached(["bash", "-c", script]);
        if (typeof Sounds !== "undefined") {
            Sounds.playSfx("reusables/button/click.wav");
        }
    }

    function resolveAppIcon(execStr, nameStr) {
        let clean = (execStr || "").trim().split(" ")[0];
        let name = (nameStr || "").trim();
        if (!clean && !name) {
            return { isIcon: false, icon: "", fontIcon: "󰑮", isScript: false };
        }
        let base = clean.split("/").pop();
        let baseLower = base.toLowerCase();

        if (baseLower.endsWith(".sh") || baseLower.endsWith(".bash") || baseLower.endsWith(".zsh") || baseLower.endsWith(".py")) {
            return { isIcon: false, icon: "", fontIcon: "󰆍", isScript: true };
        }

        let iconName = "";
        try {
            if (typeof DesktopEntries !== "undefined" && typeof DesktopEntries.heuristicLookup === "function") {
                let entry = DesktopEntries.heuristicLookup(clean) || (name ? DesktopEntries.heuristicLookup(name) : null);
                if (entry && entry.icon) {
                    iconName = entry.icon;
                }
            }
        } catch(e) {}

        return { isIcon: iconName !== "", icon: iconName, fontIcon: "󰑮", isScript: false };
    }

    function openLogModal(entryId, entryName) {
        logModalTitle = entryName.trim() !== "" ? entryName : "Application Log";
        let statusObj = autostartTabRoot.liveStatusMap[entryId] || { status: "idle", exitCode: 0 };
        logModalStatus = statusObj.status || "idle";
        logModalExitCode = statusObj.exitCode || 0;

        autostartTabRoot.logModalContent = "";
        let logPath = autostartTabRoot.autostartRunDir + "/" + entryId + ".log";
        logReaderProc.targetEntryId = entryId;
        logReaderProc.running = false;
        logReaderProc.command = ["bash", "-c", "if [ -f '" + logPath + "' ]; then tail -n 300 '" + logPath + "'; else echo '(No log output captured yet)'; fi"];
        logReaderProc.running = true;
        logModalVisible = true;
    }

    Process {
        id: logReaderProc
        property string targetEntryId: ""
        stdout: SplitParser {
            splitMarker: ""
            onRead: data => {
                autostartTabRoot.logModalContent = (autostartTabRoot.logModalContent || "") + data;
            }
        }
    }

    Process {
        id: statusReaderProc
        command: ["bash", "-c", "cd \"" + autostartTabRoot.autostartRunDir + "\" 2>/dev/null && for f in *.json; do [ -f \"$f\" ] && echo -n \"${f%.json}:\" && cat \"$f\" && echo \"\"; done || true"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                let line = data.trim();
                if (line === "" || !line.includes(":")) return;
                let colonIdx = line.indexOf(":");
                let id = line.slice(0, colonIdx);
                let jsonStr = line.slice(colonIdx + 1);
                try {
                    let parsed = JSON.parse(jsonStr);
                    if (parsed && typeof parsed === "object") {
                        let map = Object.assign({}, autostartTabRoot.liveStatusMap);
                        map[id] = parsed;
                        autostartTabRoot.liveStatusMap = map;
                    }
                } catch(e) {}
            }
        }
    }

    Connections {
        target: typeof Config !== "undefined" ? Config : null
        function onSettingsLoaded() {
            autostartTabRoot.syncSettings();
        }
    }

    onVisibleChanged: {
        if (visible && !statusReaderProc.running) {
            statusReaderProc.running = true;
        }
    }

    Component.onCompleted: {
        autostartTabRoot.syncSettings();
        if (!statusReaderProc.running) {
            statusReaderProc.running = true;
        }
    }

    FilePicker {
        id: binaryPicker
        rootObj: autostartTabRoot.rootObj
        nameFilters: ["*"]
        titleText: I18n.t("guide.autostart.browse_file", "Select Executable")
        onFileSelected: function(filePath, fileName) {
            let idx = autostartTabRoot.activePickerIndex;
            if (idx >= 0 && idx < autostartTabRoot.entriesList.length) {
                let curItem = autostartTabRoot.entriesList[idx];
                curItem["exec"] = filePath;
                if (!curItem.name || curItem.name.trim() === "") {
                    curItem["name"] = fileName;
                }
                let current = {
                    "enabled": autostartTabRoot.masterEnabled,
                    "entries": autostartTabRoot.entriesList
                };
                autostartTabRoot.autostartSettings = current;
                Config.setSetting("autostart", current);
            }
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.topMargin: rootObj.s(4)
        anchors.leftMargin: rootObj.s(8)
        anchors.rightMargin: rootObj.s(8)
        anchors.bottomMargin: rootObj.s(4)
        contentWidth: width
        contentHeight: settingsCol.implicitHeight + rootObj.s(20)
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: settingsCol
            width: parent.width
            spacing: rootObj.s(10)

            // Master Enable Card
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: masterRowLayout.implicitHeight + rootObj.s(18)
                radius: ThemeBackend.borderRadius
                color: Qt.alpha(ThemeBackend.surface0, 0.5)
                border.color: Qt.alpha(ThemeBackend.surface1, 0.6)
                border.width: 1

                RowLayout {
                    id: masterRowLayout
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: rootObj.s(16)
                    anchors.rightMargin: rootObj.s(16)
                    spacing: rootObj.s(16)

                    Item {
                        Layout.preferredWidth: rootObj.s(32)
                        Layout.preferredHeight: rootObj.s(32)
                        Layout.alignment: Qt.AlignVCenter

                        Rectangle {
                            anchors.fill: parent
                            radius: rootObj.s(8)
                            color: autostartTabRoot.masterEnabled ? Qt.alpha(ThemeBackend.mauve, 0.2) : Qt.alpha(ThemeBackend.surface1, 0.4)

                            Text {
                                anchors.centerIn: parent
                                text: "󰐥"
                                font.family: ThemeBackend.fontFamily
                                font.pixelSize: rootObj.s(18)
                                color: autostartTabRoot.masterEnabled ? ThemeBackend.mauve : ThemeBackend.subtext0
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: rootObj.s(2)

                        Text {
                            text: I18n.t("guide.autostart.master_switch.title", "Enable Autostart")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(13)
                            font.weight: Font.DemiBold
                            color: ThemeBackend.text
                        }

                        Text {
                            text: I18n.t("guide.autostart.master_switch.desc", "Globally execute the configured startup application list on login")
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(11)
                            color: ThemeBackend.subtext0
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                    }

                    Toggle {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        checked: autostartTabRoot.masterEnabled
                        accentColor: ThemeBackend.mauve
                        onToggled: function(val) {
                            autostartTabRoot.toggleMasterEnabled(val);
                        }
                    }
                }
            }

            // Header & Add Button
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: rootObj.s(6)
                Layout.bottomMargin: rootObj.s(2)

                ColumnLayout {
                    spacing: rootObj.s(2)

                    Text {
                        text: I18n.t("guide.autostart.title", "Startup Applications")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(14)
                        font.weight: Font.Bold
                        color: ThemeBackend.text
                    }

                    Text {
                        text: I18n.t("guide.autostart.desc", "Manage programs, binaries, and scripts launched automatically upon session start")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(11)
                        color: ThemeBackend.subtext0
                    }
                }

                Item { Layout.fillWidth: true }

                ClickButton {
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                    implicitHeight: rootObj.s(34)
                    horizontalPadding: rootObj.s(14)
                    cornerRadius: ThemeBackend.borderRadius
                    buttonText: I18n.t("guide.autostart.add_button", "Add Application")
                    buttonIcon: "󰐕"
                    iconFontSize: rootObj.s(14)
                    textFontSize: rootObj.s(12)
                    accentColor: ThemeBackend.mauve
                    textColor: ThemeBackend.crust
                    onClicked: {
                        autostartTabRoot.addEntry();
                    }
                }
            }

            // Empty State Card
            Rectangle {
                visible: autostartTabRoot.entriesList.length === 0
                Layout.fillWidth: true
                implicitHeight: rootObj.s(180)
                radius: ThemeBackend.borderRadius
                color: Qt.alpha(ThemeBackend.surface0, 0.3)
                border.color: Qt.alpha(ThemeBackend.surface1, 0.4)
                border.width: 1

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: rootObj.s(8)

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "󱁐"
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(36)
                        color: Qt.alpha(ThemeBackend.subtext0, 0.5)
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: I18n.t("guide.autostart.empty_title", "No autostart applications")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(14)
                        font.weight: Font.DemiBold
                        color: ThemeBackend.text
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: I18n.t("guide.autostart.empty_desc", "Click 'Add Application' to specify commands, binaries, delays, and repetition counts.")
                        font.family: ThemeBackend.fontFamily
                        font.pixelSize: rootObj.s(11)
                        color: ThemeBackend.subtext0
                    }
                }
            }

            // List of Autostart Entries
            Repeater {
                id: entriesRepeater
                model: autostartTabRoot.entriesList

                delegate: Rectangle {
                    id: entryCard
                    required property var modelData
                    required property int index

                    property string entryId: modelData.id || ("auto_entry_" + index)
                    property string entryName: modelData.name || ""
                    property string entryExec: modelData.exec || ""
                    property bool entryEnabled: modelData.enabled !== undefined ? modelData.enabled : true
                    property int entryDelay: modelData.delay || 0
                    property int entryCount: modelData.count || 1
                    property int entryRepeatDelay: modelData.repeatDelay || modelData.repeat_delay || modelData.interval || 0
                    property int entryWorkspace: modelData.workspace || 0
                    property bool entrySilent: modelData.silent || false
                    property string entryCondition: modelData.condition || "always"
                    property bool entryRestart: modelData.restartOnCrash || false

                    property bool isExpanded: autostartTabRoot.collapsedEntriesMap[entryId] === true
                    property var statusInfo: autostartTabRoot.liveStatusMap[entryId] || ({ "status": "idle", "exitCode": 0 })
                    property bool isTestRunning: false

                    Timer {
                        id: testFeedbackTimer
                        interval: 1200
                        repeat: false
                        onTriggered: entryCard.isTestRunning = false
                    }

                    Layout.fillWidth: true
                    implicitHeight: cardInnerLayout.implicitHeight + rootObj.s(20)
                    radius: ThemeBackend.borderRadius
                    color: Qt.alpha(ThemeBackend.surface0, 0.4)
                    border.color: entryCard.isExpanded ? Qt.alpha(ThemeBackend.mauve, 0.5) : Qt.alpha(ThemeBackend.surface1, 0.5)
                    border.width: 1

                    Behavior on border.color { ColorAnimation { duration: 200 } }
                    Behavior on implicitHeight { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

                    ColumnLayout {
                        id: cardInnerLayout
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: rootObj.s(10)
                        spacing: rootObj.s(8)

                        // Top Row: App Icon + Name / Command + Status Badge + Quick Actions
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: rootObj.s(10)

                            // App Icon Box
                            Item {
                                Layout.preferredWidth: rootObj.s(34)
                                Layout.preferredHeight: rootObj.s(34)
                                Layout.alignment: Qt.AlignVCenter

                                Rectangle {
                                    anchors.fill: parent
                                    radius: rootObj.s(6)
                                    color: Qt.alpha(ThemeBackend.surface1, 0.6)

                                    property var iconInfo: (autostartTabRoot.resolveAppIcon(entryCard.entryExec, entryCard.entryName)) || ({ isIcon: false, icon: "", fontIcon: "󰑮", isScript: false })

                                    Image {
                                        anchors.fill: parent
                                        anchors.margins: rootObj.s(5)
                                        source: (parent.iconInfo && parent.iconInfo.isIcon) ? (parent.iconInfo.icon.startsWith("/") ? ("file://" + parent.iconInfo.icon) : ("image://icon/" + parent.iconInfo.icon)) : ""
                                        visible: parent.iconInfo && parent.iconInfo.isIcon && status === Image.Ready
                                        fillMode: Image.PreserveAspectFit
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        visible: !parent.iconInfo || !parent.iconInfo.isIcon
                                        text: (parent.iconInfo && parent.iconInfo.fontIcon) ? parent.iconInfo.fontIcon : "󰑮"
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: rootObj.s(16)
                                        color: (parent.iconInfo && parent.iconInfo.isScript) ? ThemeBackend.yellow : ThemeBackend.mauve
                                    }
                                }
                            }

                            // Summary Info (Clickable to expand)
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: rootObj.s(34)

                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: rootObj.s(2)

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: rootObj.s(8)

                                        Text {
                                            text: entryCard.entryName.trim() !== "" ? entryCard.entryName : (entryCard.entryExec.trim() !== "" ? entryCard.entryExec : ("#" + (index + 1) + " Application"))
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: rootObj.s(13)
                                            font.weight: Font.DemiBold
                                            color: entryCard.entryEnabled ? ThemeBackend.text : ThemeBackend.subtext0
                                            elide: Text.ElideRight
                                        }

                                        // Live Status Badge
                                        Rectangle {
                                            Layout.preferredHeight: rootObj.s(18)
                                            implicitWidth: statusBadgeRow.implicitWidth + rootObj.s(10)
                                            radius: rootObj.s(9)
                                            color: entryCard.statusInfo.status === "running" ? Qt.alpha(ThemeBackend.green, 0.2)
                                                 : (entryCard.statusInfo.status === "failed" ? Qt.alpha(ThemeBackend.red, 0.2)
                                                 : (entryCard.statusInfo.status === "success" ? Qt.alpha(ThemeBackend.green, 0.1) : "transparent"))
                                            visible: entryCard.statusInfo.status !== "idle"

                                            RowLayout {
                                                id: statusBadgeRow
                                                anchors.centerIn: parent
                                                spacing: rootObj.s(4)

                                                Rectangle {
                                                    width: rootObj.s(6)
                                                    height: rootObj.s(6)
                                                    radius: 3
                                                    color: entryCard.statusInfo.status === "running" ? ThemeBackend.green
                                                         : (entryCard.statusInfo.status === "failed" ? ThemeBackend.red : ThemeBackend.subtext0)

                                                    SequentialAnimation on opacity {
                                                        running: entryCard.statusInfo.status === "running"
                                                        loops: Animation.Infinite
                                                        NumberAnimation { from: 1.0; to: 0.3; duration: 600 }
                                                        NumberAnimation { from: 0.3; to: 1.0; duration: 600 }
                                                    }
                                                }

                                                Text {
                                                    text: entryCard.statusInfo.status === "running" ? I18n.t("guide.autostart.status_running", "Running")
                                                        : (entryCard.statusInfo.status === "failed" ? (I18n.t("guide.autostart.status_failed", "Failed") + " (" + entryCard.statusInfo.exitCode + ")")
                                                        : I18n.t("guide.autostart.status_success", "Success"))
                                                    font.family: ThemeBackend.fontFamily
                                                    font.pixelSize: rootObj.s(9)
                                                    font.weight: Font.DemiBold
                                                    color: entryCard.statusInfo.status === "running" ? ThemeBackend.green
                                                         : (entryCard.statusInfo.status === "failed" ? ThemeBackend.red : ThemeBackend.subtext0)
                                                }
                                            }

                                            TapHandler {
                                                onTapped: {
                                                    autostartTabRoot.openLogModal(entryCard.entryId, entryCard.entryName);
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        text: !entryCard.isExpanded
                                            ? ((entryCard.entryExec.trim() !== "" ? entryCard.entryExec : "No command")
                                               + (entryCard.entryWorkspace > 0 ? (" • WS " + entryCard.entryWorkspace) : "")
                                               + (entryCard.entrySilent ? " • Silent" : "")
                                               + (entryCard.entryDelay > 0 ? (" • " + entryCard.entryDelay + "s") : "")
                                               + (entryCard.entryCount > 1 ? (" • " + entryCard.entryCount + "x" + (entryCard.entryRepeatDelay > 0 ? (" (" + entryCard.entryRepeatDelay + "s)") : "")) : ""))
                                            : (entryCard.entryExec.trim() !== "" ? entryCard.entryExec : "")
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: rootObj.s(10)
                                        color: ThemeBackend.subtext0
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        autostartTabRoot.toggleCollapsed(entryCard.entryId);
                                    }
                                }
                            }

                            // View Log Button
                            IconButton {
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: rootObj.s(30)
                                implicitHeight: rootObj.s(30)
                                cornerRadius: rootObj.s(6)
                                buttonIcon: "󰆍"
                                iconFontSize: rootObj.s(13)
                                accentColor: ThemeBackend.surface0
                                textColor: ThemeBackend.subtext0
                                onClicked: {
                                    autostartTabRoot.openLogModal(entryCard.entryId, entryCard.entryName);
                                }
                            }

                            // Test Run Button
                            IconButton {
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: rootObj.s(30)
                                implicitHeight: rootObj.s(30)
                                cornerRadius: rootObj.s(6)
                                buttonIcon: entryCard.isTestRunning ? "󱎫" : "󰐊"
                                iconFontSize: rootObj.s(13)
                                iconOffsetX: entryCard.isTestRunning ? 0 : 1
                                accentColor: entryCard.isTestRunning ? Qt.alpha(ThemeBackend.yellow, 0.2) : ThemeBackend.surface0
                                textColor: entryCard.isTestRunning ? ThemeBackend.yellow : (entryCard.entryExec.trim() !== "" ? ThemeBackend.green : ThemeBackend.subtext0)
                                onClicked: {
                                    if (entryCard.entryExec.trim() !== "") {
                                        entryCard.isTestRunning = true;
                                        testFeedbackTimer.restart();
                                        autostartTabRoot.testRunEntry(entryCard.entryExec, entryCard.entryDelay, entryCard.entryCount, entryCard.entryRepeatDelay, entryCard.entryWorkspace, entryCard.entrySilent);
                                    }
                                }
                            }

                            // Browse Executable Button
                            IconButton {
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: rootObj.s(30)
                                implicitHeight: rootObj.s(30)
                                cornerRadius: rootObj.s(6)
                                buttonIcon: "󰉋"
                                iconFontSize: rootObj.s(13)
                                accentColor: ThemeBackend.surface0
                                textColor: ThemeBackend.mauve
                                onClicked: {
                                    autostartTabRoot.activePickerIndex = index;
                                    binaryPicker.open();
                                }
                            }

                            // Entry Enable/Disable Toggle
                            Toggle {
                                Layout.alignment: Qt.AlignVCenter
                                checked: entryCard.entryEnabled
                                accentColor: ThemeBackend.mauve
                                onToggled: function(val) {
                                    entryCard.entryEnabled = val;
                                    autostartTabRoot.flushEntry(index, "enabled", val);
                                }
                            }

                            // Delete Button
                            IconButton {
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: rootObj.s(30)
                                implicitHeight: rootObj.s(30)
                                cornerRadius: rootObj.s(6)
                                buttonIcon: "󰅖"
                                iconFontSize: rootObj.s(13)
                                accentColor: Qt.alpha(ThemeBackend.red, 0.15)
                                textColor: ThemeBackend.red
                                onClicked: {
                                    autostartTabRoot.deleteEntry(index);
                                }
                            }

                            // Chevron Expand / Collapse Button
                            IconButton {
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: rootObj.s(30)
                                implicitHeight: rootObj.s(30)
                                cornerRadius: rootObj.s(6)
                                buttonIcon: "󰅀"
                                iconFontSize: rootObj.s(14)
                                accentColor: ThemeBackend.surface0
                                textColor: ThemeBackend.text
                                rotation: entryCard.isExpanded ? 180 : 0
                                Behavior on rotation { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
                                onClicked: {
                                    autostartTabRoot.toggleCollapsed(entryCard.entryId);
                                }
                            }
                        }

                        // Collapsible Body
                        Item {
                            id: expandableWrapper
                            Layout.fillWidth: true
                            clip: true
                            visible: opacity > 0
                            opacity: entryCard.isExpanded ? 1.0 : 0.0
                            implicitHeight: entryCard.isExpanded ? expandableCol.implicitHeight : 0

                            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            Behavior on implicitHeight { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }

                            ColumnLayout {
                                id: expandableCol
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                spacing: rootObj.s(12)

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 1
                                    color: Qt.alpha(ThemeBackend.surface1, 0.4)
                                    Layout.topMargin: rootObj.s(2)
                                    Layout.bottomMargin: rootObj.s(2)
                                }

                                // Section 1: Basic Info (Name and Command)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: rootObj.s(10)

                                    ColumnLayout {
                                        Layout.preferredWidth: rootObj.s(180)
                                        spacing: rootObj.s(4)

                                        Text {
                                            text: I18n.t("guide.autostart.name_label", "Name")
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: rootObj.s(11)
                                            color: ThemeBackend.subtext0
                                        }

                                        Input {
                                            id: cardNameInput
                                            Layout.fillWidth: true
                                            implicitHeight: rootObj.s(32)
                                            text: entryCard.entryName
                                            placeholderText: I18n.t("guide.autostart.name_placeholder", "e.g. Discord, Script")
                                            fontPixelSize: rootObj.s(11)
                                            baseColor: ThemeBackend.surface0
                                            accentColor: ThemeBackend.mauve
                                            textColor: ThemeBackend.text
                                            borderColor: Qt.alpha(ThemeBackend.surface2, 0.5)
                                            cornerRadius: rootObj.s(6)
                                            onTextEdited: function(newText) {
                                                entryCard.entryName = newText;
                                                autostartTabRoot.updateEntrySilent(index, "name", newText);
                                            }
                                            onAccepted: function(t) {
                                                let val = (typeof t === "string") ? t : text;
                                                entryCard.entryName = val;
                                                autostartTabRoot.flushEntry(index, "name", val);
                                            }
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: rootObj.s(4)

                                        Text {
                                            text: I18n.t("guide.autostart.exec_label", "Command / Executable")
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: rootObj.s(11)
                                            color: ThemeBackend.subtext0
                                        }

                                        Input {
                                            id: cardExecInput
                                            Layout.fillWidth: true
                                            implicitHeight: rootObj.s(32)
                                            text: entryCard.entryExec
                                            placeholderText: I18n.t("guide.autostart.exec_placeholder", "Binary path or command + flags")
                                            fontPixelSize: rootObj.s(11)
                                            baseColor: ThemeBackend.surface0
                                            accentColor: ThemeBackend.mauve
                                            textColor: ThemeBackend.text
                                            borderColor: Qt.alpha(ThemeBackend.surface2, 0.5)
                                            cornerRadius: rootObj.s(6)
                                            onTextEdited: function(newText) {
                                                entryCard.entryExec = newText;
                                                autostartTabRoot.updateEntrySilent(index, "exec", newText);
                                            }
                                            onAccepted: function(t) {
                                                let val = (typeof t === "string") ? t : text;
                                                entryCard.entryExec = val;
                                                autostartTabRoot.flushEntry(index, "exec", val);
                                            }
                                        }
                                    }
                                }

                                // Section 2: Timing, Repetition & Workspace (All in ONE single line as requested)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: rootObj.s(10)

                                    // Startup Delay
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: rootObj.s(4)

                                        Text {
                                            text: I18n.t("guide.autostart.delay_label", "Startup Delay")
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: rootObj.s(11)
                                            color: ThemeBackend.subtext0
                                        }

                                        NumberSelector {
                                            Layout.fillWidth: true
                                            implicitHeight: rootObj.s(32)
                                            from: 0
                                            to: 3600
                                            stepSize: 1
                                            decimals: 0
                                            suffix: "s"
                                            value: entryCard.entryDelay
                                            baseColor: ThemeBackend.surface0
                                            accentColor: ThemeBackend.mauve
                                            buttonColor: ThemeBackend.surface1
                                            buttonTextColor: ThemeBackend.text
                                            textColor: ThemeBackend.text
                                            borderColor: Qt.alpha(ThemeBackend.surface2, 0.5)
                                            cornerRadius: rootObj.s(6)
                                            fontFamily: ThemeBackend.fontFamily
                                            fontPixelSize: rootObj.s(11)
                                            onTriggered: {
                                                let rounded = Math.max(0, Math.round(value));
                                                if (entryCard.entryDelay !== rounded) {
                                                    entryCard.entryDelay = rounded;
                                                    autostartTabRoot.flushEntry(index, "delay", rounded);
                                                }
                                            }
                                        }
                                    }

                                    // Launch Count
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: rootObj.s(4)

                                        Text {
                                            text: I18n.t("guide.autostart.count_label", "Launch Count")
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: rootObj.s(11)
                                            color: ThemeBackend.subtext0
                                        }

                                        NumberSelector {
                                            Layout.fillWidth: true
                                            implicitHeight: rootObj.s(32)
                                            from: 1
                                            to: 50
                                            stepSize: 1
                                            decimals: 0
                                            value: entryCard.entryCount
                                            baseColor: ThemeBackend.surface0
                                            accentColor: ThemeBackend.mauve
                                            buttonColor: ThemeBackend.surface1
                                            buttonTextColor: ThemeBackend.text
                                            textColor: ThemeBackend.text
                                            borderColor: Qt.alpha(ThemeBackend.surface2, 0.5)
                                            cornerRadius: rootObj.s(6)
                                            fontFamily: ThemeBackend.fontFamily
                                            fontPixelSize: rootObj.s(11)
                                            onTriggered: {
                                                let rounded = Math.max(1, Math.round(value));
                                                if (entryCard.entryCount !== rounded) {
                                                    entryCard.entryCount = rounded;
                                                    autostartTabRoot.flushEntry(index, "count", rounded);
                                                }
                                            }
                                        }
                                    }

                                    // Workspace Selection
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: rootObj.s(4)

                                        Text {
                                            text: I18n.t("guide.autostart.workspace_label", "Workspace")
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: rootObj.s(11)
                                            color: ThemeBackend.subtext0
                                        }

                                        NumberSelector {
                                            Layout.fillWidth: true
                                            implicitHeight: rootObj.s(32)
                                            from: 0
                                            to: 10
                                            stepSize: 1
                                            decimals: 0
                                            prefix: "WS "
                                            specialZeroText: I18n.t("guide.autostart.workspace_default", "Default")
                                            value: entryCard.entryWorkspace
                                            baseColor: ThemeBackend.surface0
                                            accentColor: ThemeBackend.mauve
                                            buttonColor: ThemeBackend.surface1
                                            buttonTextColor: ThemeBackend.text
                                            textColor: ThemeBackend.text
                                            borderColor: Qt.alpha(ThemeBackend.surface2, 0.5)
                                            cornerRadius: rootObj.s(6)
                                            fontFamily: ThemeBackend.fontFamily
                                            fontPixelSize: rootObj.s(11)
                                            onTriggered: {
                                                let rounded = Math.max(0, Math.round(value));
                                                if (entryCard.entryWorkspace !== rounded) {
                                                    entryCard.entryWorkspace = rounded;
                                                    autostartTabRoot.flushEntry(index, "workspace", rounded);
                                                }
                                            }
                                        }
                                    }

                                    // Repeat Interval (Visible only when count > 1)
                                    ColumnLayout {
                                        visible: entryCard.entryCount > 1
                                        Layout.fillWidth: true
                                        spacing: rootObj.s(4)

                                        Text {
                                            text: I18n.t("guide.autostart.repeat_delay_label", "Repeat Interval")
                                            font.family: ThemeBackend.fontFamily
                                            font.pixelSize: rootObj.s(11)
                                            color: ThemeBackend.subtext0
                                        }

                                        NumberSelector {
                                            Layout.fillWidth: true
                                            implicitHeight: rootObj.s(32)
                                            from: 0
                                            to: 3600
                                            stepSize: 1
                                            decimals: 0
                                            suffix: "s"
                                            value: entryCard.entryRepeatDelay
                                            baseColor: ThemeBackend.surface0
                                            accentColor: ThemeBackend.mauve
                                            buttonColor: ThemeBackend.surface1
                                            buttonTextColor: ThemeBackend.text
                                            textColor: ThemeBackend.text
                                            borderColor: Qt.alpha(ThemeBackend.surface2, 0.5)
                                            cornerRadius: rootObj.s(6)
                                            fontFamily: ThemeBackend.fontFamily
                                            fontPixelSize: rootObj.s(11)
                                            onTriggered: {
                                                let rounded = Math.max(0, Math.round(value));
                                                if (entryCard.entryRepeatDelay !== rounded) {
                                                    entryCard.entryRepeatDelay = rounded;
                                                    autostartTabRoot.flushEntry(index, "repeatDelay", rounded);
                                                }
                                            }
                                        }
                                    }
                                }

                                // Section 3: Options (Silent Launch & Keep-Alive Watchdog)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: rootObj.s(10)

                                    // Silent Launch Toggle
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: rootObj.s(46)
                                        radius: rootObj.s(6)
                                        color: Qt.alpha(ThemeBackend.surface0, 0.4)
                                        border.color: Qt.alpha(ThemeBackend.surface1, 0.4)
                                        border.width: 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: rootObj.s(10)
                                            anchors.rightMargin: rootObj.s(10)
                                            spacing: rootObj.s(8)

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0

                                                Text {
                                                    text: I18n.t("guide.autostart.silent_label", "Silent Launch")
                                                    font.family: ThemeBackend.fontFamily
                                                    font.pixelSize: rootObj.s(11)
                                                    font.weight: Font.DemiBold
                                                    color: ThemeBackend.text
                                                }

                                                Text {
                                                    text: I18n.t("guide.autostart.silent_desc", "Do not steal focus")
                                                    font.family: ThemeBackend.fontFamily
                                                    font.pixelSize: rootObj.s(9)
                                                    color: ThemeBackend.subtext0
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                            }

                                            Toggle {
                                                Layout.alignment: Qt.AlignVCenter
                                                checked: entryCard.entrySilent
                                                accentColor: ThemeBackend.mauve
                                                onToggled: function(val) {
                                                    entryCard.entrySilent = val;
                                                    autostartTabRoot.flushEntry(index, "silent", val);
                                                }
                                            }
                                        }
                                    }

                                    // Keep-Alive / Watchdog Toggle
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: rootObj.s(46)
                                        radius: rootObj.s(6)
                                        color: Qt.alpha(ThemeBackend.surface0, 0.4)
                                        border.color: Qt.alpha(ThemeBackend.surface1, 0.4)
                                        border.width: 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: rootObj.s(10)
                                            anchors.rightMargin: rootObj.s(10)
                                            spacing: rootObj.s(8)

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0

                                                Text {
                                                    text: I18n.t("guide.autostart.restart_crash_label", "Keep-Alive")
                                                    font.family: ThemeBackend.fontFamily
                                                    font.pixelSize: rootObj.s(11)
                                                    font.weight: Font.DemiBold
                                                    color: ThemeBackend.text
                                                }

                                                Text {
                                                    text: I18n.t("guide.autostart.restart_crash_desc", "Restart if crashes")
                                                    font.family: ThemeBackend.fontFamily
                                                    font.pixelSize: rootObj.s(9)
                                                    color: ThemeBackend.subtext0
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                            }

                                            Toggle {
                                                Layout.alignment: Qt.AlignVCenter
                                                checked: entryCard.entryRestart
                                                accentColor: ThemeBackend.mauve
                                                onToggled: function(val) {
                                                    entryCard.entryRestart = val;
                                                    autostartTabRoot.flushEntry(index, "restartOnCrash", val);
                                                }
                                            }
                                        }
                                    }
                                }

                                // Section 4: Launch Condition Selector
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: rootObj.s(4)

                                    Text {
                                        text: I18n.t("guide.autostart.condition_label", "Launch Condition")
                                        font.family: ThemeBackend.fontFamily
                                        font.pixelSize: rootObj.s(11)
                                        color: ThemeBackend.subtext0
                                    }

                                    Switch {
                                        Layout.fillWidth: true
                                        implicitHeight: rootObj.s(32)
                                        options: [
                                            I18n.t("guide.autostart.condition_always", "Always"),
                                            I18n.t("guide.autostart.condition_ac_only", "AC Only"),
                                            I18n.t("guide.autostart.condition_battery_only", "Battery"),
                                            I18n.t("guide.autostart.condition_multi_monitor", "Multi-Mon")
                                        ]
                                        currentIndex: entryCard.entryCondition === "ac_only" ? 1
                                                    : (entryCard.entryCondition === "battery_only" ? 2
                                                    : (entryCard.entryCondition === "multi_monitor" ? 3 : 0))
                                        accentColor: ThemeBackend.mauve
                                        baseColor: ThemeBackend.surface0
                                        textColor: ThemeBackend.subtext0
                                        activeTextColor: ThemeBackend.crust
                                        cornerRadius: rootObj.s(6)
                                        fontPixelSize: rootObj.s(10)
                                        onToggled: function(idx) {
                                            let cond = "always";
                                            if (idx === 1) cond = "ac_only";
                                            else if (idx === 2) cond = "battery_only";
                                            else if (idx === 3) cond = "multi_monitor";
                                            if (entryCard.entryCondition !== cond) {
                                                entryCard.entryCondition = cond;
                                                autostartTabRoot.flushEntry(index, "condition", cond);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Execution Log Modal Dialog
    Rectangle {
        id: logModalBackdrop
        anchors.fill: parent
        color: Qt.alpha(ThemeBackend.crust, 0.8)
        visible: autostartTabRoot.logModalVisible
        opacity: visible ? 1.0 : 0.0
        z: 100

        Behavior on opacity { NumberAnimation { duration: 200 } }

        MouseArea {
            anchors.fill: parent
            onClicked: autostartTabRoot.logModalVisible = false
        }

        Rectangle {
            id: logModalCard
            anchors.centerIn: parent
            width: Math.min(parent.width - rootObj.s(40), rootObj.s(520))
            height: Math.min(parent.height - rootObj.s(40), rootObj.s(380))
            radius: ThemeBackend.borderRadius
            color: ThemeBackend.base
            border.color: ThemeBackend.surface1
            border.width: 1

            MouseArea {
                anchors.fill: parent
                // Prevent backdrop close click when clicking modal card
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: rootObj.s(16)
                spacing: rootObj.s(12)

                // Modal Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: rootObj.s(10)

                    Rectangle {
                        Layout.preferredWidth: rootObj.s(28)
                        Layout.preferredHeight: rootObj.s(28)
                        radius: rootObj.s(6)
                        color: Qt.alpha(ThemeBackend.mauve, 0.2)

                        Text {
                            anchors.centerIn: parent
                            text: "󰆍"
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(14)
                            color: ThemeBackend.mauve
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Text {
                            text: autostartTabRoot.logModalTitle
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(13)
                            font.weight: Font.Bold
                            color: ThemeBackend.text
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            text: autostartTabRoot.logModalStatus === "running" ? I18n.t("guide.autostart.status_running", "Running")
                                : (autostartTabRoot.logModalStatus === "failed" ? (I18n.t("guide.autostart.status_failed", "Failed") + " (Exit code " + autostartTabRoot.logModalExitCode + ")")
                                : (autostartTabRoot.logModalStatus === "success" ? I18n.t("guide.autostart.status_success", "Completed successfully (Exit code 0)")
                                : I18n.t("guide.autostart.status_idle", "Idle")))
                            font.family: ThemeBackend.fontFamily
                            font.pixelSize: rootObj.s(10)
                            color: autostartTabRoot.logModalStatus === "running" ? ThemeBackend.green
                                 : (autostartTabRoot.logModalStatus === "failed" ? ThemeBackend.red : ThemeBackend.subtext0)
                        }
                    }

                    IconButton {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: rootObj.s(28)
                        implicitHeight: rootObj.s(28)
                        cornerRadius: rootObj.s(6)
                        buttonIcon: "󰅖"
                        iconFontSize: rootObj.s(12)
                        accentColor: Qt.alpha(ThemeBackend.surface1, 0.5)
                        textColor: ThemeBackend.text
                        onClicked: autostartTabRoot.logModalVisible = false
                    }
                }

                // Log Content Box
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: rootObj.s(6)
                    color: ThemeBackend.crust
                    border.color: Qt.alpha(ThemeBackend.surface1, 0.4)
                    border.width: 1
                    clip: true

                    Flickable {
                        id: logFlickable
                        anchors.fill: parent
                        anchors.margins: rootObj.s(10)
                        contentWidth: logText.implicitWidth
                        contentHeight: logText.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        TextEdit {
                            id: logText
                            width: logFlickable.width
                            text: autostartTabRoot.logModalContent !== "" ? autostartTabRoot.logModalContent : I18n.t("guide.autostart.no_log", "No log output captured yet")
                            font.family: "JetBrainsMono Nerd Font Mono"
                            font.pixelSize: rootObj.s(11)
                            color: autostartTabRoot.logModalStatus === "failed" ? ThemeBackend.red : ThemeBackend.text
                            wrapMode: TextEdit.Wrap
                            readOnly: true
                            selectByMouse: true
                        }
                    }
                }

                // Modal Footer
                RowLayout {
                    Layout.fillWidth: true
                    spacing: rootObj.s(8)

                    ClickButton {
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        implicitHeight: rootObj.s(30)
                        horizontalPadding: rootObj.s(16)
                        cornerRadius: rootObj.s(6)
                        buttonText: "Close"
                        accentColor: ThemeBackend.surface0
                        textColor: ThemeBackend.text
                        onClicked: autostartTabRoot.logModalVisible = false
                    }
                }
            }
        }
    }
}
