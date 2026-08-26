// Proton VPN — DankMaterialShell dankbar widget.
//
// Bar: the Proton VPN mark. Themed neutral when disconnected, accent when
// connected.
//
// Connection state comes from `nmcli`, not from `protonvpn status`. The CLI
// refuses to run while Proton's GTK app is alive and *exits 0* while refusing,
// so it cannot be trusted as a state source. The presence of the `proton0`
// device is authoritative no matter what else is running.

import QtQuick
import qs.Common
import qs.Modules.Plugins
import "./components"

PluginComponent {
    id: root

    readonly property int pollSeconds: parseInt(pluginData.pollSeconds) || 5

    property bool connected: false

    // Optical size correction. The Proton glyph fills its viewBox edge to edge,
    // while the Material icons beside it on the bar carry internal padding, so
    // matching their nominal size makes ours read noticeably larger. Tune the
    // factor, not the base — `iconSize` already honors barThickness and iconScale.
    readonly property real markSize: Math.round(root.iconSize * 0.8)

    function refreshStatus() {
        Proc.runCommand("protonVpn-status", ["sh", "-c", "nmcli -t -f DEVICE connection show --active"], function (output, exitCode) {
            if (exitCode !== 0) {
                // Leave the prior reading; a stale pill beats a flapping one.
                return;
            }
            root.connected = output.split("\n").some(line => line.trim() === "proton0");
        });
    }

    Component.onCompleted: root.refreshStatus()

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
}
