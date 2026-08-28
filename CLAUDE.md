# dms-protonvpn

A [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) dankbar
widget for Proton VPN. Scope is deliberately narrow: **status, connect,
disconnect**, plus state and country selection. Settings and account management
hand off to Proton's own GTK app. When a feature request would grow this past
those verbs, say so rather than building it.

## Stack

QML (Qt 6 / Quickshell) only. No build step, no package manager, no test
framework. The engine is the `protonvpn` CLI (`proton-vpn-cli >= 1.0.3`) from
Proton's official package repo; DMS `>= 1.4.0` loads the plugin. `just` runs the
dev loop and `python3` runs the one helper script.

## Structure

Mirrors the `dankscale` plugin (see Related Projects) — that layout is the
convention here, not an accident. What exists:

- `plugin.json` — manifest. Plugin id is `protonVpn`; the installed directory
  name must match the id.
- `ProtonVpn.qml` — bar pill plus `popoutContent`. The whole widget.
- `components/ProtonVpnMark.qml` — the Proton glyph.
- `scripts/us-states.py` — local state-tier server selection; see Hard
  constraints.
- `justfile` — the dev loop.

Conventional slots not yet used, which is where they go if they become needed: a
`ProtonVpnSettings.qml` pane at the root, and `services/` plus a root `qmldir`
for a singleton whose state must outlive the popout.

## Hard Constraints

These were learned by breaking things. Do not rediscover them.

- **Never branch on the `protonvpn` exit code.** It exits 0 while refusing to
  run because the GTK app is alive. Match on the message text, or use
  `nmcli con show --active` (look for `proton0`), which is authoritative
  regardless of what else is running. See `.claude/memory/`.
- **One writer: the CLI.** The GTK app is a settings tool the user launches and
  quits. Quitting it tears down the tunnel, and it does not reconcile state on
  launch. Never reach for `allow_concurrency` to dodge Proton's guard.
- **The logo is Proton's own single-path glyph**, drawn via `PathSvg` in
  `components/ProtonVpnMark.qml` and recolored through `markColor`. Never ship a
  *gradient* version of the mark — baked fills ignore the DMS theme, which is the
  whole reason this one is the single-path glyph. Owner's decision to use the real
  mark rather than a lookalike (dankscale ships a Tailscale-*style* mark instead).
- **Size bar content with `Theme.barIconSize(...)`**, never a fixed
  `Theme.iconSize` — the latter renders tiny at a non-default `iconScale`.
- **Colors come from `Theme.*`** (`Theme.surfaceText`, etc.). No literals.
- **Keep `proton-vpn-cli`, `proton-vpn-daemon`, and `proton-vpn-gtk-app`
  version-locked.** All three sit on `python3-proton-vpn-api-core`; skew is what
  broke the old Flatpak.
- **A settings pane must declare `pluginId: "protonVpn"` itself.** DMS injects
  the id into a bar widget (`WidgetHost` assigns it from the configured widget
  id), but `PluginSettings` declares it `required` and injects nothing. A wrong
  literal resolves the pane's settings against another plugin with no error
  anywhere. `just doctor` checks this.
- **Resolve Proton's cache through `XDG_CACHE_HOME`**, never a hardcoded
  `~/.cache`. Do not fall back to a Flatpak's sandbox cache: that directory
  outlives an uninstall, so reading it can silently serve stale server data from
  an app that is no longer installed.

## Dev Loop

No tests to run. Verify in the real shell. `just` wraps the whole loop; run
`just` for the list and `just bootstrap` on a new machine.

DMS loads plugins from `~/.config/DankMaterialShell/plugins/<id>`, never from
your clone. If that path is a real directory instead of a symlink to your working
tree, the bar runs an independent copy and **silently ignores every edit**, with
reload and restart both reporting success. `just develop start` makes the swap
and `just status` reports which copy is live; check it before debugging anything
that looks like a change not taking effect.

Adding the widget to a bar section is a settings-UI action — do not edit
`~/.config/DankMaterialShell/settings.json` directly.

`just doctor` checks the invariants that fail silently at runtime: manifest paths
that point at missing files, and `pluginId` literals that disagree with
`plugin.json`. Neither produces a runtime error, and the second is why a settings
pane must declare its own id (see Hard constraints).

**`plugins reload` only cache-busts the entry file.** DMS appends `?t=<ts>` to
`ProtonVpn.qml`, but not to anything it imports. So edits to `components/` or
`services/` are *not* picked up by a reload — the engine serves the cached type
and you get either `Cannot assign to non-existent property "…"` (new entry file,
stale component) or, worse, a silent render of the **old** code with no error at
all. After editing an imported file, restart the shell (`just restart`) rather
than reloading. A restart is also required after any `plugin.json` change or a
`just develop` swap, since neither is re-read by a hot reload.

Do not burn time on `plugins disable/enable` or `plugin-scan rescan` for this —
both were tried and neither clears the type cache. Worse, they can wedge the
plugin: `disable` returns `PLUGIN_DISABLE_FAILED`, `reload` returns `SUCCESS`
while the bar logs no load event, and `plugins list` still claims `[loaded]`.
Restart is the only reliable reset.

**A reload can leave two live instances.** The orphaned old one keeps its
`IpcHandler` registered on the `protonvpn` target with frozen state, so
`dms ipc call protonvpn …` may answer from the stale instance while the visible
popout belongs to the new one. This produces contradictory readings — a `toggle`
that reports `disconnecting` while the popout shows *Disconnected*, and no
connect happening. Restart the shell before trusting any IPC-driven test.

Trust the journal over `plugins list`, which will happily report `[loaded]` for a
plugin the bar has unloaded:
`journalctl --user -n 30 | grep -E 'DankBar: Plugin|component error'`. A healthy
load logs `DankBar: Plugin loaded: protonVpn` and nothing else.

Read the live Proton state from its own cache rather than guessing at shapes:
`serverlist.json` and `connection/connection_persistence.json`, both under
`$XDG_CACHE_HOME/Proton/VPN/` (defaulting to `~/.cache`).

Your `~/.config/DankMaterialShell` may itself be a symlink into a dotfiles tree.
If so, anything written under `plugins/` lands inside that repo's working tree,
which is worth knowing before a develop swap surprises you in `git status`.
`just develop` keeps its backup in `~/.cache/` for exactly this reason.

## Related Projects

Read on-demand; never preload at session start.

- **Reference** [`dankscale`](https://github.com/AvengeMedia/dankscale) — the
  structural model for this plugin. Consult it before inventing a pattern.
- **Reference** [`dms-caffeinate`](https://github.com/robwilkerson/dms-caffeinate)
  and [`dms-distro-menu`](https://github.com/robwilkerson/dms-distro-menu) — sibling
  DMS plugins by the same author. The justfile, README shape, `.gitignore`, and
  repo conventions here follow theirs.

Whatever builds your OS image owns the `proton-vpn-*` packages this plugin runs
on. Treat a Proton package version bump as a blast-radius event for this repo:
the CLI's subcommand surface and message text are what the widget parses, and it
matches on message text rather than exit codes (see Hard constraints).

## Integrations

- Repo: `git@github.com:robwilkerson/dms-protonvpn.git`. Issues live there; no
  Jira, no CI.
- Decisions that outlived their conversation are recorded in `README.md` (what
  the widget does and why) and `.claude/memory/` (the constraints behind it).
  Read those before re-deriving a decision from scratch.

## Working Notes

`SESSION_CONTEXT.md` is per-session crash-recovery scratch, gitignored and local
to whoever is working. It goes stale fast; treat it as a resumption aid, not a
source of truth. The scoping questions it once tracked are all resolved and the
answers live in `README.md` and `.claude/memory/`.

This file and everything under `.claude/` **are committed and shared**, matching
`dms-caffeinate`. Only `SESSION_CONTEXT.md` and `.claude/settings.local.json`
stay ignored, since the first is per-session and the second is per-machine
permission state. Write accordingly: no host names, no credentials, nothing that
only makes sense on one box.
