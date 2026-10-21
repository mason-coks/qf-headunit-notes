#!/usr/bin/env bash
# Undo scripts/apply-settings.sh using the backup it left in /data/local/tmp/qf-notes-backup/.
#
# Dry run by default. Add --do to execute.
#
#   FACTORY_HOME=com.android.launcher.horizon.city scripts/revert-settings.sh [--do]
#
# FACTORY_HOME is the factory launcher to restore as HOME (default above, the one on the
# tested K706). car.config itself is NOT overwritten from the backup, because the vendor
# Settings app may have changed other lines since; the backup copy stays on the unit at
# /data/local/tmp/qf-notes-backup/car.config if you need it.
set -uo pipefail

DO=0; [[ "${1:-}" == "--do" ]] && DO=1
ADB=(adb); [ -n "${ADB_SERIAL:-}" ] && ADB+=(-s "$ADB_SERIAL")
FACTORY_HOME="${FACTORY_HOME:-com.android.launcher.horizon.city}"
BK=/data/local/tmp/qf-notes-backup
BG=/great/protect_dir/bg_white_list.config
SL=/great/sleep/sleep_whitelist
CTX=u:object_r:system_data_file:s0

sh_() { if (( DO )); then "${ADB[@]}" shell "$1"; else echo "  adb shell '$1'"; fi; }
step() { echo; echo "== $* =="; }

if (( DO )); then
  "${ADB[@]}" get-state >/dev/null 2>&1 || { echo "adb can't see the unit"; exit 1; }
  "${ADB[@]}" shell "[ -f $BK/settings.txt ]" || { echo "no backup at $BK on the unit; nothing to revert from"; exit 1; }
fi

step "1. Settings and properties back to the saved values"
# each line: "<namespace> <key>=<value>" or "prop <name>=<value>"; "null" = was unset
sh_ "while IFS= read -r line; do
  ns=\${line%% *}; rest=\${line#* }; key=\${rest%%=*}; val=\${rest#*=}
  if [ \"\$ns\" = prop ]; then
    case \$key in persist.sys.qf.launcher) ;; *) setprop \"\$key\" \"\$val\";; esac
  elif [ \"\$val\" = null ]; then settings delete \$ns \$key >/dev/null
  else settings put \$ns \$key \"\$val\"; fi
  echo \"restored \$ns \$key\"
done < $BK/settings.txt"

step "2. Status bar back on screen"
sh_ "wm overscan reset"

step "3. Whitelists back to how they were"
sh_ "if [ -f $BK/bg_white_list.absent ]; then rm -f $BG; else cp $BK/bg_white_list.config $BG; chown system:system $BG; chmod 0666 $BG; chcon $CTX $BG; fi"
sh_ "if [ -f $BK/sleep_whitelist.absent ]; then rm -f $SL; else cp $BK/sleep_whitelist $SL; chown system:system $SL; chmod 0644 $SL; chcon $CTX $SL; fi"

step "4. HOME = $FACTORY_HOME"
sh_ "am broadcast -a com.qf.action.SET_LAUNCHER --es packageName $FACTORY_HOME"

echo
if (( DO )); then
  echo "Done. Reboot (adb reboot) so the freeform settings apply."
  echo "The backup is kept in $BK; delete it by hand if you want apply-settings.sh to take a fresh one."
else
  echo "-- DRY RUN. Nothing was changed. Run again with --do to revert."
fi
