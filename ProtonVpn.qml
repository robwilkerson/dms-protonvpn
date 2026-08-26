// Proton VPN — DankMaterialShell dankbar widget.
//
// Bar: the Proton VPN mark. Themed neutral when disconnected, accent when
// connected.
//
// Popout: account subtitle plus a connection toggle. Settings and account
// management stay in Proton's own GTK app; this widget deliberately covers only
// status, connect, and disconnect.
//
// Connection state comes from `nmcli`, not from `protonvpn status`. The CLI
// refuses to run while Proton's GTK app is alive and *exits 0* while refusing,
// so it cannot be trusted as a state source. The presence of the `proton0`
// device is authoritative no matter what else is running.

import QtQuick
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

    // Optical size correction. The Proton glyph fills its viewBox edge to edge,
    // while the Material icons beside it on the bar carry internal padding, so
    // matching their nominal size makes ours read noticeably larger. Tune the
    // factor, not the base — `iconSize` already honors barThickness and iconScale.
    readonly property real markSize: Math.round(root.iconSize * 0.8)

    readonly property string stateLabel: connected ? "Connected" : "Disconnected"

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

    function toggleConnection() {
        if (root.busy)
            return;
        root.busy = true;
        root.lastError = "";
        const verb = root.connected ? "disconnect" : "connect";
        // Generous timeout: a connect can refresh the whole server list first.
        Proc.runCommand("protonVpn-toggle", ["sh", "-c", "protonvpn " + verb + " 2>&1"], function (output, exitCode) {
            root.busy = false;
            // Exit code is useless here — the GUI-running refusal also exits 0 —
            // so match the message instead.
            if (output.indexOf("desktop app is currently running") !== -1)
                root.lastError = "Quit the Proton VPN app first";
            else if (exitCode !== 0)
                root.lastError = "Proton VPN " + verb + " failed";
            root.refreshStatus();
            root.refreshAccount();
        }, 0, 120000);
    }

    Component.onCompleted: {
        root.refreshStatus();
        root.refreshAccount();
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

    popoutWidth: 360
    popoutContent: Component {
        PopoutComponent {
            headerText: "Proton VPN"
            detailsText: root.account || "Not signed in"
            showCloseButton: true

            Component.onCompleted: {
                root.refreshStatus();
                root.refreshAccount();
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

                // Connection card
                StyledRect {
                    width: parent.width
                    height: 64
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

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
                            text: root.lastError || root.serverName || "Proton VPN"
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
                            checked: root.connected
                            toggling: root.busy
                            onToggled: root.toggleConnection()
                        }
                    }
                }
            }
        }
    }
}
