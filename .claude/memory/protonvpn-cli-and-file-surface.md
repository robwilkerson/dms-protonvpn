---
name: protonvpn-cli-and-file-surface
description: What the protonvpn CLI can and cannot do, its verified output shapes, and where Proton keeps its caches and settings on disk.
metadata:
  type: project
---

Verified on x86_64 Fedora bootc, 2026-08-26, against `proton-vpn-cli` 1.0.3.

**Commands:** `signin, signout, info, connect, disconnect, status, servers,
countries, cities, config`. Note `countries` needs an action: `countries list`.

**Output shapes** (no ANSI, no trailing whitespace; every one of these exits 0,
including the GUI-running refusal — see [[protonvpn-cli-gui-mutual-exclusion]]):

```
Status: Disconnected
```
```
Status: Connected
Server: US-GA#580 in Atlanta, United States
Load: 32%
Protocol: wireguard
```

`Server:` is `<name> in <city>, <country>`. `protonvpn info` prints
`Account: 'user@domain'`. `disconnect` prints `Disconnected.` with the period.
`connect` prints the server and new IP, preceded by
`Server list is outdated, updating...` when the cache is stale.

**`connect` targeting:** a bare `SERVER_NAME` argument (`US-CO#416`), or
`--country` (code or full name), `--city`, `--p2p`, `--securecore`, `--tor`,
`--random`. There is **no `--state`** — that's why state selection is computed
locally (see [[protonvpn-server-selection-replication]]).

**`config list` / `config set` covers 8 settings:** netshield, kill-switch,
port-forwarding, custom-dns, vpn-accelerator, moderate-nat, ipv6,
anonymous-crash-reports. **Missing versus the GUI: `protocol` and
`split_tunneling`.** Both live in `settings.json` below if ever needed, though
split tunneling is an app-path picker that belongs in the GUI. This is the
surface available if the popout ever exposes settings directly.

**Files:**
- `~/.cache/Proton/VPN/serverlist.json` — full server list (~18k logicals), plus
  top-level `MaxTier`, `ExpirationTime`, `LoadsExpirationTime`.
- `~/.cache/Proton/VPN/connection/connection_persistence.json` — current
  connection, including `server_name` and the NM `connection_id`.
- `~/.config/Proton/VPN/settings.json` — every VPN setting in one flat file,
  **but created lazily and removed on sign-out**. Observed absent entirely
  after `signout`. Never read it to learn a current setting; parse
  `protonvpn config list` instead.
- `~/.config/Proton/VPN/app-config.json` — app-level only: `tray_pinned_servers`,
  `connect_at_app_startup`, `start_app_minimized`. Written only once the user
  changes one. This plugin deliberately uses none of them.

**`signin` cannot be automated.** It prompts for the password via
`getpass.getpass` and then a 2FA token, so it needs a terminal — a bar widget
or script cannot host it. `signout` has no prompts and is safe to call
directly. This is why the plugin offers sign-out but not sign-in.

**How to apply:** read state from `nmcli`, not from these files or `status` — the
caches lag and the CLI is blocked while the GTK app runs. Use this as the map of
what's available when adding a feature, rather than re-deriving it.
