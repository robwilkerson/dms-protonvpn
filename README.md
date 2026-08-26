# Proton VPN

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) dankbar
widget for [Proton VPN](https://protonvpn.com). Shows connection state on the bar
and connects or disconnects from a popout.

Scope is deliberately narrow: **status, connect, disconnect**. Settings and
account management stay in Proton's own desktop app, which does them better.

## Prerequisites

- **DankMaterialShell `>= 1.4.0`** — the shell that loads this plugin.
- **`proton-vpn-cli`** — the engine. On Fedora it comes from Proton's official
  RPM repo. Sign in once with `protonvpn signin`.
- **NetworkManager (`nmcli`)** — used to read connection state.
- **`python3`** — runs the US-state server selection helper. Already present
  wherever `proton-vpn-cli` is, since that CLI is written in Python.

## Bar

The Proton VPN mark, themed to follow DMS: neutral when disconnected, your accent
color when connected. No configuration.

## Popout

- **Account** — the signed-in Proton address, as the subtitle.
- **Connection** — state, the connected server name, and a toggle. Connecting
  uses Proton's own fastest-server selection. The toggle flips immediately and
  the label reports the transition (`Connecting…` / `Disconnecting…`), since a
  connect takes several seconds.
- **US state** — connects to the fastest server in the chosen state.
- **Country** — connects to the fastest server in the chosen country.
- **Open Proton VPN** — launches Proton's app for everything this widget
  deliberately doesn't do.

### Why states and countries work differently

Countries are Proton's own feature: `protonvpn connect --country US` picks the
server, and refreshes a stale server cache while doing it.

States are not. Proton's API has no state tier — a state exists only inside the
server *name* (`US-CO#416`) — so `scripts/us-states.py` computes the pick locally
(lowest `Score` among enabled, in-tier servers, excluding Secure Core and Tor)
and the widget connects to that server by name. The list of states offered is
derived from the cache, so a state Proton doesn't serve simply never appears.

The tradeoff: a state pick is only as fresh as `~/.cache/Proton/VPN/serverlist.json`,
which only a Proton command refreshes. A country pick is always current.

## Why `nmcli` and not `protonvpn status`

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
