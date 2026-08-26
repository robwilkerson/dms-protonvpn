#!/usr/bin/env python3
"""US-state server selection for the Proton VPN dankbar widget.

Proton's API has no notion of a US state: `connect --country` works and
`connect --city` works, but state lives only in the server *name* (`US-CO#416`).
So state selection has to be computed here and handed to `protonvpn connect` as
an explicit server name.

Usage:
    us-states.py list             # "CO:Colorado" per state that has servers
    us-states.py fastest CO       # "US-CO#416"

The filter replicates `ServerList.get_fastest_in_country` from
proton/vpn/session/servers/logicals.py. Getting it wrong is silent rather than
loud, so the details matter:

  * `Features` is a raw int bitmask and the enum is
    SECURE_CORE=1, TOR=2, P2P=4, STREAMING=8, IPV6=16.
    Excluding SECURE_CORE|TOR is `& 3`. Using `& 5` instead drops every P2P
    server -- which is most of DC and CO -- while admitting the TOR ones.
  * the user's tier is the cache's own top-level `MaxTier`.
  * `enabled` is exactly `Status == 1`.
  * fastest is `min(Score)`; lower is faster.

Caveat: `Score` and `Load` in the cache go stale, and only a Proton command
refreshes them. A pick here is only as fresh as the cache.
"""

import json
import os
import re
import sys

CACHE = os.path.expanduser("~/.cache/Proton/VPN/serverlist.json")

EXCLUDE_FEATURES = 1 | 2  # SECURE_CORE | TOR

STATE_NAMES = {
    "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas",
    "CA": "California", "CO": "Colorado", "CT": "Connecticut",
    "DC": "Washington DC", "DE": "Delaware", "FL": "Florida", "GA": "Georgia",
    "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois", "IN": "Indiana",
    "IA": "Iowa", "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana",
    "ME": "Maine", "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan",
    "MN": "Minnesota", "MS": "Mississippi", "MO": "Missouri", "MT": "Montana",
    "NE": "Nebraska", "NV": "Nevada", "NH": "New Hampshire",
    "NJ": "New Jersey", "NM": "New Mexico", "NY": "New York",
    "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio",
    "OK": "Oklahoma", "OR": "Oregon", "PA": "Pennsylvania",
    "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota",
    "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont",
    "VA": "Virginia", "WA": "Washington", "WV": "West Virginia",
    "WI": "Wisconsin", "WY": "Wyoming",
}

NAME_RE = re.compile(r"^US-([A-Z]{2})#")


def load():
    with open(CACHE) as fh:
        data = json.load(fh)
    return data["LogicalServers"], data.get("MaxTier", 0)


def available(server, tier):
    return (
        server.get("Status") == 1
        and server.get("Tier", 99) <= tier
        and (server.get("Features", 0) & EXCLUDE_FEATURES) == 0
    )


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: us-states.py list | fastest <CODE>")

    mode = sys.argv[1]

    try:
        servers, tier = load()
    except (OSError, ValueError, KeyError):
        # No cache yet, or unreadable. Print nothing; the caller degrades to an
        # empty dropdown rather than showing a wrong answer.
        return 1

    if mode == "list":
        codes = set()
        for server in servers:
            match = NAME_RE.match(server.get("Name", ""))
            if match and available(server, tier):
                codes.add(match.group(1))
        for code in sorted(codes, key=lambda c: STATE_NAMES.get(c, c)):
            print(f"{code}:{STATE_NAMES.get(code, code)}")
        return 0

    if mode == "fastest":
        if len(sys.argv) < 3:
            sys.exit("usage: us-states.py fastest <CODE>")
        code = sys.argv[2].upper()
        candidates = [
            s for s in servers
            if NAME_RE.match(s.get("Name", ""))
            and NAME_RE.match(s["Name"]).group(1) == code
            and available(s, tier)
        ]
        if not candidates:
            return 1
        print(min(candidates, key=lambda s: s["Score"])["Name"])
        return 0

    sys.exit(f"unknown mode: {mode}")


if __name__ == "__main__":
    sys.exit(main())
