---
name: dms-bar-reorder-orphans-plugin-pills
description: Reordering DMS bar widgets can leave an unrelated plugin's pill loaded but painting nothing; `plugins reload <id>` fixes it, and `plugins list` gives no hint.
metadata:
  type: project
---

Changing the bar's widget list in DMS settings (adding a widget, dragging to
reorder) can orphan an **unrelated** plugin's bar pill. The pill keeps its
layout space but paints nothing at all — not faint, genuinely blank.

Observed 2026-08-26: adding the `protonVpn` widget to `rightWidgets` made
`dankscale`, the entry immediately after it, go blank.

**Why it misleads:** every diagnostic says the plugin is fine.
- `dms ipc call plugins list` → `[loaded]`, and `plugins status <id>` → `loaded`.
- The plugin's own IPC answers correctly (dankscale reported
  `Disconnected • 3/11 online`, operator fine, daemon active).
- **Zero** QML errors, warnings, or type failures in `journalctl --user`.
- Its `settings.json` entry is intact and `enabled: true`.
- `DankBar: Plugin loaded: <id>` was logged hours earlier and never unloaded —
  so the instance exists; it is just detached from rendering.

Every signal points at the blank plugin's own code, which is the trap. The newly
added widget is not at fault: disabling `protonVpn` left `dankscale` blank, which
is what ruled our code out.

**How to apply:** when a pill goes blank after a bar change, do not debug that
plugin's QML. Run `dms ipc call plugins reload <id>` — the forced
`unloaded` → `loaded` cycle rebuilds the instance and it renders immediately.
Suspect this first any time a pill is invisible while its IPC and logs are clean.

The mechanism inside DMS is unconfirmed; the correlation with a widget-list
rebuild is inference from timing, not something reproduced deliberately.
Related: [[protonvpn-cli-gui-mutual-exclusion]].
