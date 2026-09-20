#!/usr/bin/env bash
# Runs iOS integration tests on a simulator, one file at a time.
#
#   scripts/run_ios_integration_tests.sh <simulator udid> integration_test/a_test.dart ...
#
# One file at a time with a watchdog each: a failing integration test can leave
# `flutter test -d <simulator>` hanging forever instead of exiting non-zero.
set -u
device="$1"
shift
limit="${IOS_IT_TIMEOUT_SECONDS:-900}"
failed=()
for test in "$@"; do
  echo "::group::$test"
  flutter test "$test" -d "$device" --no-pub \
    --dart-define=FORCE_DEBUG_APP_CHECK_PROVIDER=true -r expanded &
  pid=$!
  (
    sleep "$limit" &
    sleeper=$!
    # Stood down: leave without touching the test's (by now reusable) pid.
    trap 'kill "$sleeper" 2>/dev/null; exit 0' TERM
    wait "$sleeper"
    echo "watchdog: $test ran longer than ${limit}s, stopping it"
    pkill -P "$pid"
    kill "$pid"
  ) &
  watchdog=$!
  wait "$pid"
  status=$?
  kill "$watchdog" 2>/dev/null
  wait "$watchdog" 2>/dev/null
  echo "::endgroup::"
  if [ "$status" -eq 0 ]; then echo "PASS $test"; else echo "FAIL $test ($status)"; failed+=("$test"); fi
done
if [ "${#failed[@]}" -gt 0 ]; then
  printf 'failed: %s\n' "${failed[@]}"
  exit 1
fi
