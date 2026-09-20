#!/usr/bin/env bash
# Captures App Store screenshots from a simulator.
#
#   tools/app_store_screenshots.sh <simulator udid> <output dir>
#
# Runs integration_test/app_store_screenshots_test.dart, which prints
# `@@SHOT <name>` and holds still at every stop; each marker becomes
# <output dir>/<name>.png at the simulator's native resolution.
set -u
udid="$1"
out="$2"
mkdir -p "$out"
log="$out/run.log"
: > "$log"
xcrun simctl status_bar "$udid" override --time "9:41" --batteryState charged \
  --batteryLevel 100 --wifiBars 3 --cellularBars 4 >/dev/null 2>&1
flutter test integration_test/app_store_screenshots_test.dart -d "$udid" --no-pub \
  --dart-define=FORCE_DEBUG_APP_CHECK_PROVIDER=true -r expanded > "$log" 2>&1 &
pid=$!
taken=""
start=$(date +%s)
while kill -0 "$pid" 2>/dev/null; do
  for name in $(grep -o '@@SHOT [^ ]*' "$log" | cut -d' ' -f2); do
    case " $taken " in *" $name "*) continue ;; esac
    sleep 1.5 # let the screen settle after the marker
    xcrun simctl io "$udid" screenshot "$out/$name.png" >/dev/null 2>&1 && echo "captured $name"
    taken="$taken $name"
  done
  if [ $(( $(date +%s) - start )) -gt 1500 ]; then
    echo "watchdog: stopping after 25 minutes"; pkill -P "$pid"; kill "$pid"; break
  fi
  sleep 0.5
done
wait "$pid"
status=$?
xcrun simctl status_bar "$udid" clear >/dev/null 2>&1
echo "flutter exit: $status"
exit "$status"
