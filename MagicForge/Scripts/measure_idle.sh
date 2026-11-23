#!/usr/bin/env bash
# Measures idle CPU and memory of a running MagicForge (or any process) by sampling.
# It only reports what it measured on this machine; it contains no reference numbers.
#
#   Scripts/measure_idle.sh                          # launch dist/MagicForge.app, sample 30 s, quit it
#   Scripts/measure_idle.sh --duration 120 --interval 2
#   Scripts/measure_idle.sh --pid 12345              # attach to a running process (left running)
#   Scripts/measure_idle.sh --app /Applications/MagicForge.app --output idle.txt
#
# Options:
#   --pid PID         sample this process instead of launching the app
#   --app PATH        app bundle to launch (default <package>/dist/MagicForge.app)
#   --duration SEC    sampling time (default 30)
#   --interval SEC    seconds between samples (default 1)
#   --warmup SEC      wait after launch before sampling (default 5)
#   --output FILE     also write the report to FILE
#
# Method: `ps -o %cpu=,rss=` every interval (on macOS ps %cpu is a decaying average), and on
# macOS additionally `top -l` for per-interval CPU and idle wake-ups. "Idle" is only
# meaningful if you leave the mouse and keyboard alone while it runs.
# Exit status: 0 ok, 2 the process exited while being sampled.
set -euo pipefail

# shellcheck source=Scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

PID=""
APP="$MF_ROOT/dist/$MF_APP_NAME.app"
DURATION=30
INTERVAL=1
WARMUP=5
OUTPUT=""

while (( $# > 0 )); do
  case "$1" in
    --pid|--app|--duration|--interval|--warmup|--output)
      [[ $# -ge 2 ]] || mf_die "$1 needs a value"
      case "$1" in
        --pid) PID="$2" ;;
        --app) APP="$2" ;;
        --duration) DURATION="$2" ;;
        --interval) INTERVAL="$2" ;;
        --warmup) WARMUP="$2" ;;
        --output) OUTPUT="$2" ;;
      esac
      shift ;;
    -h|--help) sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) mf_die "unknown argument: $1 (see --help)" ;;
  esac
  shift
done

for value in "$DURATION" "$INTERVAL" "$WARMUP"; do
  [[ "$value" =~ ^[0-9]+$ ]] || mf_die "durations must be whole seconds, got '$value'"
done
(( INTERVAL >= 1 )) || mf_die "--interval must be at least 1"
(( DURATION >= INTERVAL )) || mf_die "--duration must be at least --interval"

LAUNCHED=0
WORK="$(mktemp -d -t mf-idle.XXXXXX)"
cleanup() {
  if (( LAUNCHED == 1 )) && kill -0 "$PID" 2>/dev/null; then
    kill "$PID" 2>/dev/null || true
  fi
  rm -rf "${WORK:?}"
}
trap cleanup EXIT

if [[ -z "$PID" ]]; then
  mf_require_macos "Launching the app"
  EXECUTABLE="$APP/Contents/MacOS/$MF_APP_NAME"
  [[ -x "$EXECUTABLE" ]] || mf_die "$EXECUTABLE not found; build the app first or pass --pid"
  mf_log "Launching $EXECUTABLE"
  "$EXECUTABLE" >"$WORK/app.log" 2>&1 &
  PID=$!
  LAUNCHED=1
  sleep "$WARMUP"
fi
[[ "$PID" =~ ^[0-9]+$ ]] || mf_die "--pid must be a number"
kill -0 "$PID" 2>/dev/null || mf_die "process $PID is not running"

SAMPLES=$(( DURATION / INTERVAL ))
mf_log "Sampling pid $PID: $SAMPLES samples, every ${INTERVAL}s"

TOP_FILE="$WORK/top.txt"
TOP_PID=""
if mf_is_macos; then
  # The first top sample has no CPU delta, so take one extra and drop it later.
  top -l $(( SAMPLES + 1 )) -s "$INTERVAL" -pid "$PID" -stats pid,cpu,idlew >"$TOP_FILE" 2>/dev/null &
  TOP_PID=$!
fi

PS_FILE="$WORK/ps.txt"
: >"$PS_FILE"
DIED=0
for (( i = 0; i < SAMPLES; i++ )); do
  if ! line="$(ps -o %cpu= -o rss= -p "$PID" 2>/dev/null)" || [[ -z "$line" ]]; then
    DIED=1
    break
  fi
  printf '%s\n' "$line" >>"$PS_FILE"
  sleep "$INTERVAL"
done
if [[ -n "$TOP_PID" ]]; then
  wait "$TOP_PID" 2>/dev/null || true
fi

if mf_is_macos; then
  HOST_OS="macOS $(sw_vers -productVersion)"
else
  HOST_OS="$(uname -r)"
fi

REPORT="$WORK/report.txt"
{
  echo "MagicForge idle measurement"
  echo "  date:      $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "  host:      $(uname -sm), $HOST_OS"
  if mf_is_macos; then
    echo "  hardware:  $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"
  fi
  echo "  process:   pid $PID ($(ps -o comm= -p "$PID" 2>/dev/null || echo exited))"
  echo "  requested: ${DURATION}s at ${INTERVAL}s intervals"
  if (( DIED == 1 )); then
    echo "  WARNING:   the process exited during sampling; results cover only the samples taken"
  fi
  awk '
    { n++; cpu += $1; if ($1 > cpumax) cpumax = $1; rss += $2; if ($2 > rssmax) rssmax = $2
      if (n == 1 || $2 < rssmin) rssmin = $2 }
    END {
      if (n == 0) { print "  ps:        no samples collected"; exit }
      printf "  ps:        %d samples\n", n
      printf "    CPU %%   avg %.2f   max %.2f\n", cpu / n, cpumax
      printf "    RSS MB  avg %.1f   min %.1f   max %.1f\n", rss / n / 1024, rssmin / 1024, rssmax / 1024
    }' "$PS_FILE"
  if [[ -s "$TOP_FILE" ]]; then
    awk -v pid="$PID" '
      $1 == pid { seen++; if (seen == 1) next
        n++; cpu += $2; if ($2 > cpumax) cpumax = $2; wake += $3; if ($3 > wakemax) wakemax = $3 }
      END {
        if (n == 0) { print "  top:       no samples collected"; exit }
        printf "  top:       %d samples (first discarded)\n", n
        printf "    CPU %%   avg %.2f   max %.2f\n", cpu / n, cpumax
        printf "    idle wake-ups per sample   avg %.1f   max %d\n", wake / n, wakemax
      }' "$TOP_FILE"
  fi
} >"$REPORT"

cat "$REPORT"
if [[ -n "$OUTPUT" ]]; then
  cp "$REPORT" "$OUTPUT"
fi
if (( DIED == 1 )); then
  exit 2
fi
