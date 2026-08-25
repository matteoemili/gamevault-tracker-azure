#!/bin/bash
# Emits deterministic JSON Lines for logical-instance scale tests.

set -u
set -o pipefail

count="${1:-}"
case "$count" in
  ''|*[!0-9]*) echo "Usage: generate-logical-instances.sh <non-negative-count>" >&2; exit 2 ;;
esac

i=1
while [ "$i" -le "$count" ]; do
  printf '{"logicalInstanceId":"li-%05d","displayName":"Logical Instance %05d"}\n' "$i" "$i"
  i=$((i + 1))
done
