# Proton VPN

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) dankbar
widget for [Proton VPN](https://protonvpn.com). Shows connection state on the bar
and connects or disconnects from a popout.

Scope is deliberately narrow: **status, connect, disconnect**. Settings and
account management stay in Proton's own desktop app, which does them better,
except the kill switch.

## Prerequisites

- **DankMaterialShell `>= 1.4.0`** — the shell that loads this plugin.
- **`proton-vpn-cli` `>= 1.0.3`** — the engine, invoked as `protonvpn` on your
  `PATH`. Install it from Proton's official package repo for your distribution
  ([Fedora](https://protonvpn.com/support/official-linux-vpn-fedora/),
  [Debian/Ubuntu](https://protonvpn.com/support/official-linux-vpn-ubuntu/)).
  Earlier releases are unusable: 1.0.0 fails on import against current
  `api-core`.
- **NetworkManager (`nmcli`)** — used to read connection state.
- **`gdbus`** (glib2) — watches for Proton's app opening, which disables the
  widget's controls. Present on any GTK-era desktop.
- **`python3`** — runs the US-state server selection helper. Already present
  wherever `proton-vpn-cli` is, since that CLI is written in Python.

**Take the desktop app too.** `proton-vpn-gtk-app` is technically optional; the
plugin only ever launches it, and hides the "Open Proton VPN" button when it
isn't there. But Proton's official repos ship it alongside the CLI, the two share
credentials, and it's the escape hatch for account management and the settings
the CLI can't reach. Installing both is the path of least resistance.

**Signing in.** With the desktop app installed, sign in there once and the CLI
picks it up; nothing further is needed. Without it, run `protonvpn signin` in a
terminal, which prompts for a password and a 2FA token. A bar widget can't host
that prompt, which is why the popout never offers sign-in.

Keep the `proton-vpn-*` packages **version-locked as a set**. They all share
`python3-proton-vpn-api-core`, and skew between them breaks the CLI with a Python
import error rather than a clear message. Install the CLI and the desktop app
from the same source, and update them together.

## Bar

The Proton VPN mark, themed to follow DMS: neutral when disconnected, your accent
color when connected. No configuration.

It dims whenever the plugin can't act — no signed-in account, or Proton's app
holding the CLI — and adds a ⛔ badge only for the app case, since that one is
fixed by closing something.

## Popout

- **Account** — the signed-in Proton address, with buttons to manage the
  account (opens account.proton.me, since the CLI exposes nothing but the
  address) and to sign out. Signing out also drops any live connection.
  Signing *in* isn't offered: `protonvpn signin` prompts for a password and
  2FA token on a terminal, which a bar widget can't host. While signed out every
  control is disabled except "Open Proton VPN", which is the way back in.
  The address can't be read at all while the app is open, so if it was never
  known the row says so rather than guessing; it's re-read the instant the
  app exits.
  Detection is `info` printing `Account: 'None'` — it still exits 0, and
  `status` looks identical signed in or out, so neither the exit code nor the
  status line can be used.
- **Connection** — state, the connected server name, and a toggle. Connecting
  uses Proton's own fastest-server selection. The toggle flips immediately and
  the label reports the transition (`Connecting…` / `Disconnecting…`), since a
  connect takes several seconds.
- **Kill switch** — blocks internet if the tunnel drops. It's the one Proton
  setting the popout exposes, because it changes with where you are. The CLI
  can set only `off` and `standard`; the app's permanent mode stays in the app.
- **US state** — connects to the fastest server in the chosen state. Shown by
  default only when your locale is US (or has no country); the plugin's
  settings pane overrides that either way.
- **Country** — connects to the fastest server in the chosen country.
- **Open Proton VPN** — launches Proton's app for everything this widget
  deliberately doesn't do. While that app is open the widget's controls are
  disabled: the bar mark dims and gets a ⛔ badge, and the popout says so.

### Why States and Countries Work Differently

Countries are Proton's own feature: `protonvpn connect --country US` picks the
server, and refreshes a stale server cache while doing it.

States are not. Proton's API has no state tier — a state exists only inside the
server *name* (`US-CO#416`) — so `scripts/us-states.py` computes the pick locally
(lowest `Score` among enabled, in-tier servers, excluding Secure Core and Tor)
and the widget connects to that server by name. The list of states offered is
derived from the cache, so a state Proton doesn't serve simply never appears.

The tradeoff: a state pick is only as fresh as Proton's own server cache
(`$XDG_CACHE_HOME/Proton/VPN/serverlist.json`, defaulting to `~/.cache`), which
only a Proton command refreshes. A country pick is always current.

## Why `nmcli` and Not `protonvpn status`

The Proton CLI refuses to run while Proton's desktop app is open, and **exits 0
while refusing**:

```
$ protonvpn status
Error: Proton VPN desktop app is currently running
$ echo $?
0
```

Anything that shells out and checks the exit code reads that refusal as success.
This plugin instead treats the presence of the `proton0` device as the source of
truth, which is accurate no matter what else is running. Commands that *write*
(connect, disconnect) are matched on their message text, so a refusal surfaces in
the popout as "Quit the Proton VPN app first" rather than failing silently.

### While the App Is Open

Proton forbids the two running together because both write the same tunnel with
no shared state, so the CLI refuses *every* command — status, info, connect,
disconnect alike. The widget detects this by watching the app's session bus name
(`proton.vpn.app.gtk`) with `gdbus monitor`, which reports current ownership on
start and every change after.

Status keeps working throughout, because `nmcli` is unaffected. Only the controls
go dead, so the widget dims the mark, badges it, and disables the toggle and
dropdowns rather than letting you click into a guaranteed failure.

The corollary: **the plugin owns the connection, so don't leave the desktop app
running.** Quitting it tears down the tunnel, and it doesn't reconcile state on
launch. It ships no autostart entry, so this is already the default — just leave
its `connect_at_app_startup` and `start_app_minimized` settings off.

## Install

DMS loads plugins from `~/.config/DankMaterialShell/plugins/`. Either clone this
repo directly into that directory:

```sh
git clone git@github.com:robwilkerson/dms-protonvpn.git \
  ~/.config/DankMaterialShell/plugins/protonVpn
```

or clone it anywhere and symlink it in:

```sh
git clone git@github.com:robwilkerson/dms-protonvpn.git
ln -s "$(pwd)/dms-protonvpn" \
  ~/.config/DankMaterialShell/plugins/protonVpn
```

The directory name must match the plugin id, `protonVpn`. Then enable it on the
bar via Settings → Plugin Management, or add
`{"id":"protonVpn","enabled":true}` to a bar's widget list in `settings.json`.

## Uninstall

Remove it from the bar in Settings → Plugin Management (or delete its entry from
the bar's widget list in `settings.json`), then delete the plugin directory:

```sh
rm -rf ~/.config/DankMaterialShell/plugins/protonVpn
```

## IPC

```sh
dms ipc call protonvpn status     # "Connected • US-GA#491"
dms ipc call protonvpn toggle     # connect or disconnect
dms ipc call protonvpn popout     # toggle the popout
dms ipc call protonvpn state CO   # fastest server in a US state
dms ipc call protonvpn country DE # fastest server in a country
```

## Notes

- Connection state is polled every 5 seconds.
- The account address is read once and cached, since `protonvpn info` is
  unavailable whenever the desktop app is running.
- After editing a file the plugin *imports* (anything in `components/`),
  `dms ipc call plugins reload protonVpn` is not enough — DMS only cache-busts
  the entry file. Restart the shell with `systemctl --user restart dms.service`.

## License

MIT — see `LICENSE`.
