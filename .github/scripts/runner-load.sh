#!/usr/bin/env bash
# Samples the runner's load while the UI tests run, to explain stalls
# (accessibility audits that run out of time). Usage:
#   runner-load.sh start <log>   start sampling every 5 s in the background
#   runner-load.sh stop  <log>   stop sampling and print a summary
set -euo pipefail

cmd="${1:?start|stop}"
log="${2:?log file}"
pidfile="$log.pid"

sample() {
  # A failed probe (or `head` closing a pipe) must not stop the sampling.
  set +e +o pipefail
  while true; do
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    load=$(sysctl -n vm.loadavg | tr -d '{}' | awk '{print $1}')
    free=$(memory_pressure -Q 2>/dev/null | awk -F': ' '/free percentage/ {gsub("%","",$2); print $2}')
    swap=$(sysctl -n vm.swapusage | awk '{print $6}')
    pageouts=$(vm_stat | awk '/Pageouts/ {gsub("\\.","",$2); print $2}')
    top=$(ps -Ao pcpu=,rss=,comm= -r | head -3 \
      | awk '{n=$3; sub(".*/","",n); printf "%s:%s%%/%dMB ", n, $1, $2/1024}')
    echo "$ts load=$load free=${free:-?}% swap_used=$swap pageouts=$pageouts top=$top"
    sleep 5
  done
}

case "$cmd" in
  start)
    mkdir -p "$(dirname "$log")"
    sample >"$log" 2>&1 &
    echo $! >"$pidfile"
    echo "Sampling runner load into $log (pid $(cat "$pidfile"))"
    ;;
  stop)
    if [[ -f "$pidfile" ]]; then
      kill "$(cat "$pidfile")" 2>/dev/null || true
      rm -f "$pidfile"
    fi
    [[ -s "$log" ]] || { echo "No samples in $log"; exit 0; }
    echo "Samples: $(wc -l <"$log")"
    awk '{for (i=2;i<=4;i++) {split($i,kv,"="); v[kv[1]]=kv[2]}
          l=v["load"]+0; f=v["free"]+0; s=v["swap_used"]+0
          if (l>ml) ml=l; if (NR==1 || f<mf) mf=f; if (s>ms) ms=s}
         END {printf "Max load: %.2f  Min free memory: %d%%  Max swap used: %.0fM\n", ml, mf, ms}' "$log"
    echo "Samples with free memory under 20% or load over 6:"
    awk '{split($3,f,"="); split($2,l,"="); if (f[2]+0<20 || l[2]+0>6) print}' "$log" | head -40
    ;;
  *)
    echo "usage: $0 start|stop <log>" >&2
    exit 2
    ;;
esac
