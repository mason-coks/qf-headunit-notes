#!/usr/bin/env bash
# Apply the settings from the notes to a QF head unit: no system bars, no freeform, apps kept
# alive through standby, and (optionally) your launcher as HOME.
#
# Dry run by default: prints what it would do. Add --do to execute.
#
#   KEEP_ALIVE="com.example.launcher com.tailscale.ipn" \
#   IMMERSIVE="com.example.launcher,com.waze,com.zjinnova.zlink" \
#   LAUNCHER=com.example.launcher \
#   scripts/apply-settings.sh [--do]
#
# Variables:
#   ADB_SERIAL   adb -s target (optional)
#   KEEP_ALIVE   packages added to BOTH app-killer whitelists (space-separated)       [docs/05]
#   IMMERSIVE    packages for policy_control immersive.full (comma-separated)         [docs/04]
#   LAUNCHER     package to make HOME through the vendor broadcast (optional)         [docs/03]
#   TOP_BAR      status bar height in px to push off-screen (default 160; 0 = skip)   [docs/04]
#
# Before changing anything it saves the current values and files to
# /data/local/tmp/qf-notes-backup/ on the unit. scripts/revert-settings.sh restores them.
# It does NOT touch services.jar, car.config by hand, or anything in /system.
set -uo pipefail

DO=0; [[ "${1:-}" == "--do" ]] && DO=1
ADB=(adb); [ -n "${ADB_SERIAL:-}" ] && ADB+=(-s "$ADB_SERIAL")
KEEP_ALIVE="${KEEP_ALIVE:-}"
IMMERSIVE="${IMMERSIVE:-}"
LAUNCHER="${LAUNCHER:-}"
TOP_BAR="${TOP_BAR:-160}"
BK=/data/local/tmp/qf-notes-backup
BG=/great/protect_dir/bg_white_list.config
SL=/great/sleep/sleep_whitelist
CTX=u:object_r:system_data_file:s0

sh_() {  # run (or print) a shell command on the unit
  if (( DO )); then "${ADB[@]}" shell "$1"; else echo "  adb shell '$1'"; fi
}
step() { echo; echo "== $* =="; }

if (( DO )); then
  "${ADB[@]}" get-state >/dev/null 2>&1 || { echo "adb can't see the unit"; exit 1; }
  [ "$("${ADB[@]}" shell id -u | tr -d '\r')" = 0 ] || { echo "adb shell is not root on this unit; stopping"; exit 1; }
  "${ADB[@]}" shell service list | grep -q mcu_service || { echo "no mcu_service: this doesn't look like a QF ROM; stopping"; exit 1; }
fi

step "0. Backup current state to $BK (only the first time, so revert goes back to stock)"
sh_ "if [ ! -f $BK/settings.txt ]; then mkdir -p $BK &&
  { for k in 'global policy_control' 'secure nav_bar_force_visible' 'system show_navigationbar' 'global enable_freeform_support' 'global force_resizable_activities'; do echo \"\$k=\$(settings get \$k)\"; done;
    echo \"prop persist.sys.qf.show.navibar=\$(getprop persist.sys.qf.show.navibar)\";
    echo \"prop persist.sys.qf.launcher=\$(getprop persist.sys.qf.launcher)\"; } > $BK/settings.txt &&
  cp /great/protect_dir/car.config $BK/car.config &&
  { [ -f $BG ] && cp $BG $BK/bg_white_list.config || touch $BK/bg_white_list.absent; } &&
  { [ -f $SL ] && cp $SL $BK/sleep_whitelist || touch $BK/sleep_whitelist.absent; } &&
  echo saved; else echo 'backup already exists, keeping it'; fi"

if [ -n "$IMMERSIVE" ]; then
  step "1. Immersive mode for: $IMMERSIVE"
  sh_ "settings put global policy_control immersive.full=$IMMERSIVE"
  sh_ "settings put secure nav_bar_force_visible 0"
else
  step "1. Immersive mode: skipped (IMMERSIVE not set)"
fi

step "2. Vendor bars off"
sh_ "settings put system show_navigationbar 0"
sh_ "setprop persist.sys.qf.show.navibar false"
if [ "$TOP_BAR" != 0 ]; then sh_ "wm overscan 0,-$TOP_BAR,0,0"; fi

step "3. Freeform off (takes effect after reboot; see docs/09 about launch_params)"
sh_ "settings put global enable_freeform_support 0"
sh_ "settings put global force_resizable_activities 0"

if [ -n "$KEEP_ALIVE" ]; then
  step "4. Whitelists against KillApps and QFSleepWakeup: $KEEP_ALIVE"
  sh_ "touch $BG && for p in $KEEP_ALIVE; do grep -qx \"\$p\" $BG || echo \"\$p\" >> $BG; done;
       chown system:system $BG; chmod 0666 $BG; chcon $CTX $BG"
  sh_ "mkdir -p /great/sleep && chmod 0755 /great/sleep && touch $SL &&
       for p in $KEEP_ALIVE; do grep -qx \"\$p\" $SL || echo \"\$p\" >> $SL; done;
       chown system:system $SL; chmod 0644 $SL; chcon $CTX $SL"
else
  step "4. Whitelists: skipped (KEEP_ALIVE not set)"
fi

if [ -n "$LAUNCHER" ]; then
  step "5. HOME = $LAUNCHER (vendor broadcast: updates car.config too)"
  if (( DO )) && ! "${ADB[@]}" shell pm path "$LAUNCHER" | grep -q package:; then
    echo "  $LAUNCHER is not installed: not changing HOME (a missing HOME leaves the unit without launcher)"
  else
    sh_ "am broadcast -a com.qf.action.SET_LAUNCHER --es packageName $LAUNCHER"
  fi
else
  step "5. HOME: skipped (LAUNCHER not set)"
fi

echo
if (( DO )); then
  echo "Done. Reboot when convenient (adb reboot) so the freeform change applies."
else
  echo "-- DRY RUN. Nothing was changed. Run again with --do to apply."
fi
