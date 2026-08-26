// Proton VPN — DankMaterialShell dankbar widget.
//
// Bar: the Proton VPN mark. Themed neutral when disconnected, accent when
// connected.
//
// Popout: account subtitle, a connection toggle for the fastest server overall,
// dropdowns to pick a US state or a country, and a button to open Proton's own
// app. Account management and the settings Proton doesn't expose to the CLI
// stay in that app.
//
// Connection state comes from `nmcli`, not from `protonvpn status`. The CLI
// refuses to run while Proton's GTK app is alive and *exits 0* while refusing,
// so it cannot be trusted as a state source. The presence of the `proton0`
// device is authoritative no matter what else is running.

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "./components"

PluginComponent {
    id: root

    readonly property int pollSeconds: parseInt(pluginData.pollSeconds) || 5

    property bool connected: false
    property string serverName: ""
    property string account: ""
    property bool busy: false
    property string lastError: ""

    // Where the in-flight command is trying to get to. A connect or disconnect
    // takes seconds, so the toggle reflects intent immediately and the label
    // reports the transition; `connected` alone would leave both frozen on the
    // old state until the command returned.
    property bool desiredConnected: false

    // US state selection has to be computed locally — Proton's API has no state
    // tier, only the server name encodes it. See scripts/us-states.py.
    property var stateOptions: []
    property var stateCodes: ({})
    property string selectedState: ""

    // Countries go straight to `connect --country`, so Proton picks the server
    // and refreshes its own cache while doing it.
    property var countryOptions: []
    property var countryCodes: ({})
    property string selectedCountry: ""

    readonly property string statesScript: Qt.resolvedUrl("scripts/us-states.py").toString().replace("file://", "")

    // Optical size correction. The Proton glyph fills its viewBox edge to edge,
    // while the Material icons beside it on the bar carry internal padding, so
    // matching their nominal size makes ours read noticeably larger. Tune the
    // factor, not the base — `iconSize` already honors barThickness and iconScale.
    readonly property real markSize: Math.round(root.iconSize * 0.8)

    readonly property string stateLabel: {
        if (busy)
            return desiredConnected ? "Connecting…" : "Disconnecting…";
        return connected ? "Connected" : "Disconnected";
    }

    // The toggle shows intent while a command is in flight, so it flips the
    // instant it's clicked. If the command fails, `busy` clears and it snaps
    // back to the real state.
    readonly property bool toggleChecked: busy ? desiredConnected : connected

    function refreshStatus() {
        Proc.runCommand("protonVpn-status", ["sh", "-c", "nmcli -t -f NAME,DEVICE connection show --active"], function (output, exitCode) {
            if (exitCode !== 0) {
                // Leave the prior reading; a stale pill beats a flapping one.
                return;
            }
            let found = false;
            let name = "";
            for (const line of output.split("\n")) {
                // NAME may contain spaces ("ProtonVPN US-GA#580"); the device is
                // the last colon-separated field.
                const idx = line.lastIndexOf(":");
                if (idx === -1)
                    continue;
                if (line.substring(idx + 1).trim() === "proton0") {
                    found = true;
                    name = line.substring(0, idx).replace(/^ProtonVPN\s+/, "").trim();
                    break;
                }
            }
            root.connected = found;
            root.serverName = found ? name : "";
            // Nothing is connected, so no selector describes reality — including
            // when the tunnel went down outside this widget (the CLI, the Proton
            // app, a dropped link). Skip while a command is in flight, since a
            // connect passes through "not connected" on its way up.
            if (!found && !root.busy) {
                root.selectedState = "";
                root.selectedCountry = "";
            }
        });
    }

    // The account email is the popout subtitle. It never changes between
    // sign-ins, and `protonvpn info` is blocked whenever the GTK app is running,
    // so fetch it once and keep it.
    function refreshAccount() {
        if (root.account)
            return;
        Proc.runCommand("protonVpn-info", ["sh", "-c", "protonvpn info 2>&1"], function (output, exitCode) {
            const m = output.match(/Account:\s*'([^']+)'/);
            if (m)
                root.account = m[1];
        }, 0, 20000);
    }

    function refreshStates() {
        if (root.stateOptions.length > 0)
            return;
        Proc.runCommand("protonVpn-states", ["sh", "-c", "'" + root.statesScript + "' list"], function (output, exitCode) {
            if (exitCode !== 0)
                return;
            const names = [];
            const codes = {};
            for (const line of output.split("\n")) {
                const parts = line.trim().split(":");
                if (parts.length !== 2 || !parts[0])
                    continue;
                codes[parts[1]] = parts[0];
                names.push(parts[1]);
            }
            root.stateCodes = codes;
            root.stateOptions = names;
        }, 0, 20000);
    }

    // `countries list` also refreshes the server cache, so it can take a few
    // seconds on a cold start. Fetch once per session and keep it.
    function refreshCountries() {
        if (root.countryOptions.length > 0)
            return;
        Proc.runCommand("protonVpn-countries", ["sh", "-c", "protonvpn countries list 2>&1"], function (output, exitCode) {
            if (exitCode !== 0)
                return;
            const names = [];
            const codes = {};
            for (const line of output.split("\n")) {
                // "Afghanistan                       AF" — two or more spaces
                // separate the name from the code. Skips the header and rules.
                const m = line.match(/^(.+?)\s{2,}([A-Z]{2})\s*$/);
                if (!m)
                    continue;
                codes[m[1].trim()] = m[2];
                names.push(m[1].trim());
            }
            root.countryCodes = codes;
            root.countryOptions = names;
        }, 0, 60000);
    }

    // Exit codes are useless for Proton commands — the GUI-running refusal also
    // exits 0 — so failures are matched on message text.
    function noteFailure(output, exitCode, label) {
        if (output.indexOf("desktop app is currently running") !== -1)
            root.lastError = "Quit the Proton VPN app first";
        else if (exitCode !== 0)
            root.lastError = label + " failed";
    }

    function runProton(args, label, wantConnected) {
        root.busy = true;
        root.desiredConnected = wantConnected;
        root.lastError = "";
        // Generous timeout: a connect can refresh the whole server list first.
        Proc.runCommand("protonVpn-connect", ["sh", "-c", "protonvpn " + args + " 2>&1"], function (output, exitCode) {
            root.busy = false;
            root.noteFailure(output, exitCode, label);
            root.refreshStatus();
            root.refreshAccount();
        }, 0, 120000);
    }

    // Exactly one of the three modes describes the live connection, so starting
    // any of them clears the other selectors. Quick connect owns neither
    // dropdown, so it clears both.
    function toggleConnection() {
        if (root.busy)
            return;
        root.selectedState = "";
        root.selectedCountry = "";
        if (root.connected)
            root.runProton("disconnect", "Disconnect", false);
        else
            root.runProton("connect", "Connect", true);
    }

    // Two steps: resolve the fastest server in the state, then connect to it by
    // name. There is no `connect --state`.
    //
    // Keyed on the code rather than the display name so the IPC verb works
    // before the dropdown list has loaded. `display` is cosmetic.
    function connectToStateCode(code, display) {
        if (!code || root.busy)
            return;
        root.selectedState = display;
        root.selectedCountry = "";
        root.busy = true;
        root.desiredConnected = true;
        root.lastError = "";
        Proc.runCommand("protonVpn-fastest", ["sh", "-c", "'" + root.statesScript + "' fastest " + code], function (output, exitCode) {
            const server = output.trim();
            if (exitCode !== 0 || !server) {
                root.busy = false;
                root.lastError = "No servers in " + (display || code);
                return;
            }
            root.runProton("connect '" + server + "'", "Connect", true);
        }, 0, 20000);
    }

    function connectToState(display) {
        root.connectToStateCode(root.stateCodes[display], display);
    }

    // stateCodes maps display name -> code, so a code lookup has to scan.
    function stateNameForCode(code) {
        for (const name in root.stateCodes) {
            if (root.stateCodes[name] === code)
                return name;
        }
        return "";
    }

    // Keyed on the code for the same reason as the state path: the IPC verb has
    // a code and may not have the country list loaded yet.
    function connectToCountryCode(code, display) {
        if (!code || root.busy)
            return;
        root.selectedCountry = display;
        root.selectedState = "";
        root.runProton("connect --country " + code, "Connect", true);
    }

    function connectToCountry(display) {
        root.connectToCountryCode(root.countryCodes[display], display);
    }

    function countryNameForCode(code) {
        for (const name in root.countryCodes) {
            if (root.countryCodes[name] === code)
                return name;
        }
        return "";
    }

    function openApp() {
        Quickshell.execDetached(["protonvpn-app"]);
        root.closePopout();
    }

    Component.onCompleted: {
        root.refreshStatus();
        root.refreshAccount();
        // Cheap (one local file read), and it makes the `state` IPC verb work
        // without the popout ever having been opened.
        root.refreshStates();
    }

    IpcHandler {
        target: "protonvpn"

        function popout(): string {
            root.triggerPopout();
            return "toggled";
        }

        function toggle(): string {
            root.toggleConnection();
            return root.connected ? "disconnecting" : "connecting";
        }

        function status(): string {
            return root.stateLabel + (root.serverName ? " • " + root.serverName : "");
        }

        function state(code: string): string {
            const upper = code.toUpperCase();
            root.connectToStateCode(upper, root.stateNameForCode(upper));
            return "connecting to " + upper;
        }

        function country(code: string): string {
            const upper = code.toUpperCase();
            root.connectToCountryCode(upper, root.countryNameForCode(upper));
            return "connecting to " + upper;
        }
    }

    Timer {
        interval: root.pollSeconds * 1000
        running: true
        repeat: true
        onTriggered: root.refreshStatus()
    }

    horizontalBarPill: Component {
        Item {
            implicitWidth: barIcon.width
            implicitHeight: barIcon.height
            anchors.verticalCenter: parent.verticalCenter

            ProtonVpnMark {
                id: barIcon
                anchors.centerIn: parent
                size: root.markSize
                markColor: root.connected ? Theme.primary : Theme.widgetIconColor
            }
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: barIconV.width
            implicitHeight: barIconV.height
            anchors.horizontalCenter: parent.horizontalCenter

            ProtonVpnMark {
                id: barIconV
                anchors.centerIn: parent
                size: root.markSize
                markColor: root.connected ? Theme.primary : Theme.widgetIconColor
            }
        }
    }

    popoutWidth: 400
    popoutContent: Component {
        PopoutComponent {
            headerText: "Proton VPN"
            detailsText: root.account || "Not signed in"
            showCloseButton: true

            Component.onCompleted: {
                root.refreshStatus();
                root.refreshAccount();
                root.refreshStates();
                root.refreshCountries();
            }

            headerActions: Component {
                DankActionButton {
                    iconName: "settings"
                    iconColor: Theme.surfaceVariantText
                    buttonSize: 28
                    tooltipText: "Plugin settings"
                    tooltipSide: "bottom"
                    onClicked: {
                        root.closePopout();
                        PopoutService.openSettingsWithTab("plugins");
                    }
                }
            }

            Column {
                width: parent.width
                spacing: Theme.spacingM

                // Connection card — the toggle connects to the fastest server
                // anywhere, which is Proton's own default `connect` behavior.
                StyledRect {
                    width: parent.width
                    height: 64
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.55)

                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.right: connControls.left
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        StyledText {
                            text: root.stateLabel
                            font.weight: Font.Medium
                        }

                        StyledText {
                            width: parent.width
                            elide: Text.ElideRight
                            text: root.lastError || root.serverName || "Fastest server"
                            font.pixelSize: Theme.fontSizeSmall
                            color: root.lastError ? Theme.error : Theme.surfaceVariantText
                        }
                    }

                    Item {
                        id: connControls
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        width: connToggle.width
                        height: parent.height

                        DankToggle {
                            id: connToggle
                            anchors.centerIn: parent
                            hideText: true
                            checked: root.toggleChecked
                            toggling: root.busy
                            onToggled: root.toggleConnection()
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: Theme.spacingS

                    StyledText {
                        text: "Connect through"
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        color: Theme.surfaceVariantText
                    }

                    StyledRect {
                        width: parent.width
                        // Rectangle doesn't size to its children, so track the
                        // Column's implicit height plus the padding on both sides.
                        height: connectThrough.implicitHeight + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: Theme.withAlpha(Theme.surfaceContainerHigh, 0.55)

                        Column {
                            id: connectThrough
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Theme.spacingM
                            spacing: Theme.spacingS

                            DankDropdown {
                                id: stateDropdown
                                width: parent.width
                                text: "US state"
                                description: "Fastest in the state"
                                options: root.stateOptions
                                emptyText: "Select a state"
                                // DankDropdown parents its popup to the popout's own
                                // overlay and flips it upward when it won't fit below,
                                // placing it at `triggerY - popupHeight - 4`. Anything
                                // much taller than this lands at a negative y and spills
                                // over the bar. The country dropdown sits lower, so it
                                // can afford more.
                                maxPopupHeight: 170
                                enabled: !root.busy
                                onValueChanged: value => root.connectToState(value)
                            }

                            // DankDropdown assigns its own `currentValue` on selection,
                            // which would clobber a plain binding and leave the widget
                            // stuck on a stale label once the other mode takes over. A
                            // Binding survives that write, so clearing the selection
                            // actually reaches the widget.
                            Binding {
                                target: stateDropdown
                                property: "currentValue"
                                value: root.selectedState
                            }

                            DankDropdown {
                                id: countryDropdown
                                width: parent.width
                                text: "Country"
                                description: "Fastest in the country"
                                options: root.countryOptions
                                enableFuzzySearch: true
                                emptyText: "Select a country"
                                // Same overlay constraint, plus 54px of search field
                                // inside the popup.
                                maxPopupHeight: 240
                                enabled: !root.busy
                                onValueChanged: value => root.connectToCountry(value)
                            }

                            Binding {
                                target: countryDropdown
                                property: "currentValue"
                                value: root.selectedCountry
                            }
                        }
                    }
                }

                DankButton {
                    width: parent.width
                    text: "Open Proton VPN"
                    buttonHeight: 36
                    onClicked: root.openApp()
                }
            }
        }
    }
}
