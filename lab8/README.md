# Lab 8: Evaluating Kernel and Kernel-Bypass NGINX Performance

## 1. Overview

This lab aims to help you **understand the performance overheads of the Linux kernel network stack** and observe the performance benefits of **kernel-bypass networking (DPDK)** through F-Stack.

You will conduct two experiments on a two-node setup:

1. **Part I:** Measure the performance of the standard (kernel-based) NGINX.
2. **Part II:** Measure the performance of F-Stack-based NGINX (built on DPDK).

By the end of this lab, you should:

* Quantify throughput (RPS) and latency of both designs.
* Observe and analyze CPU usage patterns.
* Understand why DPDK’s kernel-bypass design improves performance.

---

## 2. Experimental Setup

### Hardware and OS

| Node     | Role                | NIC        | OS           |
| -------- | ------------------- | ---------- | ------------ |
| `node-0` | Server (runs NGINX) | Intel X710 | Ubuntu 22.04 |
| `node-1` | Client (runs wrk)   | Intel X710 | Ubuntu 22.04 |

### Network Configuration

* Connect both nodes via a 10 GbE switch.
* Assign IPs on the same subnet:

  * `node-0`: `10.10.1.1`
  * `node-1`: `10.10.1.2`

---

## 3. Part I — Kernel-Stack NGINX Performance

### 3.1. Install and Configure NGINX (on node-0)

```bash
sudo apt update
sudo apt install -y nginx wrk htop sysstat
sudo systemctl stop nginx
sudo nginx
```

<!-- Edit `/etc/nginx/nginx.conf` (or use a custom config) to ensure:

```nginx
worker_processes  auto;
worker_connections  65535;

events {
    use epoll;
    multi_accept on;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;

    server {
        listen 80 reuseport;
        root /var/www/html;
        index index.html;
    }
}
``` -->

<!-- Restart NGINX:

```bash
sudo systemctl restart nginx
``` -->

### 3.2. Generate Load with wrk (on node-1)

```bash
wrk -t8 -c512 -d60s --timeout 2s --latency http://10.10.1.1/
```

This runs 8 threads, 512 concurrent connections, for 60 seconds.

### 3.3. Collect Measurements (on node-0)

Use `htop` and `mpstat` to monitor CPU activity.

Example:

```bash
htop
```

```bash
mpstat 1
```

### 3.4. Record Results

For each run, record:

* **Requests per second (RPS)**
* **Latency distribution (avg, p90, p99)**
* **CPU utilization of NGINX (user, system, softirq)**

---

## 4. Part II — F-Stack (DPDK-Based) NGINX

### 4.1. Install Dependencies

```bash
sudo apt update

# Install conda (optional)
wget https://repo.anaconda.com/miniconda/Miniconda3-py39_23.3.1-0-Linux-x86_64.sh
chmod +x Miniconda3-py39_23.3.1-0-Linux-x86_64.sh
bash Miniconda3-py39_23.3.1-0-Linux-x86_64.sh -b -p ~/miniconda3
source ~/miniconda3/bin/activate
conda init bash
source $HOME/.bashrc

# Create conda env (optional)
conda create -n ingress python=3.10 -y
conda activate ingress

# Install build dependencies (TODO: remove unnecessary deps)
sudo apt update && sudo apt install -y flex bison build-essential dwarves libssl-dev libelf-dev \
                    libnuma-dev pkg-config python3-pip python3-pyelftools \
                    libconfig-dev golang clang gcc-multilib uuid-dev sysstat gawk libpcre3 libpcre3-dev libglib2.0-dev

pip3 install meson ninja
pip3 install pyelftools --upgrade
```

### 4.2. Get and Build F-Stack

```bash
git clone https://github.com/F-Stack/f-stack.git
cd f-stack
git checkout df0df1a
```

Configure DPDK:

```bash
# Compile DPDK (21.11)
cd ~/f-stack/dpdk/
meson setup -Denable_kmods=true build
ninja -C build
sudo ninja -C build install

# Set hugepage at system-wide (Option#1)
sudo sysctl -w vm.nr_hugepages=16384

# Using Hugepage with the DPDK
sudo mkdir /mnt/huge
sudo mount -t hugetlbfs nodev /mnt/huge

# Close ASLR; it is necessary in multiple process (use root)
sudo -s

echo 0 > /proc/sys/kernel/randomize_va_space

# Install the DPDK driver (igb_uio) for Intel NICs (Not needed for Mellanox NICs)
modprobe uio
insmod f-stack/dpdk/build/kernel/linux/igb_uio/igb_uio.ko
insmod f-stack/dpdk/build/kernel/linux/kni/rte_kni.ko carrier=on # carrier=on is necessary, otherwise need to be up `veth0` via `echo 1 > /sys/class/net/veth0/carrier`

# Leave root
Type `ctrl + d`

# Bind NICs to DPDK (only for Intel NICs)
python dpdk-devbind.py --status
sudo ifconfig XXX down
python dpdk-devbind.py --bind=igb_uio XXX

# Compile and install F-Stack
export FF_PATH=~/f-stack
export PKG_CONFIG_PATH=/usr/lib64/pkgconfig:/usr/local/lib64/pkgconfig:/usr/lib/pkgconfig
cd ~/f-stack/lib/
make -j
sudo make install
```

### 4.3. Build F-Stack NGINX

```bash
cd ~/f-stack/app/nginx-1.25.2
bash ./configure --prefix=/usr/local/nginx_fstack --with-ff_module
make
sudo make install
```

> You will encounter an error! How to fix it?

Start F-Stack NGINX:

```bash
# Run NGINX not as a daemon
sudo /usr/local/nginx_fstack/sbin/nginx -g "daemon off;"
```

> You will encounter an error! How to fix it?

Modify F-stack configuration
```bash
sudo vim /usr/local/nginx_fstack/conf/f-stack.conf
```

Start F-Stack NGINX Again:

```bash
# Run NGINX not as a daemon
sudo /usr/local/nginx_fstack/sbin/nginx -g "daemon off;"
```

### 4.4. Run the Same Benchmark (on node-1)

Run the same wrk command as in Part I:

```bash
wrk -t8 -c512 -d60s --timeout 2s --latency http://10.10.1.1/
```

### 4.5. Measure and Record

As before, measure:

* **RPS**
* **Latency (p50, p90, p99)**
* **CPU utilization**

---

## 5. Analysis and Discussion

### Compare the two setups:

| Metric                                | Kernel NGINX | F-Stack NGINX |
| ------------------------------------- | ------------ | ------------- |
| Requests per Second                   |              |               |
| Avg / p99 Latency                     |              |               |
| CPU Utilization                       |              |               |

### Discussion Questions

1. Which implementation achieves higher throughput and lower latency?
2. What explains the CPU utilization difference between the two?
3. Which kernel components (e.g., softirq, TCP stack, context switches) dominate in the kernel-based NGINX?
4. How does DPDK (F-Stack) avoid these overheads?

   * Hint: consider packet I/O path differences — user-space poll-mode driver vs. kernel interrupt path.
5. When might kernel-bypass be less beneficial?

---

## 6. Deliverables

Submit a **lab report** containing:

* Your NGINX configuration.
* Benchmark results (RPS, latency histograms).
* CPU utilization and perf output screenshots.
* A short paragraph explaining **why kernel-bypass improves performance**.

---