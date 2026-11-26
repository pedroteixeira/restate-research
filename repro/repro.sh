#!/usr/bin/env bash
# End-to-end repro: restate-server + fake deployment answering with one frame of the given
# 16-bit message type. Prints how many invoker panics and RT0012 errors were logged.
# Usage: repro/repro.sh <type_hex> [image_tag]
#   Default: docker image docker.restate.dev/restatedev/restate:<image_tag> (host network).
#   RESTATE_BIN=/path/to/restate-server: run that binary instead (label "local"), e.g. a build
#   of a fix branch.
set -u
TY=${1:?type hex, e.g. 040F}
TAG=${2:-1.8.1-hotfix.3}
HERE=$(cd "$(dirname "$0")" && pwd)
LOGS=$HERE/../logs
mkdir -p "$LOGS"
NAME=restate-repro
BIN=${RESTATE_BIN:-}
[ -n "$BIN" ] && TAG=local

SRV_LOG=$(mktemp)
BASE=$(mktemp -d)
SRV=
srv_logs() { if [ -n "$BIN" ]; then cat "$SRV_LOG"; else docker logs $NAME 2>&1; fi; }
cleanup() {
  kill $FAKE 2>/dev/null
  if [ -n "$BIN" ]; then [ -n "$SRV" ] && kill $SRV 2>/dev/null; wait 2>/dev/null; rm -rf "$BASE"
  else docker rm -f $NAME >/dev/null 2>&1; fi
  rm -f "$SRV_LOG"
}

[ -z "$BIN" ] && docker rm -f $NAME >/dev/null 2>&1
python3 -I "$HERE/fake_deployment.py" 9080 "$TY" > "$LOGS/fake-$TY.log" 2>&1 &
FAKE=$!
trap cleanup EXIT

if [ -n "$BIN" ]; then
  "$BIN" --base-dir "$BASE" > "$SRV_LOG" 2>&1 &
  SRV=$!
elif ! docker run -d --name $NAME --network host docker.restate.dev/restatedev/restate:$TAG >/dev/null; then
  echo "failed to start restate:$TAG" >&2; exit 1
fi
start=$(date +%s)
until curl -sf localhost:9070/health >/dev/null; do
  if [ $(( $(date +%s) - start )) -gt 60 ]; then
    echo "restate:$TAG not healthy after 60s" >&2; srv_logs | tail -20 >&2; exit 1
  fi
  sleep 1
done

curl -s -X POST localhost:9070/deployments -H 'content-type: application/json' \
  -d '{"uri":"http://localhost:9080","use_http_11":true}' -o /dev/null -w "register: HTTP %{http_code}\n"
curl -s -X POST localhost:8080/Repro/run/send -H 'content-type: application/json' -d '{}'; echo

start=$(date +%s)
until [ "$(srv_logs | grep -c 'PANIC!!!')" -ge 2 ] || [ $(( $(date +%s) - start )) -gt 30 ]; do sleep 1; done
OUT="$LOGS/restate-$TY-$TAG.log"
srv_logs | sed 's/\x1b\[[0-9;]*m//g' > "$OUT"
echo "type=0x$TY tag=$TAG panics=$(grep -c 'PANIC!!!' "$OUT")" \
  "pp_restarts=$(grep -c 'Partition processor exited unexpectedly' "$OUT")" \
  "rt0012=$(grep -c 'RT0012' "$OUT")" \
  "invokes=$(grep -c 'POST /invoke' "$LOGS/fake-$TY.log")"
grep -m1 'panicked at' "$OUT"
grep -m1 'received unexpected message' "$OUT"
exit 0
