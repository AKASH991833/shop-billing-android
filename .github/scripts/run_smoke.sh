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

PKG=com.example.shop_billing
STATE=/storage/emulated/0/Android/data/$PKG/files/shop_billing_state.txt
adb shell rm -f "$STATE"
adb shell run-as $PKG rm -f files/native_done.txt 2>/dev/null

# The flutter tool UNINSTALLS the app when the test session ends (run 42
# logcat: PACKAGE_FULLY_REMOVED at session close), so native OS-level checks
# must run WHILE the suite is alive. The suite marks app states in $STATE;
# this poller grabs a native screencap at each state, and when the lock test
# marks 'unlocked' (password persisted, app on Home, engine idle in its
# native window) it runs lock_relaunch.py concurrently.
(
  LAST_STATE=""
  LOCK_RAN=""
  while true; do
    S=$(adb shell cat "$STATE" 2>/dev/null | tr -d '\r')
    if [ -n "$S" ] && [ "$S" != "$LAST_STATE" ]; then
      adb exec-out screencap -p > "state_$S.png" 2>/dev/null
      echo "state capture: $S -> state_$S.png"
      LAST_STATE="$S"
      if [ "$S" = "unlocked" ] && [ -z "$LOCK_RAN" ]; then
        LOCK_RAN=1
        timeout 200 python3 .github/scripts/lock_relaunch.py
        echo $? > /tmp/lock_exit
      fi
    fi
    sleep 3
  done
) &
POLLER=$!

timeout 780 flutter test integration_test/smoke_test.dart -r expanded
ITEST=$?

# If the native checks started but have not reported yet, give them their
# full bounded window (lock_relaunch is capped at 200s) before collecting.
if [ ! -f /tmp/lock_exit ] && adb shell cat "$STATE" 2>/dev/null | grep -q unlocked; then
  for i in $(seq 1 70); do
    [ -f /tmp/lock_exit ] && break
    sleep 3
  done
fi
kill $POLLER 2>/dev/null
pkill -f lock_relaunch.py 2>/dev/null
LOCK=$(cat /tmp/lock_exit 2>/dev/null)
if [ -z "$LOCK" ]; then
  echo "native lock checks never ran (state 'unlocked' not observed)"
  LOCK=9
fi

# Evidence FIRST, before any later phase can hang or be cut off.
adb logcat -d -t 400 > logcat_tail.txt
ls -la *.png 2>/dev/null

# Release APK boot proof LAST (uninstalls whatever the suite left).
timeout 420 python3 .github/scripts/boot_shot.py
BOOT=$?

adb logcat -d -t 200 >> logcat_tail.txt
echo "ITEST_EXIT=$ITEST LOCK_EXIT=$LOCK BOOT_EXIT=$BOOT"
if [ "$ITEST" != "0" ] || [ "$LOCK" != "0" ] || [ "$BOOT" != "0" ]; then
  exit 1
fi
