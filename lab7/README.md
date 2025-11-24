# Understanding Linux Network Stack

**Topology**

* **Server (node0)**: Ubuntu 22.04, 40 CPU cores, Intel 10 GbE (e.g., X520).
  Runs **NGINX** and **all measurements (perf)**. IP: **10.10.1.1**.
* **Client (node1)**: Ubuntu 22.04 (or similar).
  Runs **wrk** only. No measurements needed here.
* Connected via a switch (10 GbE). Keep default OS/NIC settings (no IRQ/offload toggling).

---

## 1) Objectives

1. Use **perf** to quantify where CPU time goes in a high-throughput HTTP server.
2. Attribute **kernel network stack** costs: device driver RX/TX, IP/TCP processing, socket layer, syscalls, and NGINX user-space work.
3. Inspect **tracepoints** (e.g., `napi:*`, `net:*`, `tcp:*`, `syscalls:*`) to link performance counters to concrete code paths.
4. Observe **context switching** and run-queue effects relevant to network I/O (without changing system config).

---

## 2) Setup (node0 & node1)

### 2.1 Install required tools

**node0 (server, measurement host)**

```bash
sudo apt update
sudo apt install -y nginx wrk linux-tools-common linux-tools-$(uname -r) \
                   linux-headers-$(uname -r) bpftrace hwloc jq
# Optional (better kernel symbol resolution):
# sudo apt install -y linux-image-$(uname -r)-dbgsym  # from ddebs; skip if not available
```

**node1 (client)**

```bash
sudo apt update
sudo apt install -y wrk
```

> If `perf` shows “Permission denied”, run experiments with `sudo` on node0.

### 2.2 Minimal NGINX config (node0)

Use default package config. Prepare static payloads to exercise different paths:

```bash
sudo mkdir -p /var/www/html/blob1m /var/www/html/blob8m
head -c 1048576 </dev/urandom | sudo tee /var/www/html/blob1m/1m.bin >/dev/null
head -c 8388608 </dev/urandom | sudo tee /var/www/html/blob8m/8m.bin >/dev/null
sudo systemctl restart nginx
```

Verify:

```bash
curl -I http://10.10.1.1/
curl -I http://10.10.1.1/blob1m/1m.bin
curl -I http://10.10.1.1/blob8m/8m.bin
```

---

## 3) Workloads (run on node1)

We will run three standard HTTP patterns to light up different kernel paths:

* **S1: Small static file** (header-heavy, higher request rate)
* **S2: 1 MiB object** (balanced syscall/data path)
* **S3: 8 MiB object** (sustained send path; GRO/TSO/etc. get exercised)

Each test runs **60 s**, multiple threads/connections. Adjust `-t/-c` if node1 is weak.

```bash
# On node1
# S1: small file (/) — lots of requests, stresses accept/epoll/TCP small sends
wrk -t16 -c1024 -d60s --latency http://10.10.1.1/ > S1_small.txt

# S2: 1 MiB blob — balanced
wrk -t16 -c256  -d60s --latency http://10.10.1.1/blob1m/1m.bin > S2_1m.txt

# S3: 8 MiB blob — sustained throughput per connection
wrk -t16 -c64   -d60s --latency http://10.10.1.1/blob8m/8m.bin > S3_8m.txt
```

> Keep node1 quiet otherwise. **Do not** run measurement tools on node1.

---

## 4) Measurement plan (all on node0)

We use **perf** in three layers, from coarse → fine:

1. **Top-level counters** (`perf stat`) while the run is happening.
2. **Hotspot & call stacks** (`perf top` and `perf record/report`) to identify user vs kernel hot code paths.
3. **Tracepoints** (`perf record -e tracepoint`) to map costs to specific network-stack stages (NAPI, GRO, TCP RX/TX, syscalls).
4. **Scheduling/CS** (`perf sched`) to see voluntary context switches and run-queue behavior.

Create a results directory per scenario:

```bash
TS=$(date +%Y%m%d-%H%M%S)
mkdir -p ~/lab7_results/$TS
cd ~/lab7_results/$TS
```

### 4.1 Get PIDs of NGINX workers (for targeted profiling)

```bash
pgrep -x nginx        > pids_all.txt
pgrep -P $(pgrep -xo nginx) > pids_workers.txt   # child workers only
cat pids_workers.txt
```

---

## 5) Layer 1 — System-wide counters (perf stat)

Run **on node0** *during* the node1 wrk test window (start stat slightly before):

```bash
# System-wide view: hardware, software, and key tracepoints counters
sudo perf stat -a -D 2000 -e cycles,instructions,branches,branch-misses,ref-cycles,cpu-clock,task-clock,context-switches,cpu-migrations,page-faults,syscalls:sys_enter_accept4,syscalls:sys_enter_epoll_wait,syscalls:sys_enter_read,syscalls:sys_enter_write,syscalls:sys_enter_sendto,syscalls:sys_enter_sendmsg  -- sleep 10
```

**What to look for**

* `context-switches` (total) scaling with concurrency; relate later to voluntary CS (Section 8).
* `syscalls:*` counts reflect syscalls pressure from NGINX workers.

**Observe the difference between with and without running `wrk`?**

---

## 6) Layer 2 — Hotspots & call stacks

### 6.1 Offline recording (perf record/report) — kernel+user call graphs

Record for each scenario (S1/S2/S3) while wrk runs:

```bash
# Record system-wide with call stacks; 60s window is enough
sudo perf record -a -F 99 --call-graph dwarf -g -- \
  sleep 10
sudo perf report --stdio --show-total-period -g graph
```

**What is the most significant overhead contributor?**

<!-- (Optional: target only NGINX workers)

```bash
sudo perf record -F 99 --call-graph dwarf -g -p $(paste -sd, pids_workers.txt) -- sleep 10
sudo perf report --stdio -g graph
``` -->

**What to annotate in your lab notes**

* %CPU in **kernel** vs **user** for each scenario.
* Top stacks on the **TX path** (send side) under load (S2/S3): e.g.,
  `nginx -> sendfile -> tcp_sendmsg -> tcp_push -> ip_queue_xmit -> dev_queue_xmit -> driver_tx`.
* **RX/accept** under S1: `inet_csk_accept` / `sys_accept4` / `epoll_wait` wakeups.

---

## 7) Layer 3 — Tracepoints for the network stack

We now capture **named kernel tracepoints** to connect time/cycles to pipeline stages.

### 7.1 RX path / NAPI

```bash
sudo perf record -a -F 99 --call-graph dwarf -g \
  -e napi:napi_poll \
  -e net:netif_receive_skb \
  -e net:netif_receive_skb_entry \
  -- sleep 10
sudo perf script
```

**Readouts:**

* `napi_poll` bursts (how often, how long call stacks run);
* Stacks under `netif_receive_skb*` show IP/TCP RX handlers beneath.

### 7.2 TX path

```bash
sudo perf record -a -F 99 --call-graph dwarf -g \
  -e net:net_dev_queue \
  -e net:net_dev_xmit \
  -- sleep 10
sudo perf script
```

**Readouts:**

* Where packets enter qdisc/device (`net_dev_queue`), time in driver xmit paths;
* Stacks should include `tcp_sendmsg` → `ip_queue_xmit` → `dev_queue_xmit` → driver.

### 7.3 TCP-specific

```bash
sudo perf record -a -F 99 --call-graph dwarf -g \
  -e tcp:tcp_probe \
  -e tcp:tcp_retransmit_skb \
  -e tcp:tcp_receive_reset \
  -e tcp:tcp_rcv_space_adjust \
  -- sleep 10
sudo perf script
```

**Readouts:**

* Congestion/rcvspace dynamics (`tcp_probe`, `tcp_rcv_space_adjust`).
* Retransmits (should be near zero on a clean LAN); if non-zero, note stacks.

### 7.4 Syscall boundaries (for attribution)

```bash
sudo perf record -a -F 99 --call-graph dwarf -g \
  -e syscalls:sys_enter_accept4 \
  -e syscalls:sys_exit_accept4 \
  -e syscalls:sys_enter_epoll_wait \
  -e syscalls:sys_exit_epoll_wait \
  -- sleep 10
sudo perf script
```

**Readouts:**

* Rate and latency of accept/epoll in steady state;
* Verify NGINX workers spend substantial time in `epoll_wait` when not actively sending.

---

## 8) Scheduling & context switches (perf sched)

We’ll inspect **voluntary context switches** (task yields, blocking on I/O, etc.) vs **involuntary** (preempted). `perf sched` uses `sched:*` tracepoints.

### 8.1 Whole-system time histogram

```bash
sudo perf sched record -- sleep 10
sudo perf sched timehist --state
```

Look for:

* NGINX workers transitioning to `S` (sleep) when waiting in `epoll_wait` → **voluntary CS**.
* Preemptions when CPU contention is high (NGINX vs ksoftirqd, etc.) → **involuntary CS**.

### 8.2 Per-process view (NGINX workers only)

```bash
sudo perf sched record -p $(paste -sd, pids_workers.txt) -- sleep 10
sudo perf sched timehist --pid $(paste -sd, pids_workers.txt) --state
```

**Interpretation guide**

* **Voluntary context switch**: the thread blocks (e.g., `epoll_wait`, `accept`), hands off CPU willingly.
* **Involuntary**: the thread is preempted by scheduler (time slice expired or higher-prio runnable).
* In HTTP workloads, expect many **voluntary CS** from NGINX workers (I/O wait), fewer involuntary CS unless the run queue is hot.

---

## 9) Putting it together — What to analyze per scenario

For each of **S1, S2, S3**:

1. **Throughput/latency (node1 wrk output)**: RPS, p50-p999.
2. **L1 perf stat**: overall cycles/instructions; syscall counts.
3. **L2 perf report**: top stacks (user vs kernel); relative time in TCP/IP/driver vs NGINX.
4. **L3 tracepoints**:

   * RX path intensity: `napi_poll`.
   * TX queueing: `net_dev_queue`, `net_dev_xmit` stacks.
   * TCP behavior: retransmits (should be low), rcv space adjustments.
   * Syscall boundaries: accept/epoll rates.
5. **L4 scheduling**: are workers mostly blocked in epoll (voluntary CS)? Any long waits or bursts of preemptions?

**Expected qualitative trends**

* **S1** (small file): higher request rate → more accepts/epoll cycles; kernel shows more per-packet work; noticeable `NET_RX` softirqs; many **voluntary CS** due to frequent epoll sleeps/wakeups.
* **S2/S3** (larger blobs): fewer requests but heavier send paths; stacks feature `tcp_sendmsg`/`ip_queue_xmit`/driver; `napi` and `gro_*` appear in RX (acks) but TX dominates. `sendfile` keeps user-space overhead modest; kernel dominates CPU.
