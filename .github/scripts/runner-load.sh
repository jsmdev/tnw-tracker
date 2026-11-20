#!/usr/bin/env bash
# Samples the runner's load while the UI tests run, to explain stalls
# (accessibility audits that run out of time). Usage:
#   runner-load.sh start  <log>  start sampling every 3 s in the background
#   runner-load.sh stop   <log>  stop sampling and print a summary
#   runner-load.sh settle        wait (at most 3 min) until the CPU is at
#                                least 50% idle for 30 s, so the tests do not
#                                start while the simulator is still busy
set -euo pipefail

cmd="${1:?start|stop|settle}"
log="${2:-}"
pidfile="$log.pid"

# The n busiest processes as name:cpu%/MB. Processes that run inside the
# simulator (their path is under a simulator runtime) are marked "sim/".
busiest() {
  ps -Ao pcpu=,rss=,comm= -r 2>/dev/null | head -"$1" \
    | awk '{cpu=$1; mem=$2; $1=""; $2=""; n=$0
            s=(n ~ /RuntimeRoot/) ? "sim/" : ""
            sub(".*/","",n); printf "%s%s:%s%%/%dMB ", s, n, cpu, mem/1024}'
}

cpu_idle() {
  top -l 2 -n 0 -s 1 | awk '/CPU usage/ {v=$7} END {gsub("%","",v); print v+0}'
}

sample() {
  # A failed probe (or `head` closing a pipe) must not stop the sampling.
  set +e +o pipefail
  while true; do
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    load=$(sysctl -n vm.loadavg | tr -d '{}' | awk '{print $1}')
    # CPU idle over one second, and disk MB/s summed over all disks.
    idle=$(cpu_idle)
    disk=$(iostat -d -K -c 2 -w 1 | tail -1 | awk '{for (i=3;i<=NF;i+=3) s+=$i; printf "%.1f", s}')
    free=$(memory_pressure -Q 2>/dev/null | awk -F': ' '/free percentage/ {gsub("%","",$2); print $2}')
    swap=$(sysctl -n vm.swapusage | awk '{print $6}')
    pageouts=$(vm_stat | awk '/Pageouts/ {gsub("\\.","",$2); print $2}')
    top=$(busiest 4)
    crashes=$(find "$HOME/Library/Logs/DiagnosticReports" -type f 2>/dev/null | wc -l | tr -d ' ')
    echo "$ts load=$load free=${free:-?}% swap_used=$swap pageouts=$pageouts crashes=$crashes idle=${idle:-?}% disk=${disk:-?}MB/s top=$top"
    sleep 3
  done
}

case "$cmd" in
  settle)
    set +e +o pipefail
    began=$SECONDS; quiet=0
    while (( SECONDS - began < 180 )); do
      idle=$(cpu_idle)
      echo "+$((SECONDS - began))s idle=${idle}% top=$(busiest 3)"
      if awk -v i="$idle" 'BEGIN {exit !(i >= 50)}'; then quiet=$((quiet + 1)); else quiet=0; fi
      if (( quiet >= 6 )); then echo "Runner quiet after $((SECONDS - began)) s"; exit 0; fi
      sleep 3
    done
    echo "Runner still busy after 180 s; starting the tests anyway"
    ;;
  start)
    : "${log:?log file}"
    mkdir -p "$(dirname "$log")"
    touch "$log.start"
    sample >"$log" 2>&1 &
    echo $! >"$pidfile"
    echo "Sampling runner load into $log (pid $(cat "$pidfile"))"
    ;;
  stop)
    : "${log:?log file}"
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
    awk '{for (i=2;i<=NF;i++) {split($i,kv,"="); if (kv[1]=="idle") {v=kv[2]+0; n++; t+=v; if (v<5) low++}}}
         END {if (n) printf "CPU idle: average %.0f%%, %d of %d samples under 5%%\n", t/n, low, n}' "$log"
    echo "Crash reports written while sampling (newest last):"
    if [[ -f "$log.start" ]]; then
      find "$HOME/Library/Logs/DiagnosticReports" -type f -newer "$log.start" 2>/dev/null \
        | xargs -I{} basename {} | sort | uniq -c | sort -n | tail -20 || true
    fi
    # The load average stays in the hundreds on this runner, so only memory
    # is a useful filter. awk stops at 40 lines itself: `| head` would close
    # the pipe early and fail the step.
    echo "Samples with free memory under 20% (at most 40):"
    awk '{split($3,f,"="); if (f[2]+0<20 && n++<40) print}' "$log"
    ;;
  *)
    echo "usage: $0 start|stop <log> | settle" >&2
    exit 2
    ;;
esac
