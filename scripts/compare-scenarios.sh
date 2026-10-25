#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  printf 'usage: %s <baseline-dir> <candidate-dir>\n' "$0" >&2
  exit 2
fi

baseline=$1
candidate=$2
status=0

for scenario in A B C D; do
  expected="$baseline/$scenario.png"
  actual="$candidate/$scenario.png"

  if [ ! -f "$expected" ]; then
    printf '%s: missing baseline: %s\n' "$scenario" "$expected" >&2
    status=1
    continue
  fi
  if [ ! -f "$actual" ]; then
    printf '%s: missing candidate: %s\n' "$scenario" "$actual" >&2
    status=1
    continue
  fi

  if cmp -s "$expected" "$actual"; then
    printf '%s: match\n' "$scenario"
  else
    printf '%s: DIFFERS\n' "$scenario" >&2
    shasum -a 256 "$expected" "$actual" >&2
    status=1
  fi
done

exit "$status"
