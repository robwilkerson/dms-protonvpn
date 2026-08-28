---
name: protonvpn-package-set
description: Why all three proton-vpn-* RPMs stay installed, and why they must be updated as a set.
metadata:
  type: project
---

Three packages, kept for three different reasons. Don't prune one without
reading this.

- **`proton-vpn-cli`** — required. It is this plugin's engine.
- **`proton-vpn-daemon`** — required by *packaging*, not by us.
  `rpm -q --requires proton-vpn-cli` lists it, so it can't be dropped while
  keeping the CLI. Functionally it only provides split tunneling; its bus name
  `me.proton.vpn.split_tunneling` is referenced nowhere outside its own
  client/service plus one `journalctl` call in the bug-report dialog, and the
  connect path degrades gracefully (`is_split_tunneling_available()` returns
  `bool(self._split_tunneling)`). It is a root-privileged `python3` service we
  never use.
- **`proton-vpn-gtk-app`** — optional to the packaging (it requires only
  `python3-proton-vpn-api-core`) **and optional to the plugin**. It is the escape
  hatch for account management and the settings the CLI can't reach, but the
  plugin only ever launches it: it checks `command -v protonvpn-app` at startup
  and hides the button when absent. Removable without breaking anything.

**Update them as a set.** All three sit on `python3-proton-vpn-api-core`, and
skew between them is what broke the old Flatpak: its bundled CLI 1.0.0 imported
`proton.vpn.core.connection`, which newer api-core only exposes as
`proton.vpn.core.vpnconnector`.

**How to apply:** the packages live in the bootc image, not here — a version bump
there is a blast-radius trigger for this repo, since the CLI surface and output
shapes this plugin parses can shift. Related:
[[protonvpn-cli-and-file-surface]].
