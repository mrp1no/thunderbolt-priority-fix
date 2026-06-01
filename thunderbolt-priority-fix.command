#!/bin/bash
#
# thunderbolt-priority-fix.command
# ------------------------------------------------------------------
# Blocks a peer Mac on Ethernet/Wi-Fi so THIS Mac discovers and/or
# connects to it over Thunderbolt. You choose how aggressive:
#   Level 1 (default) - block only the peer's Bonjour/mDNS discovery.
#   Level 2 (invasive) - also block ALL LAN/Wi-Fi traffic to the peer.
#
# Double-click to run. You'll be asked for your login password (sudo).
# Re-run it for additional peers - rules accumulate.
# ------------------------------------------------------------------

ANCHOR="/etc/pf.anchors/force-thunderbolt"
CONF="/etc/pf-force-thunderbolt.conf"
PLIST="/Library/LaunchDaemons/org.local.force-thunderbolt.plist"

pause() { echo; echo "Press Return to close."; read -r _; }

# normalise a MAC so arp's and ndp's formatting (leading zeros) compare equal
norm_mac() { printf '%s' "$1" | tr 'A-Z' 'a-z' | sed -E 's/(^|:)0([0-9a-f])/\1\2/g'; }

# interactive check: open the peer in Finder, confirm the live socket is on Thunderbolt
verify_thunderbolt() {
  local tbif tb4 tb6 local remote stripped pass other ans again
  tbif=$(networksetup -listallhardwareports 2>/dev/null | awk '/Thunderbolt Bridge/{getline; print $2}')
  [ -z "$tbif" ] && tbif="bridge0"
  tb4=$(ifconfig "$tbif" 2>/dev/null | awk '/inet /{print $2; exit}')
  tb6=$(ifconfig "$tbif" 2>/dev/null | awk '/inet6 fe80/{sub(/%.*/,"",$2); print $2; exit}')

  echo
  echo "---------------------------------------------------"
  echo " Verify the live connection uses Thunderbolt ($tbif)"
  echo "---------------------------------------------------"
  if [ "$LEVEL" = 1 ]; then
    echo "(Level 1 only blocks discovery, so an existing connection made by a"
    echo " LAN IP may still show as 'NOT over Thunderbolt' - that's expected.)"
  fi
  if [ -z "$tb4" ] && [ -z "$tb6" ]; then
    echo "No Thunderbolt Bridge address found - is the cable connected and the"
    echo "Thunderbolt Bridge configured? Skipping verification."
    return 0
  fi

  while true; do
    echo
    echo "In Finder, open the OTHER Mac (sidebar, or Cmd-K by its name) and open"
    echo "one of its shared folders so a connection is established."
    printf "Press Return when the share is open (or 's' to skip): "; read -r ans
    case "$ans" in s|S) echo "Skipped."; return 0 ;; esac

    pass=0; other=0
    while read -r local remote; do
      [ -z "$local" ] && continue
      stripped=$(printf '%s' "$local" | sed 's/\.[0-9]*$//')        # drop the .port
      if [ "$stripped" = "$tb4" ] || { [ -n "$tb6" ] && [ "${tb6#$stripped}" != "$tb6" ]; }; then
        echo "   $local  ->  $remote   [Thunderbolt OK]"
        pass=1
      else
        echo "   $local  ->  $remote   [NOT over Thunderbolt]"
        other=1
      fi
    done < <(netstat -an | awk '$1 ~ /^tcp/ && $5 ~ /\.445$/ && $6=="ESTABLISHED"{print $4" "$5}')

    if [ "$pass" = 0 ] && [ "$other" = 0 ]; then
      echo "   (no active file-sharing connection found yet)"
      printf "Try again? [Y/n] "; read -r again
      case "$again" in n|N) echo "Verification incomplete."; return 0 ;; *) continue ;; esac
    fi
    echo
    if [ "$pass" = 1 ] && [ "$other" = 0 ]; then
      echo "RESULT: PASS - file sharing is running over Thunderbolt."
    elif [ "$pass" = 1 ]; then
      echo "RESULT: PASS (with note) - a Thunderbolt connection is active; any"
      echo "        'NOT over Thunderbolt' line above is likely a different server."
    else
      echo "RESULT: NOT over Thunderbolt - the connection is using another"
      echo "        interface. Double-check the addresses you entered."
    fi
    return 0
  done
}

echo "==================================================="
echo " Force Thunderbolt - block a peer Mac on LAN/Wi-Fi"
echo "==================================================="
echo
echo "Enter the peer Mac's LAN IP address(es). Leave blank to skip."
printf "  Ethernet IPv4 (e.g. 192.168.118.60): "; read -r ETH_IP
printf "  Wi-Fi IPv4    (optional)           : "; read -r WIFI_IP

NEW=""

add_ip() {   # $1 = IPv4 of the peer; also finds its IPv6 neighbours
  local ip="$1" iface mac target addr lladdr rest
  [ -z "$ip" ] && return 0
  NEW="$NEW
$ip"
  iface=$(route -n get "$ip" 2>/dev/null | awk '/interface:/{print $2}')
  ping  -c1 -t1 "$ip" >/dev/null 2>&1                       # prime ARP cache
  [ -n "$iface" ] && ping6 -c2 "ff02::1%$iface" >/dev/null 2>&1   # prime IPv6 neighbour cache
  mac=$(arp -n "$ip" 2>/dev/null | awk '{print $4}' \
        | grep -Ei '^([0-9a-f]{1,2}:){5}[0-9a-f]{1,2}$' | head -1)
  [ -z "$mac" ] && { echo "  (note: no MAC found for $ip - blocking IPv4 only)"; return 0; }
  target=$(norm_mac "$mac")
  while read -r addr lladdr rest; do
    case "$addr" in *:*) ;; *) continue ;; esac            # IPv6 only
    [ "$(norm_mac "$lladdr")" = "$target" ] && NEW="$NEW
${addr%%\%*}"
  done < <(ndp -an 2>/dev/null | sed 1d)
}

add_ip "$ETH_IP"
add_ip "$WIFI_IP"

NEW=$(printf '%s\n' "$NEW" | grep -v '^$' | sort -u)
if [ -z "$NEW" ]; then echo; echo "No addresses entered. Nothing to do."; pause; exit 1; fi

# --- choose how aggressively to block ------------------------------
echo
echo "Choose the blocking level for these peers on Ethernet/Wi-Fi:"
echo
echo "  [1] Bonjour only  (lighter, default)"
echo "      Blocks only the peers' mDNS/Bonjour discovery (UDP 5353). They"
echo "      stop being advertised on LAN/Wi-Fi, so Finder browsing steers to"
echo "      Thunderbolt. Everything else (ping, SSH, screen sharing, etc.)"
echo "      stays reachable over LAN. NOTE: this controls DISCOVERY only - a"
echo "      connection opened directly to a LAN IP can still use Ethernet."
echo
echo "  [2] Full block    (*** MORE INVASIVE ***)"
echo "      Blocks mDNS AND all traffic to the peers' LAN/Wi-Fi addresses,"
echo "      so they are reachable ONLY over Thunderbolt. This also cuts every"
echo "      other service (SSH, screen sharing, web UI, printing, ...) to"
echo "      those Macs on Ethernet/Wi-Fi."
echo
printf "Level [1/2] (default 1): "; read -r LEVEL
case "$LEVEL" in 2) LEVEL=2 ;; *) LEVEL=1 ;; esac

echo
if [ "$LEVEL" = 2 ]; then
  echo "LEVEL 2 (FULL BLOCK - invasive): the following addresses will have"
  echo "Bonjour AND all LAN/Wi-Fi traffic blocked (reachable only via Thunderbolt):"
else
  echo "LEVEL 1 (Bonjour only): the following addresses will have their"
  echo "mDNS/Bonjour discovery blocked on LAN/Wi-Fi (other LAN services stay up):"
fi
printf '   %s\n' $NEW
echo
printf "Proceed? [y/N] "; read -r YN
case "$YN" in y|Y) ;; *) echo "Aborted."; pause; exit 1 ;; esac

gen_rules() {   # emit pf rules for every address in $1, honouring $LEVEL
  local a fam
  for a in $1; do
    case "$a" in *:*) fam="inet6" ;; *) fam="inet" ;; esac
    # always block the peer's Bonjour/mDNS discovery on LAN/Wi-Fi
    echo "block drop in quick $fam proto udp from $a port 5353 to any"
    # Level 2 additionally blocks ALL data to the peer on LAN/Wi-Fi
    if [ "$LEVEL" = 2 ]; then
      echo "block return out quick $fam from any to $a"
    fi
  done
}

TMP=$(mktemp); OUT=$(mktemp)
[ -f "$ANCHOR" ] && grep -E '^block ' "$ANCHOR" >> "$TMP" 2>/dev/null   # keep prior peers
gen_rules "$NEW" >> "$TMP"
{
  echo "# Generated by thunderbolt-priority-fix.command - do not edit by hand."
  echo "# Blocks listed peers' Bonjour (mDNS); full-block entries also drop all"
  echo "# their LAN/Wi-Fi traffic. Reach those peers over Thunderbolt instead."
  sort -u "$TMP"
} > "$OUT"

echo
echo "Installing... (enter your password if prompted)"
sudo mkdir -p /etc/pf.anchors
sudo cp "$OUT" "$ANCHOR"
rm -f "$TMP" "$OUT"

sudo tee "$CONF" >/dev/null <<'EOF'
scrub-anchor "com.apple/*"
nat-anchor "com.apple/*"
rdr-anchor "com.apple/*"
dummynet-anchor "com.apple/*"
anchor "force-thunderbolt"
load anchor "force-thunderbolt" from "/etc/pf.anchors/force-thunderbolt"
anchor "com.apple/*"
load anchor "com.apple" from "/etc/pf.anchors/com.apple"
EOF

sudo tee "$PLIST" >/dev/null <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>org.local.force-thunderbolt</string>
	<key>RunAtLoad</key>
	<true/>
	<key>ProgramArguments</key>
	<array>
		<string>/sbin/pfctl</string>
		<string>-E</string>
		<string>-f</string>
		<string>/etc/pf-force-thunderbolt.conf</string>
	</array>
	<key>StandardOutPath</key>
	<string>/var/log/force-thunderbolt.log</string>
	<key>StandardErrorPath</key>
	<string>/var/log/force-thunderbolt.log</string>
</dict>
</plist>
EOF
sudo chown root:wheel "$PLIST"
sudo chmod 644 "$PLIST"

if ! sudo pfctl -vnf "$CONF" >/dev/null 2>&1; then
  echo "ERROR: pf config failed to parse - no changes activated."; pause; exit 1
fi

sudo launchctl unload "$PLIST" 2>/dev/null
sudo launchctl load -w "$PLIST" 2>/dev/null
sudo pfctl -E -f "$CONF" >/dev/null 2>&1

sudo killall -HUP mDNSResponder 2>/dev/null     # drop stale Bonjour cache
sudo dscacheutil -flushcache 2>/dev/null

echo
echo "Active block rules:"
sudo pfctl -a force-thunderbolt -s rules 2>/dev/null | sed 's/^/   /'

verify_thunderbolt

echo
if [ "$LEVEL" = 2 ]; then
  echo "Done. Those Macs are now reachable only over Thunderbolt, and this"
  echo "persists across reboots."
else
  echo "Done. Bonjour discovery for those Macs is blocked on LAN/Wi-Fi, so"
  echo "Finder browsing should steer to Thunderbolt. This persists across"
  echo "reboots. If a Mac is still reached over Ethernet via a direct IP,"
  echo "re-run and choose Level 2 for a hard block."
fi
echo "Re-run this for more peers; run the restore script to undo everything."
pause
