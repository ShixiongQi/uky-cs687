Totally. For Online Boutique + HPA, the cleanest way to **see replica counts in real time** is:

* quick & built-in: `kubectl get hpa -w` and `kubectl get deploy -w`
* a UI: **Kubernetes Dashboard**, **Lens**, or **k9s** (TUI)
* production-grade: **Grafana** (with Prometheus + kube-state-metrics) showing HPA + replica metrics live

## Make sure you have a Kubernetes Cluster deployed

Below is an end-to-end recipe you can paste in, including Online Boutique deploy, HPA, and a Grafana dashboard that tracks “function” (service) replica counts in real time.

## TL;DR – What to use to “visualize the real-time number of functions”

* **Fastest**: `kubectl get hpa -w` and `kubectl get deploy -w`
* **Lightweight UI**: **Kubernetes Dashboard**
* **Best dashboards**: **Grafana** with `kube-state-metrics`
  (use the PromQL above for HPA & deployment replica counts)
* **Nice dev experience**: **Lens** or **k9s**

---

# 0) Prereqs (if you haven’t already)

Metrics Server (HPA needs it):

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
# CloudLab often needs insecure TLS for kubelet:
kubectl -n kube-system patch deployment metrics-server --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
kubectl -n kube-system rollout status deploy/metrics-server
```

---

# 1) Deploy Google Online Boutique

```bash
kubectl create namespace boutique
kubectl apply -n boutique -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/main/release/kubernetes-manifests.yaml

# Optional: ensure loadgenerator is on (it is in the default manifest; if you disabled it, re-enable it):
kubectl -n boutique get deploy loadgenerator
```

Wait for pods:

```bash
kubectl -n boutique get pods -w
```

Expose the frontend (for sanity check):

```bash
kubectl -n boutique get svc frontend-external
# If it’s a ClusterIP, you can port-forward:
kubectl -n boutique port-forward svc/frontend-external 8080:80
# In another shell:
curl -sI http://127.0.0.1:8080/
```

---

# 2) Add HPAs (Kubernetes autoscaler)

Example: autoscale `frontend` and `adservice` (tweak targets as you like):

```bash
kubectl -n boutique autoscale deployment frontend --cpu-percent=60 --min=1 --max=20
kubectl -n boutique autoscale deployment adservice --cpu-percent=60 --min=1 --max=20

# Watch HPA react:
kubectl -n boutique get hpa -w
```

You can add HPAs for more services (cartservice, checkoutservice, etc.) the same way.

---

# 3) Real-time visualization options

## A) Quick/CLI (zero install)

```bash
# See desired vs current replicas live
kubectl -n boutique get hpa -w

# See each deployment’s replicas live
kubectl -n boutique get deploy -w

# Top CPU/mem to understand scaling triggers
kubectl -n boutique top pod
kubectl -n boutique top deploy
```

## B) Kubernetes Dashboard (simple UI)

```bash
# Deploy the recommended dashboard
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

# Create a service account & cluster role binding
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
YAML

# Get login token
kubectl -n kubernetes-dashboard create token admin-user

# Access:
kubectl -n kubernetes-dashboard port-forward svc/kubernetes-dashboard-kong-proxy 8443:443
# open https://127.0.0.1:8443 and paste the token
```

Navigate to **Workloads → Deployments** to see live replica counts.

## C) Lens or k9s (nice live views)

* **Lens** (desktop app) connects via your kubeconfig and shows live pods/replicas/HPA.
* **k9s** (terminal UI): `k9s` → navigate to Deployments, HPAs; it auto-refreshes.

## D) Grafana (best for HPA + replicas time series)

Install the full Prometheus + kube-state-metrics + Grafana stack:

```bash
# Install Helm if needed
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install kps prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace

# Wait until up:
kubectl -n monitoring rollout status deploy/kps-grafana
kubectl -n monitoring rollout status statefulset/kps-prometheus-kube-prometheus-prometheus
```

Port-forward Grafana and get the admin password:

```bash
# forward local TCP 3000 on public IP (128.X.X.X) → Service kps-grafana:3000
kubectl -n monitoring port-forward --address=128.X.X.X svc/kps-grafana 3000:80
kubectl -n monitoring get secret kps-grafana -o jsonpath="{.data.admin-password}" | base64 -d; echo
# Open http://127.0.0.1:3000  (user: admin, pass: above)
```

In Grafana, add panels with these **PromQL** queries (real-time “function”/service replicas):

* **HPA Desired vs Current replicas (per service)**

  * *Current*:

    ```
    kube_horizontalpodautoscaler_status_current_replicas{namespace="boutique"}
    ```
  * *Desired*:

    ```
    kube_horizontalpodautoscaler_status_current_replicas{namespace="boutique"}
    ```

  > Use a “Time series” panel with legend `{{hpa}}` (name your HPAs to match deployments).

* **Deployments: desired vs available replicas**

  * *Desired*:

    ```
    kube_deployment_spec_replicas{namespace="boutique"}
    ```
  * *Available*:

    ```
    kube_deployment_status_replicas_available{namespace="boutique"}
    ```

* **Table: current replicas by deployment**

  ```
  kube_deployment_status_replicas{namespace="boutique"}
  ```

  Use a “Table” panel; group by `deployment`, show the value and sort desc.

This gives you live charts showing when autoscaler bumps replica counts and how quickly pods become available.

---

# 4) Increase traffic load

Download the `kubernetes-manifests` of Online Boutique workload.

```bash
wget https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/main/release/kubernetes-manifests.yaml
```

Update the number of users and spawn rate in `loadgenerator`.
```bash
vim kubernetes-manifests.yaml

# Go to the Deployment of loadgenerator, find its env definition

# (LINE#743) Change the value of "USERS" to 1000
# (LINE#745) Change the value of "RATE" to 100

# Save and exit kubernetes-manifests.yaml
```

Reapply the modified `kubernetes-manifests` of Online Boutique workload.
```bash
kubectl apply -n boutique -f kubernetes-manifests.yaml
```

> Now you can observe the number of frentend pods in Grafana.

---

<!-- # 4) Optional: KEDA (event-driven autoscaling)

If you plan to scale on Kafka/Redis/HTTP QPS rather than CPU:

```bash
kubectl create ns keda
helm repo add kedacore https://kedacore.github.io/charts
helm repo update
helm upgrade --install keda kedacore/keda -n keda
```

KEDA exposes metrics you can chart in Grafana similar to HPA metrics.

--- -->
