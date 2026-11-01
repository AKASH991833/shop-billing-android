#!/bin/bash
# Android-runtime smoke runner. The emulator action executes the workflow
# "script" LINE BY LINE and aborts on the first non-zero line, so the whole
# flow lives in this single file. Never abort mid-flow: capture evidence and
# decide the exit code at the end.
set +e
cd "$(dirname "$0")/../.."

# Tee EVERYTHING to a file that lands in the evidence artifact - the Actions
# log delivery dropped this script's own echoes in run 41.
exec > >(tee smoke_run.log) 2>&1

# State-handshake poller: the smoke suite writes the current app state to
# /sdcard/shop_billing_state.txt at known screens (home, more, lockgate,
# unlocked); grab a native adb screencap the moment each state appears, so
# real Android pixels do not depend on Flutter's screenshot conversion.
adb shell rm -f /sdcard/shop_billing_state.txt
LAST_STATE=""
(
  while true; do
    S=$(adb shell cat /sdcard/shop_billing_state.txt 2>/dev/null | tr -d '\r')
    if [ -n "$S" ] && [ "$S" != "$LAST_STATE" ]; then
      adb exec-out screencap -p > "state_$S.png" 2>/dev/null
      echo "state capture: $S -> state_$S.png"
      LAST_STATE="$S"
    fi
    sleep 3
  done
) &
POLLER=$!

timeout 780 flutter test integration_test/smoke_test.dart -r expanded
ITEST=$?

kill $POLLER 2>/dev/null

# Evidence FIRST, before any later phase can hang or be cut off.
adb logcat -d -t 400 > logcat_tail.txt
ls -la *.png 2>/dev/null
# Fallback: if the test session was killed before the tool pulled the
# screenshots, recover them from on-device storage.
adb shell ls /storage/emulated/0/Android/data/com.example.shop_billing/files/Pictures/ 2>/dev/null
for f in 01_home 02_before_save 03_after_save 04_more 05_lock_screen 06_unlocked_home; do
  if [ ! -f "$f.png" ]; then
    adb pull "/storage/emulated/0/Android/data/com.example.shop_billing/files/Pictures/$f.png" "$f.png" 2>/dev/null
  fi
done
ls -la *.png 2>/dev/null

# OS-level lock checks on the same device (password persisted by the smoke
# suite): password persistence, cold-start gate, native-input unlock,
# HOME+relaunch - each with foreground-focus evidence first.
timeout 240 python3 .github/scripts/lock_relaunch.py
LOCK=$?

# Release APK boot proof LAST (uninstalls the debug build).
timeout 420 python3 .github/scripts/boot_shot.py
BOOT=$?

adb logcat -d -t 200 >> logcat_tail.txt
echo "ITEST_EXIT=$ITEST LOCK_EXIT=$LOCK BOOT_EXIT=$BOOT"
if [ "$ITEST" != "0" ] || [ "$LOCK" != "0" ] || [ "$BOOT" != "0" ]; then
  exit 1
fi
