## Deploy & test quickly

```bash
kubectl apply -f baseline.yaml
kubectl apply -f sidecar-tcp.yaml
kubectl apply -f sidecar-uds.yaml
kubectl rollout status deploy/nginx-baseline
kubectl rollout status deploy/nginx-sidecar-tcp
kubectl rollout status deploy/nginx-sidecar-uds
```

---

## Reapply and restart

```bash
kubectl apply -f baseline.yaml
kubectl apply -f sidecar-tcp.yaml
kubectl apply -f sidecar-uds.yaml
kubectl rollout restart deploy/nginx-baseline
kubectl rollout restart deploy/nginx-sidecar-tcp
kubectl rollout restart deploy/nginx-sidecar-uds
kubectl rollout status deploy/nginx-baseline
kubectl rollout status deploy/nginx-sidecar-tcp
kubectl rollout status deploy/nginx-sidecar-uds
```

---

## Use **NodePort** like this:

### 1) Switch your Services to NodePort

```bash
kubectl patch svc nginx-baseline-svc    -p '{"spec":{"type":"NodePort"}}'
kubectl patch svc nginx-sidecar-tcp-svc -p '{"spec":{"type":"NodePort"}}'
kubectl patch svc nginx-sidecar-uds-svc -p '{"spec":{"type":"NodePort"}}'
```

### 2) Get a node IP

Any node’s IP will work (NodePort listens on every node). Grab an InternalIP:

```bash
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo $NODE_IP
```

If you need a specific node:

```bash
kubectl get nodes -o wide
# then:
NODE_IP=$(kubectl get node <node-name> -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
```

### 3) Get each Service’s NodePort

```bash
BASE_PORT=$(kubectl get svc nginx-baseline-svc    -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
TCP_PORT=$(kubectl  get svc nginx-sidecar-tcp-svc -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
UDS_PORT=$(kubectl  get svc nginx-sidecar-uds-svc -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
echo $BASE_PORT $TCP_PORT $UDS_PORT
```

### 4) Hit them from outside the cluster

```bash
wrk -t4 -c64 -d30s http://$NODE_IP:$BASE_PORT/
wrk -t4 -c64 -d30s http://$NODE_IP:$TCP_PORT/
wrk -t4 -c64 -d30s http://$NODE_IP:$UDS_PORT/
```

---

## Notes to keep your measurements clean

* All three configs return the **same tiny body** (`"ok\n"`) to minimize disk I/O bias.
* In the TCP sidecar case, the app binds `127.0.0.1:8081` and the sidecar proxies from `:8080` → `127.0.0.1:8081`.
* In the UDS sidecar case, both containers share `/var/run/app` via `emptyDir` and the app **listens on** `unix:/var/run/app/app.sock`.
* `fsGroup: 2000` ensures the shared volume is group-writable; this avoids socket permission issues.
* Keep resource limits the same across variants (already set) so the scheduler doesn’t skew results.
* For higher load, bump `worker_connections` and consider setting `worker_processes` to a fixed number across all three to control concurrency.

If you want me to add TLS termination, HTTP keep-alive tuning, or a synthetic CPU “work” handler to simulate app logic, say the word and I’ll drop in those variants too.
