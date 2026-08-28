---
name: protonvpn-server-selection-replication
description: How to reproduce Proton's own "fastest server" pick from serverlist.json, and the two things that make a hand-rolled filter silently wrong.
metadata:
  type: project
---

Proton's `ServerList.get_fastest_in_country` can be replicated exactly from
`~/.cache/Proton/VPN/serverlist.json` — validated 2026-08-26, where the filter
picked `US-GA#580` at score 1.6874, the same server `protonvpn connect` chose.

Filter: `Status == 1`, `Tier <= MaxTier`, `(Features & 3) == 0`, then
`min(key=Score)`. Lower `Score` is faster.

**Why the two easy mistakes are silent:**

1. `Features` is a **raw int bitmask** in the JSON, and the enum is
   `SECURE_CORE=1, TOR=2, P2P=4, STREAMING=8, IPV6=16`
   (`proton/vpn/session/servers/types.py`). Guessing `TOR=4` inverts the intent:
   it excludes every P2P server — which is most of the DC and CO fleet, so a
   location returns "no servers" or a lone TOR box — while admitting the TOR
   servers you meant to drop. Nothing errors.
2. `user_tier` is the cache's own top-level **`MaxTier`** key, not a value from
   the account API.

**`Score` and `Load` go stale.** Nothing refreshes them but a Proton command;
`protonvpn connect` prints "Server list is outdated, updating..." and does it
mid-connect. A stale cache was the whole explanation for an earlier apparent
filter mismatch (`#481` vs `#567`) — the filter was fine. So check the top-level
`LoadsExpirationTime` / `ExpirationTime` before trusting a locally-computed pick,
or delegate the choice to `protonvpn connect`.

**How to apply:** read the constants out of
`/usr/lib/python3.*/site-packages/proton/vpn/session/servers/` rather than
re-deriving them, and treat any local "fastest" answer as only as fresh as the
cache. Related: [[protonvpn-cli-gui-mutual-exclusion]].
