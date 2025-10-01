# Autoscale Sample App — Go

A demonstration of Knative Serving autoscaling, updated to use **`wrk`** and the Host header `autoscale-go.default.example.com` (NodePort / Kourier-NodePort style access).

## Prerequisites

* A Kubernetes cluster with **Knative Serving** installed and configured to route with the domain `example.com` (so your service host is `autoscale-go.default.example.com`).
* **Ingress access** via a node IP and **NodePort** (or LoadBalancer). You’ll curl/wrk the node IP:port and set the Host header to the Knative service host.
* The `wrk` load generator installed:

  ```bash
  # Ubuntu/Debian (repo availability varies)
  sudo apt-get update && sudo apt-get install -y wrk || true
  
  # Or build from source:
  # git clone https://github.com/wg/wrk.git && cd wrk && make
  # sudo cp wrk /usr/local/bin/
  ```
* Clone the docs repo and move into the sample:

  ```bash
  git clone -b release-1.17 https://github.com/knative/docs knative-docs
  cd knative-docs
  ```

---

## Deploy the Service

```bash
kubectl apply -f docs/serving/autoscaling/autoscale-go/service.yaml
```

Obtain the URL of the service (once Ready). If you set your domain to `example.com`, it will be:

```
NAME           URL                                   LATESTCREATED       LATESTREADY        READY
autoscale-go   http://autoscale-go.default.example.com   autoscale-go-xxxxx autoscale-go-xxxxx True
```

> When using NodePort/Host header, you’ll actually send traffic to `http://<NODE_IP>:<NODE_PORT>/...` **with** `-H "Host: autoscale-go.default.example.com"`.

---

## Load the Service

### Quick single request

```bash
curl -H "Host: autoscale-go.default.example.com" \
  "http://<NODE_IP>:<NODE_PORT>/?sleep=100&prime=10000&bloat=5"
```

Example (your IP/port may differ):

```bash
curl -H "Host: autoscale-go.default.example.com" \
  "http://128.105.145.232:32427/?sleep=100&prime=10000&bloat=5"
```

### 30 seconds, ~100 open connections with `wrk`

```bash
wrk -t4 -c100 -d30s \
  -H "Host: autoscale-go.default.example.com" \
  "http://<NODE_IP>:<NODE_PORT>/?sleep=100&prime=10000&bloat=5"

kubectl get pod -w
```

Example using your node IP/port:

```bash
wrk -t4 -c100 -d30s \
  -H "Host: autoscale-go.default.example.com" \
  "http://128.105.145.232:32427/?sleep=100&prime=10000&bloat=5"
```

You should see multiple `autoscale-go-<revision>-deployment-...` pods spin up.

---

## Analysis

### Algorithm

Knative Serving autoscaling (KPA) targets average **in-flight requests per pod** (concurrency). Default target ~100 (configurable), and in this sample it’s **10**. If you drive ~50 concurrent requests, the autoscaler converges near **5 pods** (50/10).

### Panic

Autoscaler uses a **60s stable window** and a **6s panic window**. If the 6s window exceeds **2× target**, it enters panic mode (faster scaling). After 60s without panic conditions, it returns to the stable window.

```
                                                       |
                                  Panic Target--->  +--| 20
                                                    |  |
                                                    | <------Panic Window
                                                    |  |
       Stable Target--->  +-------------------------|--| 10   CONCURRENCY
                          |                         |  |
                          |                      <-----------Stable Window
                          |                         |  |
--------------------------+-------------------------+--+ 0
120                       60                           0
                     TIME
```

---

## Customization

Two autoscaler classes:

* `kpa.autoscaling.knative.dev` — **concurrency-based** (default)
* `hpa.autoscaling.knative.dev` — delegates to Kubernetes **HPA (CPU)**

### Example: scale on CPU (HPA)

```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: autoscale-go
  namespace: default
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/class: hpa.autoscaling.knative.dev
        autoscaling.knative.dev/metric: cpu
    spec:
      containers:
        - image: ghcr.io/knative/autoscale-go:latest
```

### Example: custom concurrency target & bounds (KPA)

```yaml
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: autoscale-go
  namespace: default
spec:
  template:
    metadata:
      annotations:
        autoscaling.knative.dev/class: kpa.autoscaling.knative.dev
        autoscaling.knative.dev/metric: concurrency
        autoscaling.knative.dev/target: "10"     # target in-flight per pod
        autoscaling.knative.dev/min-scale: "1"   # disable scale-to-zero
        autoscaling.knative.dev/max-scale: "100"
    spec:
      containers:
        - image: ghcr.io/knative/autoscale-go:latest
```

> **Note:** For `hpa.autoscaling.knative.dev`, `autoscaling.knative.dev/target` is the **CPU%** target (default `"80"`).

---

## Other Experiments (with `wrk` + Host header)

> Standard `wrk` controls **connections**, not exact QPS. For fixed QPS tests, use **wrk2** (`-R 100`). Below are practical `wrk` variants that drive sustained load.

* **60s with ~100 concurrent connections, 100ms work:**

  ```bash
  wrk -t4 -c100 -d60s \
    -H "Host: autoscale-go.default.example.com" \
    "http://<NODE_IP>:<NODE_PORT>/?sleep=100&prime=10000&bloat=5"
  ```

* **Short requests (~10ms):**

  ```bash
  wrk -t4 -c100 -d60s \
    -H "Host: autoscale-go.default.example.com" \
    "http://<NODE_IP>:<NODE_PORT>/?sleep=10"
  ```

* **Long requests (~1s):**

  ```bash
  wrk -t4 -c100 -d60s \
    -H "Host: autoscale-go.default.example.com" \
    "http://<NODE_IP>:<NODE_PORT>/?sleep=1000"
  ```

* **CPU-heavy (large prime calc):**

  ```bash
  wrk -t4 -c100 -d60s \
    -H "Host: autoscale-go.default.example.com" \
    "http://<NODE_IP>:<NODE_PORT>/?prime=40000000"
  ```

* **Memory-heavy (1 GB/request):**

  ```bash
  wrk -t4 -c5 -d60s \
    -H "Host: autoscale-go.default.example.com" \
    "http://<NODE_IP>:<NODE_PORT>/?bloat=1000"
  ```

Replace `<NODE_IP>:<NODE_PORT>` with your actual endpoint (e.g., `128.105.145.232:32427`).

---

## Cleanup

```bash
kubectl delete -f docs/serving/autoscaling/autoscale-go/service.yaml
```