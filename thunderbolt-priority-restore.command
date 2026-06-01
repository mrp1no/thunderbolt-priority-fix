#!/bin/bash
#
# force-thunderbolt-restore.command
# ------------------------------------------------------------------
# Removes ALL Bonjour blocks created by force-thunderbolt-apply.command,
# no matter how many addresses/peers were blocked. Restores normal
# discovery on every interface.
#
# Double-click to run. You'll be asked for your login password (sudo).
# ------------------------------------------------------------------

ANCHOR="/etc/pf.anchors/force-thunderbolt"
CONF="/etc/pf-force-thunderbolt.conf"
PLIST="/Library/LaunchDaemons/org.local.force-thunderbolt.plist"

pause() { echo; echo "Press Return to close."; read -r _; }

echo "==================================================="
echo " Force Thunderbolt - restore (remove ALL blocks)"
echo "==================================================="
echo "You may be asked for your login password."
echo

# stop & remove the boot daemon
sudo launchctl unload -w "$PLIST" 2>/dev/null

# flush our anchor's rules, then reload Apple's default ruleset so the
# anchor is fully detached from the live pf configuration
sudo pfctl -a force-thunderbolt -F rules 2>/dev/null
sudo pfctl -f /etc/pf.conf 2>/dev/null

# delete the files we created
sudo rm -f "$ANCHOR" "$CONF" "$PLIST"

# refresh discovery so the previously blocked Macs reappear
sudo killall -HUP mDNSResponder 2>/dev/null
sudo dscacheutil -flushcache 2>/dev/null

echo "All blocks removed. Bonjour discovery is back to normal on every"
echo "interface. If a Mac is still missing, wait a few seconds or reopen Finder."
pause
