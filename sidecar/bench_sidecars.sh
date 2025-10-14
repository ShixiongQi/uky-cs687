#!/usr/bin/env bash
# Bench baseline vs TCP-sidecar vs UDS-sidecar with wrk; dump rich CSV.
# Usage examples:
#   ./bench_sidecars.sh --node-ip 10.10.1.1
#   ./bench_sidecars.sh --node-ip 10.10.1.1 --max-conc 64 --duration 30s --max-threads 8 --out results.csv

set -euo pipefail

# Defaults (overridable via flags below)
MAX_CONC="${MAX_CONC:-64}"
DURATION="${DURATION:-30s}"
MAX_THREADS="${MAX_THREADS:-4}"
OUT="${OUT:-sidecar_bench_$(date +%Y%m%d_%H%M%S).csv}"
NODE_IP="${NODE_IP:-}"

# ----- CLI flags -----
while [[ $# -gt 0 ]]; do
  case "$1" in
    --node-ip)     NODE_IP="$2"; shift 2 ;;
    --max-conc)    MAX_CONC="$2"; shift 2 ;;
    --duration)    DURATION="$2"; shift 2 ;;
    --max-threads) MAX_THREADS="$2"; shift 2 ;;
    --out)         OUT="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }; }
need kubectl; need wrk; need awk; need sed

# ----- Discover NODE_IP if not provided -----
if [[ -z "${NODE_IP}" ]]; then
  NODE_IP="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"
fi
[[ -n "${NODE_IP}" ]] || { echo "Failed to resolve NODE_IP. Set --node-ip <IP> and retry." >&2; exit 1; }

# ----- Helpers -----
get_nodeport() {
  local svc="$1"
  local p
  p="$(kubectl get svc "$svc" -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')"
  [[ -n "$p" ]] || p="$(kubectl get svc "$svc" -o jsonpath='{.spec.ports[0].nodePort}')"
  echo "$p"
}

to_ms() {
  # Convert latency token to milliseconds (supports us/ms/s)
  local tok="${1:-}"; [[ -n "$tok" ]] || { echo "NA"; return; }
  local num unit
  num="$(printf '%s' "$tok" | sed -E 's/^([0-9.]+).*/\1/')"
  unit="$(printf '%s' "$tok" | sed -E 's/^[0-9.]+(.*)$/\1/')"
  case "$unit" in
    us) awk -v n="$num" 'BEGIN{printf "%.6f", n/1000.0}' ;;
    ms) awk -v n="$num" 'BEGIN{printf "%.3f", n}' ;;
    s)  awk -v n="$num" 'BEGIN{printf "%.3f", n*1000.0}' ;;
    *)  printf "%s" "$num" ;;
  esac
}

from_si() {
  # Convert Req/Sec tokens with optional SI suffix (k/M/G) to plain number
  local tok="${1:-}"; [[ -n "$tok" ]] || { echo "NA"; return; }
  if [[ "$tok" =~ ^[0-9.]+$ ]]; then printf "%s" "$tok"; return; fi
  local num="${tok%[a-zA-Z]}"; local suf="${tok:${#num}}"
  case "$suf" in
    k|K) awk -v n="$num" 'BEGIN{printf "%.6f", n*1000.0}' ;;
    M)   awk -v n="$num" 'BEGIN{printf "%.6f", n*1000000.0}' ;;
    G)   awk -v n="$num" 'BEGIN{printf "%.6f", n*1000000000.0}' ;;
    m)   awk -v n="$num" 'BEGIN{printf "%.6f", n/1000.0}' ;;  # unlikely, but safe
    *)   printf "%s" "$num" ;;
  esac
}

strip_pct() {
  local tok="${1:-}"; [[ -n "$tok" ]] || { echo "NA"; return; }
  printf '%s' "$tok" | sed 's/%$//'
}

# ----- Ports -----
BASE_PORT="$(get_nodeport nginx-baseline-svc)"
TCP_PORT="$(get_nodeport nginx-sidecar-tcp-svc)"
UDS_PORT="$(get_nodeport nginx-sidecar-uds-svc)"
for var in BASE_PORT TCP_PORT UDS_PORT; do
  [[ -n "${!var}" ]] || { echo "Service ${var%_PORT} has no NodePort. Patch the Service or set ports manually." >&2; exit 1; }
done

echo "Using NODE_IP=$NODE_IP"
echo " baseline:    http://$NODE_IP:$BASE_PORT/"
echo " sidecar-tcp: http://$NODE_IP:$TCP_PORT/"
echo " sidecar-uds: http://$NODE_IP:$UDS_PORT/"
echo

# ----- CSV header -----
echo "variant,concurrency,threads,lat_avg_ms,lat_stdev_ms,lat_max_ms,lat_pm_stdev_pct,reqps_thread_avg,reqps_thread_stdev,reqps_thread_max,reqps_thread_pm_stdev_pct,requests_per_sec" > "$OUT"

run_one() {
  local name="$1" port="$2"
  for ((c=1; c<=MAX_CONC; c++)); do
    local t="$MAX_THREADS"; (( t > c )) && t="$c"; (( t == 0 )) && t=1
    echo "[$name] c=$c t=$t  ->  http://$NODE_IP:$port/"
    out="$(wrk -t"$t" -c"$c" -d"$DURATION" "http://$NODE_IP:$port/" 2>&1 || true)"

    # Parse Thread Stats lines
    # Expect: "Latency <avg> <stdev> <max> <+/-stdev%>"
    read -r lat_avg_tok lat_stdev_tok lat_max_tok lat_pm_tok < <(printf '%s\n' "$out" | awk '$1=="Latency"{print $2,$3,$4,$5; exit}')
    read -r rps_avg_tok rps_stdev_tok rps_max_tok rps_pm_tok  < <(printf '%s\n' "$out" | awk '$1=="Req/Sec"{print $2,$3,$4,$5; exit}')

    lat_avg_ms="$(to_ms "$lat_avg_tok")"
    lat_stdev_ms="$(to_ms "$lat_stdev_tok")"
    lat_max_ms="$(to_ms "$lat_max_tok")"
    lat_pm_pct="$(strip_pct "$lat_pm_tok")"

    rps_thread_avg="$(from_si "$rps_avg_tok")"
    rps_thread_stdev="$(from_si "$rps_stdev_tok")"
    rps_thread_max="$(from_si "$rps_max_tok")"
    rps_thread_pm_pct="$(strip_pct "$rps_pm_tok")"

    # Aggregated Requests/sec (all threads)
    rps_agg="$(printf '%s\n' "$out" | awk -F: '/Requests\/sec/ {gsub(/^[ \t]+/,"",$2); print $2; exit}')"
    rps_agg="${rps_agg:-NA}"

    echo "$name,$c,$t,$lat_avg_ms,$lat_stdev_ms,$lat_max_ms,$lat_pm_pct,$rps_thread_avg,$rps_thread_stdev,$rps_thread_max,$rps_thread_pm_pct,$rps_agg" >> "$OUT"

    sleep 2
  done
}

run_one baseline    "$BASE_PORT"
run_one sidecar-tcp "$TCP_PORT"
run_one sidecar-uds "$UDS_PORT"

echo
echo "Results written to: $OUT"

# #!/usr/bin/env bash
# # Bench baseline vs TCP-sidecar vs UDS-sidecar with wrk; dump CSV.
# # Usage: bash bench_sidecars.sh
# # Tunables via env: MAX_CONC (default 64), DURATION (default 30s), MAX_THREADS (default 4), OUT (csv file), NODE_IP

# set -u
# set -o pipefail

# MAX_CONC="${MAX_CONC:-64}"
# DURATION="${DURATION:-30s}"
# MAX_THREADS="${MAX_THREADS:-4}"
# OUT="${OUT:-sidecar_bench_$(date +%Y%m%d_%H%M%S).csv}"

# # add after OUT=...
# while [[ $# -gt 0 ]]; do
#   case "$1" in
#     --node-ip)     NODE_IP="$2"; shift 2 ;;
#     --max-conc)    MAX_CONC="$2"; shift 2 ;;
#     --duration)    DURATION="$2"; shift 2 ;;
#     --max-threads) MAX_THREADS="$2"; shift 2 ;;
#     --out)         OUT="$2"; shift 2 ;;
#     *) echo "Unknown arg: $1" >&2; exit 1 ;;
#   esac
# done

# need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }; }
# need kubectl
# need wrk
# need awk
# need sed

# # Resolve node IP (use the first node's InternalIP unless NODE_IP is preset)
# NODE_IP="${NODE_IP:-}"
# if [[ -z "${NODE_IP}" ]]; then
#   NODE_IP="$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')"
# fi
# if [[ -z "${NODE_IP}" ]]; then
#   echo "Failed to resolve NODE_IP. Set NODE_IP explicitly and retry." >&2
#   exit 1
# fi

# get_nodeport() {
#   local svc="$1"
#   # Expect the http port to be named "http" as in the manifests
#   local p
#   p="$(kubectl get svc "$svc" -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')"
#   if [[ -z "$p" ]]; then
#     # Fallback to first port if name is missing
#     p="$(kubectl get svc "$svc" -o jsonpath='{.spec.ports[0].nodePort}')"
#   fi
#   echo "$p"
# }

# BASE_PORT="$(get_nodeport nginx-baseline-svc)"
# TCP_PORT="$(get_nodeport nginx-sidecar-tcp-svc)"
# UDS_PORT="$(get_nodeport nginx-sidecar-uds-svc)"

# for var in BASE_PORT TCP_PORT UDS_PORT; do
#   if [[ -z "${!var}" ]]; then
#     echo "Service for ${var%_PORT} is not of type NodePort or has no nodePort. Patch the Service or set ports manually." >&2
#     exit 1
#   fi
# done

# echo "Using NODE_IP=$NODE_IP"
# echo " baseline: http://$NODE_IP:$BASE_PORT/"
# echo " sidecar-tcp: http://$NODE_IP:$TCP_PORT/"
# echo " sidecar-uds: http://$NODE_IP:$UDS_PORT/"
# echo

# # CSV header
# echo "variant,concurrency,threads,latency_ms,requests_per_sec" > "$OUT"

# run_one() {
#   local name="$1"
#   local port="$2"

#   for ((c=1; c<=MAX_CONC; c++)); do
#     # Ensure threads ≤ connections to avoid wrk aborts (-t4 -c1)
#     local t="$MAX_THREADS"
#     if (( t > c )); then t="$c"; fi
#     (( t == 0 )) && t=1

#     echo "[$name] c=$c t=$t  ->  http://$NODE_IP:$port/"
#     # Run wrk, capture output (do not exit script on wrk failure)
#     out="$(wrk -t"$t" -c"$c" -d"$DURATION" "http://$NODE_IP:$port/" 2>&1 || true)"

#     # Parse Avg latency token (e.g., 31.35ms / 850us / 0.12s)
#     lat_token="$(printf '%s\n' "$out" | awk '/^[[:space:]]*Latency[[:space:]]/ { print $2; exit }')"
#     # Parse aggregated Requests/sec
#     rps="$(printf '%s\n' "$out" | awk -F: '/Requests\/sec/ { gsub(/^[ \t]+/,"",$2); print $2; exit }')"

#     # Convert latency to ms
#     latency_ms="NA"
#     if [[ -n "${lat_token:-}" ]]; then
#       num_unit="$(printf '%s' "$lat_token" | sed -E 's/^([0-9.]+)(us|ms|s)$/\1 \2/')"
#       val="$(printf '%s\n' "$num_unit" | awk '{print $1}')"
#       unit="$(printf '%s\n' "$num_unit" | awk '{print $2}')"
#       case "$unit" in
#         us) latency_ms="$(awk -v n="$val" 'BEGIN{printf "%.6f", n/1000.0}')" ;;
#         ms) latency_ms="$(awk -v n="$val" 'BEGIN{printf "%.3f", n}')" ;;
#         s)  latency_ms="$(awk -v n="$val" 'BEGIN{printf "%.3f", n*1000.0}')" ;;
#         *)  latency_ms="$val" ;;
#       esac
#     fi

#     rps="${rps:-NA}"
#     echo "$name,$c,$t,$latency_ms,$rps" | tee -a "$OUT" >/dev/null
#   done
# }

# run_one baseline    "$BASE_PORT"
# run_one sidecar-tcp "$TCP_PORT"
# run_one sidecar-uds "$UDS_PORT"

# echo
# echo "Results written to: $OUT"
