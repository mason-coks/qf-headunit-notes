# Scripts

All three talk to the unit over `adb` (set `ADB_SERIAL` if more than one device is connected)
and need the ROM's root `adb shell` ([docs/01](../docs/01-device-and-access.md)).

| Script | What it does | Writes to the unit? |
|---|---|---|
| `collect-info.sh` | Snapshot of identity, vendor properties, binder services, `car.config`, whitelists, display settings and recent MCU log lines into `./qf-info-<date>/` | No |
| `apply-settings.sh` | Saves the current state, then: immersive list, vendor bars off, freeform off, your packages added to both app-killer whitelists, your launcher as HOME | Yes, with `--do` |
| `revert-settings.sh` | Puts back what `apply-settings.sh` saved, and the factory launcher as HOME | Yes, with `--do` |

Without `--do` the apply and revert scripts only print the commands they would run.

```bash
scripts/collect-info.sh

KEEP_ALIVE="com.example.launcher com.tailscale.ipn" \
IMMERSIVE="com.example.launcher,com.waze,com.zjinnova.zlink" \
LAUNCHER=com.example.launcher \
scripts/apply-settings.sh          # look at the plan
# … then the same with --do, and adb reboot

scripts/revert-settings.sh --do
```

How these were tested: every command in them was run by hand on the K706 described in the
README. The scripts as a whole were checked against a simulated `adb` (backup, idempotent
re-run, revert), not end to end on a unit. Run the dry run first and read it.

Not covered on purpose: the `services.jar` hooks ([hooks/](../hooks/)), replacing the radio
app, and hand edits of `car.config`.
