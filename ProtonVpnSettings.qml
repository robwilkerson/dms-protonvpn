import QtQuick
import qs.Common
import qs.Modules.Plugins

PluginSettings {
    id: root

    // Required here, unlike on the bar widget: nothing injects it into a
    // settings pane, and a wrong literal reads another plugin's settings.
    pluginId: "protonVpn"

    ToggleSetting {
        settingKey: "showStatePicker"
        label: "Show US State Picker"
        description: "Connect to the fastest server in a US state. Hiding it leaves the country picker."
        // Unset, this follows the locale, matching the widget's own fallback in
        // ProtonVpn.qml. A locale with no country counts as US.
        defaultValue: {
            const country = Qt.locale().name.split("_")[1];
            return !country || country === "US";
        }
    }
}
