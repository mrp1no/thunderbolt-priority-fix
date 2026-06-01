# thunderbolt-priority-fix

A macOS double-click utility for two (or more) Macs joined by a Thunderbolt cable. It blocks a peer Mac on Ethernet/Wi-Fi so the patched Mac reaches it over the Thunderbolt Bridge instead.

## Why

macOS file sharing discovery doesn't honour your interface preference. Even if you set the service order in System Settings with Thunderbolt Bridge first, Finder ignores it: when you click the other Mac in the sidebar it connects to whichever address Bonjour advertised, which is normally the Ethernet/Wi-Fi one. The only way to force Thunderbolt is to connect by its IP manually (Cmd-K → `smb://<thunderbolt-ip>`), which is clunky and breaks the normal point-and-click flow.

This fix removes that friction. By blocking the peer's LAN/Wi-Fi presence (its Bonjour advertisement, and at Level 2 its data path too), the address Finder discovers and connects to is the Thunderbolt one — so the ordinary "click the Mac in the sidebar and open a share" flow runs over Thunderbolt, with no manual IP entry.

## What it does

Double-click the `.command` file and it will:

1. Ask for the peer's Ethernet IPv4 and, optionally, its Wi-Fi IPv4.
2. Resolve the peer's MAC and any matching IPv6 addresses, so both IPv4 and IPv6 are covered.
3. Let you pick a blocking level (below) and write the matching pf firewall rules. The Thunderbolt Bridge subnet is never matched, so the peer stays reachable there.
4. Install the rules as a pf anchor plus a LaunchDaemon, so they reapply on every boot.
5. Flush the Bonjour and DNS caches.
6. Optionally verify, by inspecting the live SMB (port 445) socket, that the connection is on Thunderbolt.

Rules accumulate: running it again for another peer adds to the set instead of replacing it.

## Blocking levels

Level 1 — Bonjour only (default, lighter). Blocks just the peer's mDNS/Bonjour discovery (UDP 5353), so it stops being advertised on LAN/Wi-Fi and Finder browsing steers to Thunderbolt. Everything else (ping, SSH, screen sharing, web) stays reachable over the LAN. This controls discovery only — a connection opened directly to a LAN IP can still use Ethernet.

Level 2 — Full block (more invasive). Blocks mDNS and all traffic to the peer's LAN/Wi-Fi addresses, so it is reachable only over Thunderbolt. A hard guarantee, but it also cuts every other service to that Mac on Ethernet/Wi-Fi.

Levels can be mixed across runs; rules just accumulate in the same anchor.

## Requirements

macOS, an administrator account (the script uses `sudo`), and a working Thunderbolt Bridge between the Macs (cable connected, the Thunderbolt Bridge interface configured). Without the bridge, verification is skipped and you may simply lose LAN access to the peer.

## Usage

Make it executable if needed:

```bash
chmod +x thunderbolt-priority-fix.command
```

then double-click it in Finder (or run it from Terminal).

Enter the peer's IP address(es), pick a level, confirm, and supply your password when prompted. To undo everything, run the matching restore script.

## Warnings

- It changes system-level networking and persists across reboots: it edits the pf ruleset and installs a root LaunchDaemon.
- Level 2 blocks far more than Bonjour — it drops all traffic to the peer's LAN/Wi-Fi address, not just file sharing. Level 1 avoids this but only controls discovery, not the data path.
- It targets IP addresses, not devices. If the peer's IP changes (DHCP) the rules go stale or could hit an unrelated host that later gets that IP. Prefer static/reserved IPs.
- IPv6 coverage depends on the neighbour cache being populated at run time; otherwise some IPv6 addresses may be missed.
- It loads a global pf config and enables pf. If you already rely on pf (VPN kill-switch, other firewall) this can conflict — test first.
- If Thunderbolt isn't actually working, Level 2 can lock you out of the peer over LAN/Wi-Fi. Keep a way back in (the restore script, or manual cleanup below).
- macOS-only and version-sensitive. No warranty — review the source and use at your own risk.
