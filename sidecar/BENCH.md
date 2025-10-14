# Benchmarking NGINX Sidecar Variants — README

This README explains how to run the `bench_sidecars.sh` script **with command-line flags** to benchmark three Kubernetes deployments:

1. **Baseline**: `nginx-baseline-svc`
2. **Sidecar (TCP)**: `nginx-sidecar-tcp-svc`
3. **Sidecar (UDS)**: `nginx-sidecar-uds-svc`

The script runs `wrk` from the host, sweeping concurrency **1 → 64** (configurable), auto-adjusting `-t` so `threads ≤ connections`, and writes a CSV of **Avg latency (ms)** and **Requests/sec** per run.

---

## Requirements

* A working Kubernetes cluster with the three Services deployed
* Each Service is **type: NodePort**
* Tools installed on the host:

  * `kubectl`, `wrk`, `awk`, `sed`
* Network access to each node’s **InternalIP** on the NodePort range (default `30000–32767`)

If your Services aren’t NodePort yet:

```bash
kubectl patch svc nginx-baseline-svc    -p '{"spec":{"type":"NodePort"}}'
kubectl patch svc nginx-sidecar-tcp-svc -p '{"spec":{"type":"NodePort"}}'
kubectl patch svc nginx-sidecar-uds-svc -p '{"spec":{"type":"NodePort"}}'
```

---

## Add command-line flags (once)

Supported flags (with defaults):

* `--node-ip <IP>`        Node InternalIP to hit (auto-detected if omitted)
* `--max-conc <N>`        Max concurrency to sweep (default: `64`)
* `--duration <Xs|Xm>`    `wrk -d` duration (default: `30s`)
* `--max-threads <N>`     Max `wrk -t` threads (default: `4`)
* `--out <file.csv>`      Output CSV path (default: `sidecar_bench_<timestamp>.csv`)

> The script will **auto-set threads** as `t = min(MAX_THREADS, concurrency)`, ensuring `wrk` never aborts with `-t4 -c1`.

---

## Usage

### Quick start (auto-detect Node IP and ports)

```bash
./bench_sidecars.sh
```

### Specify a Node IP explicitly

```bash
./bench_sidecars.sh --node-ip 10.10.1.1
```

### Customize the sweep, duration, threads, and output file

```bash
./bench_sidecars.sh \
  --node-ip 10.10.1.1 \
  --max-conc 64 \
  --duration 30s \
  --max-threads 8 \
  --out results_sidecar.csv
```

---

## Output format

The script now writes a **richer CSV** with full *Thread Stats* for both **Latency** and **Req/Sec**, plus the aggregated **Requests/sec**:

```
variant,concurrency,threads,lat_avg_ms,lat_stdev_ms,lat_max_ms,lat_pm_stdev_pct,reqps_thread_avg,reqps_thread_stdev,reqps_thread_max,reqps_thread_pm_stdev_pct,requests_per_sec
baseline,1,1,0.812,0.240,2.317,82.15,6200.330,410.220,7100.550,74.10,6150.43
baseline,2,2,1.145,0.360,3.201,79.88,10120.770,680.130,11200.220,71.45,10123.77
sidecar-tcp,64,4,34.721,28.113,120.554,78.42,0.885k,0.210k,1.760k,69.50,3520.18
sidecar-uds,64,4,31.350,24.670,100.990,79.95,0.960k,0.221k,1.990k,69.83,3803.66
```

**Column meanings**

* `variant` — one of `baseline`, `sidecar-tcp`, `sidecar-uds`.
* `concurrency` — `wrk -c` used for this run.
* `threads` — `wrk -t` used (script enforces `threads ≤ concurrency`).
* `lat_avg_ms`, `lat_stdev_ms`, `lat_max_ms` — values from **Thread Stats → Latency** converted to **milliseconds** (handles `us`, `ms`, `s`).
* `lat_pm_stdev_pct` — the **“+/- Stdev”** percentage from **Thread Stats → Latency**.
* `reqps_thread_avg`, `reqps_thread_stdev`, `reqps_thread_max` — values from **Thread Stats → Req/Sec** (these are **per-thread** Req/Sec). Numbers are normalized (supports `k`, `M`, `G` suffixes).
* `reqps_thread_pm_stdev_pct` — the **“+/- Stdev”** percentage from **Thread Stats → Req/Sec**.
* `requests_per_sec` — the **aggregated** Req/Sec across **all threads** (the `Requests/sec:` line).

Use this CSV directly in your plotting scripts (e.g., RPS vs. concurrency, Avg/Max latency vs. concurrency).
