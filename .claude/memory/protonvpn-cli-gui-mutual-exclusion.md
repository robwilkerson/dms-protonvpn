---
name: protonvpn-cli-gui-mutual-exclusion
description: Proton VPN's CLI refuses to run while its GTK app is alive and exits 0 while refusing; the two also diverge silently if you force it.
metadata:
  type: project
---

Proton VPN's official RPM stack (`proton-vpn-cli` + `proton-vpn-gtk-app`) cannot
be driven from both ends at once. With `protonvpn-app` running, every CLI command
prints `Error: Proton VPN desktop app is currently running` — and **exits 0**.

**Why:** guard at `proton/vpn/cli/__init__.py:133`, gated on
`ctx.obj.allow_gui_concurrency`. The off switch exists but is a Python parameter,
not a shell flag: `main(allow_concurrency=False, cli_args=None, controller=None)`.

**How to apply:** never parse the CLI's exit code to decide whether a Proton
command worked — a widget or script doing that reads success on a hard refusal.
Match the message, or use `nmcli con show --active` (look for `proton0`), which is
authoritative no matter what else is running.

Don't reach for `allow_concurrency` to dodge the guard. The divergence it prevents
is real and was observed here: after a CLI connect, the running GUI's tray still
offered "Connect" while `proton0` was up. Related: quitting the GUI tears down the
tunnel, and the GUI does not reconcile state on launch. The workable model — and
this plugin's core architectural assumption — is one writer, the CLI, with the GUI
launched only for settings and then quit. It ships no autostart entry, so
non-residency is already the default.

Found on x86_64 Fedora bootc after the Proton Flatpak → official-RPM migration,
while scoping this plugin.
