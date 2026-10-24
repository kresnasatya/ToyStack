#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out=${1:-"$root/benchmark/$(date +%Y-%m-%d-%H%M%S)"}
repeats=${REPEATS:-3}

case "$repeats" in
  ''|*[!0-9]*|0)
    printf 'REPEATS must be a positive integer, got %s\n' "$repeats" >&2
    exit 2
    ;;
esac

mkdir -p "$out"

run() {
  swift run -c release ToyStackHeadless "$@"
}

base="file://$root/www"

# C — 6 bursts x 60 events, 250 ms apart, 40 px each.
scrolls=""
burst=0
while [ "$burst" -lt 6 ]; do
  i=0
  while [ "$i" -lt 60 ]; do
    t=$(awk -v b="$burst" -v e="$i" \
      'BEGIN { printf "%.4f", 2.0 + 0.25*b + e*0.25/60 }')
    scrolls="$scrolls --scroll-at $t:0:300:-40"
    i=$((i + 1))
  done
  burst=$((burst + 1))
done

rep=1
while [ "$rep" -le "$repeats" ]; do
  dir="$out/run-$rep"
  mkdir -p "$dir"

  # A — width animation, 10 s.
  run "$base/ch13/exercise-13-5-1.html" \
    --trace "$dir/A.trace" --frame-limit 600 \
    --screenshot "$dir/A.png"

  # B — opacity animation, 10 s; must not lay out after frame 1.
  run "$base/ch13/exercise-13-5-2.html" \
    --trace "$dir/B.trace" --frame-limit 600 \
    --screenshot "$dir/B.png"

  run "$base/bench/large.html" \
    --trace "$dir/C.trace" --frame-limit 300 $scrolls \
    --screenshot "$dir/C.png"

  # D — same page, no input; first-layout cost baseline.
  run "$base/bench/large.html" \
    --trace "$dir/D.trace" --frame-limit 600 \
    --screenshot "$dir/D.png"

  rep=$((rep + 1))
done

printf 'scenarios written to %s (%s repetitions per scenario)\n' "$out" "$repeats"
