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

    // The GTK app is optional: this plugin only needs the CLI. It's the escape
    // hatch for account management and the settings the CLI can't reach, so when
    // it isn't installed the button that opens it is simply absent. Checked once
    // at startup — packages don't come and go mid-session.
    property bool appInstalled: false

    // Proton's GTK app refuses the CLI *every* command while it is merely
    // running — status, info, connect, disconnect alike — so while it's up this
    // widget can still report state (nmcli is unaffected) but can't change it.
    property bool appRunning: false

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

    readonly property bool signedIn: account !== ""

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
    // `force` re-asks even when an address is already cached — needed because the
    // cache is persisted, so without it a sign-out that happened elsewhere would
    // leave the old address on screen forever.
    //
    // Signed out, `info` prints `Account: 'None'` and still exits 0, so the test
    // is whether the captured value looks like an address at all.
    function refreshAccount(force) {
        // Asking while the app is open is guaranteed to fail, so don't — and
        // don't let that failure read as being signed out.
        if (root.appRunning)
            return;
        if (root.account && !force)
            return;
        Proc.runCommand("protonVpn-info", ["sh", "-c", "protonvpn info 2>&1"], function (output, exitCode) {
            const m = output.match(/Account:\s*'([^']+)'/);
            const value = m && m[1].indexOf("@") !== -1 ? m[1] : "";
            root.account = value;
            if (root.pluginService)
                root.pluginService.savePluginData(root.pluginId, "account", value);
        }, 0, 20000);
    }

    function checkAppInstalled() {
        Proc.runCommand("protonVpn-app-installed", ["sh", "-c", "command -v protonvpn-app >/dev/null"], function (output, exitCode) {
            root.appInstalled = exitCode === 0;
        });
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
        else if (output.indexOf("Please sign in") !== -1) {
            root.lastError = "Sign in to Proton VPN first";
            root.account = "";
            if (root.pluginService)
                root.pluginService.savePluginData(root.pluginId, "account", "");
        }
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

    function signOut() {
        // Unlike `signin`, which needs an interactive password and 2FA prompt,
        // `signout` is non-interactive, so the plugin can do it directly. It also
        // terminates any live connection, which Proton handles for us.
        if (root.busy || root.appRunning)
            return;
        root.busy = true;
        root.desiredConnected = false;
        root.lastError = "";
        Proc.runCommand("protonVpn-signout", ["sh", "-c", "protonvpn signout 2>&1"], function (output, exitCode) {
            root.busy = false;
            root.noteFailure(output, exitCode, "Sign out");
            if (output.indexOf("signed out") !== -1) {
                root.account = "";
                if (root.pluginService)
                    root.pluginService.savePluginData(root.pluginId, "account", "");
            }
            root.refreshStatus();
        }, 0, 60000);
    }

    // Account management is web-only; the CLI exposes nothing but the address.
    function manageAccount() {
        Quickshell.execDetached(["xdg-open", "https://account.proton.me"]);
        root.closePopout();
    }

    function openApp() {
        Quickshell.execDetached(["protonvpn-app"]);
        root.closePopout();
    }

    onPluginDataChanged: {
        if (!root.account && pluginData && pluginData.account)
            root.account = pluginData.account;
    }

    Component.onCompleted: {
        if (pluginData && pluginData.account)
            root.account = pluginData.account;
        root.refreshStatus();
        root.refreshAccount(true);
        root.checkAppInstalled();
        // Cheap (one local file read), and it makes the `state` IPC verb work
        // without the popout ever having been opened.
        root.refreshStates();
    }

    // Why this exists: Proton deliberately forbids the app and the CLI running
    // together, because both write the same single tunnel with no shared state —
    // permitting it means split brain (observed: the app's tray offering
    // "Connect" over a live CLI tunnel). So while the app is open the CLI refuses
    // *every* command, and exits 0 while refusing. This plugin is a CLI front
    // end, so an open app disables all of it.
    //
    // The app's session bus name is the tell. `gdbus monitor` prints current
    // ownership when it starts and again on every change, so it needs no
    // separate startup probe:
    //   "...is owned by :1.848"     -> running
    //   "...does not have an owner" -> not running
    Process {
        id: appWatcher

        running: true
        command: ["gdbus", "monitor", "--session", "--dest", "proton.vpn.app.gtk"]

        stdout: SplitParser {
            onRead: line => {
                if (line.indexOf("is owned by") !== -1)
                    root.appRunning = true;
                else if (line.indexOf("does not have an owner") !== -1)
                    root.appRunning = false;
            }
        }

        // Nothing else knows this state, so a silent death would freeze it.
        // Restart on a delay so a command that fails instantly can't spin.
        onExited: watcherRestart.restart()
    }

    Timer {
        id: watcherRestart
        interval: 2000
        onTriggered: appWatcher.running = true
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
                // Dimmed whenever the plugin can't act — the app owning the CLI,
                // or no signed-in account. The badge is reserved for the app case,
                // since that one is resolved by closing something.
                opacity: root.appRunning || !root.signedIn ? 0.45 : 1
            }

            DankIcon {
                visible: root.appRunning
                name: "block"
                filled: true
                size: barIcon.size * 0.55
                color: Theme.error
                anchors.right: barIcon.right
                anchors.bottom: barIcon.bottom
                anchors.rightMargin: -2
                anchors.bottomMargin: -2
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
                // Dimmed whenever the plugin can't act — the app owning the CLI,
                // or no signed-in account. The badge is reserved for the app case,
                // since that one is resolved by closing something.
                opacity: root.appRunning || !root.signedIn ? 0.45 : 1
            }

            DankIcon {
                visible: root.appRunning
                name: "block"
                filled: true
                size: barIconV.size * 0.55
                color: Theme.error
                anchors.right: barIconV.right
                anchors.bottom: barIconV.bottom
                anchors.rightMargin: -2
                anchors.bottomMargin: -2
            }
        }
    }

    popoutWidth: 400
    popoutContent: Component {
        PopoutComponent {
            headerText: "Proton VPN"
            detailsText: ""
            showCloseButton: true

            Component.onCompleted: {
                root.refreshStatus();
                root.refreshAccount(true);
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

                // Account row: glyph + address, with the two account actions.
                Item {
                    width: parent.width
                    height: 32

                    DankIcon {
                        id: acctGlyph
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        name: "account_circle"
                        size: 20
                        color: Theme.surfaceVariantText
                    }

                    StyledText {
                        anchors.left: acctGlyph.right
                        anchors.leftMargin: Theme.spacingS
                        anchors.right: acctActions.left
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: root.account || "Not signed in"
                        color: root.account ? Theme.surfaceText : Theme.surfaceVariantText
                    }

                    Row {
                        id: acctActions
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXS
                        visible: root.account !== ""

                        DankActionButton {
                            iconName: "open_in_new"
                            iconColor: Theme.surfaceVariantText
                            buttonSize: 28
                            tooltipText: "Manage account"
                            tooltipSide: "bottom"
                            // A browser link, so it works even while the app owns
                            // the CLI.
                            onClicked: root.manageAccount()
                        }

                        DankActionButton {
                            iconName: "logout"
                            iconColor: Theme.surfaceVariantText
                            buttonSize: 28
                            tooltipText: "Sign out"
                            tooltipSide: "bottom"
                            enabled: !root.busy && !root.appRunning && root.signedIn
                            onClicked: root.signOut()
                        }
                    }
                }

                StyledText {
                    width: parent.width
                    visible: !root.signedIn && !root.appRunning
                    wrapMode: Text.WordWrap
                    // The account row already says "Not signed in"; this line is
                    // only here to say what to do about it.
                    text: root.appInstalled
                        ? "Sign in with the Proton VPN app below, or run `protonvpn signin <user>`."
                        : "Run `protonvpn signin <user>` in a terminal to sign in."
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.error
                    leftPadding: Theme.spacingS
                }

                StyledText {
                    width: parent.width
                    visible: root.appRunning
                    wrapMode: Text.WordWrap
                    text: "The Proton VPN app must be closed to use this plugin."
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.error
                    // Line up with the account line above, which PopoutComponent
                    // insets by spacingS. The cards below sit flush at 0.
                    leftPadding: Theme.spacingS
                }

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
                            enabled: !root.appRunning && root.signedIn
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
                                enabled: !root.busy && !root.appRunning && root.signedIn
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
                                enabled: !root.busy && !root.appRunning && root.signedIn
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
                    visible: root.appInstalled
                    // Already open — nothing to launch.
                    enabled: !root.appRunning
                    onClicked: root.openApp()
                }
            }
        }
    }
}
