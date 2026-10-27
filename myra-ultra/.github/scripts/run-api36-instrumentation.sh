#!/usr/bin/env bash
set +e

watch_log="myra-api36-device-watch.log"
device_log="myra-api36-live-logcat.log"
: > "$watch_log"
: > "$device_log"
(
  while true; do
    {
      printf '\n=== %s ===\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      adb devices -l
      printf 'Guest app and instrumentation processes:\n'
      adb shell 'ps -A | grep -E "com\.myra\.ultra\.nativeapp|androidx\.test" || true' 2>&1
      pgrep -af '[e]mulator|[q]emu-system' || true
      awk '/MemAvailable|SwapFree/ {print}' /proc/meminfo
      if [ -r /sys/fs/cgroup/memory.events ]; then cat /sys/fs/cgroup/memory.events; fi
    } >> "$watch_log" 2>&1
    sleep 10
  done
) &
watch_pid=$!
adb logcat -b all -v threadtime > "$device_log" 2>&1 &
logcat_pid=$!

stop_monitors() {
  kill "$watch_pid" "$logcat_pid" 2>/dev/null || true
  wait "$watch_pid" 2>/dev/null || true
  wait "$logcat_pid" 2>/dev/null || true
}
trap stop_monitors EXIT

./gradlew --no-daemon connectedDebugAndroidTest
test_status=$?
stop_monitors
trap - EXIT

if [ "$test_status" -ne 0 ]; then
  echo 'API 36 test failed; last emulator/host snapshots:'
  tail -n 150 "$watch_log"
  echo 'Final emulator process list:'
  pgrep -af '[e]mulator|[q]emu-system' || true
  echo 'Final cgroup memory events:'
  if [ -r /sys/fs/cgroup/memory.events ]; then cat /sys/fs/cgroup/memory.events; fi
fi
exit "$test_status"
