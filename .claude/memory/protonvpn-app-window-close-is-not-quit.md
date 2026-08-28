---
name: protonvpn-app-window-close-is-not-quit
description: Closing the Proton VPN app's window leaves the process alive in the tray, still owning its bus name and still blocking the CLI.
metadata:
  type: project
---

Closing the Proton VPN app's window does **not** quit it. The process keeps
running with a tray icon, so from the plugin's point of view nothing changed:
it still owns `proton.vpn.app.gtk` on the session bus, and the CLI still refuses
every command. Quitting requires the tray icon's menu (or killing the PID).

Verified 2026-08-26: after closing the window, `pgrep -f protonvpn-app` still
found PID 381746, `busctl --user list` still showed both `proton.vpn.app.gtk` and
its `org.kde.StatusNotifierItem-…` name, and `protonvpn info` still returned the
"desktop app is currently running" refusal.

**Why it matters:** this looks exactly like a broken plugin. The user closes the
window, expects the widget to come back to life, and it stays greyed out with the
⛔ badge. Two separate bug reports this session traced back to this, and the
plugin's own copy made it worse by saying the app must be "closed" — which is
precisely what had been done. That string now says *quit*, and where from.

**How to apply:** when the widget insists the app is running, believe it and
check `pgrep -f '[/]usr/bin/protonvpn-app'` before suspecting the watcher. The
detection is a bus-name watch, which is authoritative — a false positive there
is far less likely than a window that was merely hidden.
Related: [[protonvpn-cli-gui-mutual-exclusion]].
