---
name: dms-plugin-api-source
description: DMS ships its QML source on disk under /usr/share/quickshell/dms; read it to settle plugin API questions instead of inferring them.
metadata:
  type: reference
---

DankMaterialShell installs its own QML, so the plugin API is readable source, not
a black box. It lives under `/usr/share/quickshell/dms/Modules/`. Read it rather
than inferring behaviour from how other plugins happen to be written.

Three files answer most questions:

- `Modules/Plugins/PluginComponent.qml` — the base type every widget extends.
  Every property a plugin may set is declared here, with defaults.
- `Modules/DankBar/WidgetHost.qml` — how a bar widget is instantiated. It
  **assigns `pluginId`** from the configured widget id (splitting `id:variant`),
  along with `variantId`, `variantData`, and `pluginService`.
- `Modules/Plugins/PluginSettings.qml` — the settings pane base. It declares
  `pluginId` as a **`required property`** and nothing injects it.

That asymmetry is the practical payoff: a bar widget's `pluginId` literal is
redundant because the host overwrites it, while a settings pane must carry its own
or fail to construct. Copying another plugin's arrangement without reading these
files makes the two look like one rule.

**How to apply:** when unsure whether DMS sets a property or the plugin must,
grep these Modules before writing code or filing a bug. `just doctor` enforces the
`pluginId` half of it. Related: [[dms-bar-reorder-orphans-plugin-pills]].
