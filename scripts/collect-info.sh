#!/usr/bin/env bash
# Read-only snapshot of a QF head unit, to compare with the notes or attach to an issue.
#
#   scripts/collect-info.sh                 # uses the only device adb sees
#   ADB_SERIAL=192.168.1.50:5555 scripts/collect-info.sh
#
# Nothing is written on the unit: only getprop, cat, ls, pm, service list, settings get,
# dumpsys, wm and logcat -d. Output goes to ./qf-info-YYYYmmdd-HHMMSS/.
# Review it before sharing: it contains your settings and installed apps.
set -u

ADB=(adb); [ -n "${ADB_SERIAL:-}" ] && ADB+=(-s "$ADB_SERIAL")
"${ADB[@]}" get-state >/dev/null 2>&1 || { echo "adb can't see the unit"; exit 1; }

OUT="qf-info-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

run() {  # run NAME "command on the unit"
  { echo "# $2"; echo "# ----"; timeout 60 "${ADB[@]}" shell "$2" 2>&1; } > "$OUT/$1.txt"
  echo "ok  $1"
}

run 01-identity 'for p in ro.build.fingerprint ro.build.display.id ro.build.version.release ro.build.version.sdk ro.build.version.security_patch ro.board.platform ro.hardware ro.product.model ro.product.brand ro.debuggable ro.control_privapp_permissions; do echo "$p=$(getprop $p)"; done; id; getenforce'
run 02-cpu-mem 'grep -E "Hardware|processor" /proc/cpuinfo | sort | uniq -c; head -3 /proc/meminfo'
run 03-storage 'df -h 2>/dev/null; echo; mount | grep -E " /system | /vendor | /data | /great "'
run 04-qf-props 'getprop | grep -E "qf|persist.sys.(maps|dvr|obd|tpms)|otula"'
run 05-binder 'service list | grep -iE "qf|mcu|emmc|gesture|config_service|util_service"'
run 06-vendor-packages 'pm list packages -f | grep -E "com\.qf\.|zjinnova|fmradio|horizon|launcher"'
run 07-car-config 'ls -lZ /great/protect_dir/ 2>&1; echo; cat /great/protect_dir/car.config 2>&1'
run 08-whitelists 'for f in /great/protect_dir/bg_white_list.config /great/sleep/sleep_whitelist /system/config/NotKillAppsBeforeSleep.ini; do echo "== $f"; ls -lZ $f 2>&1; cat $f 2>&1; done'
run 09-canbox 'cat /great/canconf/canconfig.xml 2>&1 | head -40'
run 10-display 'wm size; wm density; wm overscan 2>&1; for k in "global policy_control" "secure nav_bar_force_visible" "system show_navigationbar" "global enable_freeform_support" "global force_resizable_activities"; do echo "$k=$(settings get $k)"; done; echo; dumpsys window windows | grep -E "Window #|mFrame=" | head -60'
run 11-home 'cmd package resolve-activity -c android.intent.category.HOME -a android.intent.action.MAIN | grep -E "packageName|name="'
run 12-framework-jars 'ls -l /system/framework/services.jar* /system/framework/oat/arm64/services.* 2>&1'
run 13-logcat-mcu 'logcat -d -v time 2>/dev/null | grep -E "mcu_services|UartDataTransmit|QFKeyEvent|KillApps|killAppsBeforeSleep" | tail -300'

echo "Done: $OUT/"
