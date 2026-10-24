#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out="$root/www/bench/large.html"
mkdir -p "$(dirname "$out")"

{
  cat <<'HTML'
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<title>ToyStack bench: 1000 blocks</title>
<style>
  body { margin: 0; font-family: monospace; font-size: 12px; line-height: 16px; }
  .row { margin: 0; padding: 2px 0; }
  .alt { background-color: #eef2ff; }
  .warm { background-color: #fff7e6; }
  .hi { color: #a40000; }
  h2 { margin: 8px 0 4px; font-size: 14px; }
</style>
</head>
<body>
HTML

  i=0
  while [ "$i" -lt 1000 ]; do
    if [ $((i % 100)) -eq 0 ]; then
      printf '<h2 id="section-%d">section %d</h2>\n' "$i" "$i"
    fi
    if [ $((i % 7)) -eq 0 ]; then
      cls="row alt"
    elif [ $((i % 11)) -eq 0 ]; then
      cls="row warm"
    else
      cls="row"
    fi
    printf '<p class="%s">block %04d <span class="hi">alpha</span> beta gamma delta epsilon zeta eta theta</p>\n' "$cls" "$i"
    i=$((i + 1))
  done

  printf '</body>\n</html>\n'
} > "$out"

printf 'wrote %s (%s bytes)\n' "$out" "$(wc -c < "$out")"
