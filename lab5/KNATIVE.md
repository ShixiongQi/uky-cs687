# 0) What you’ll install

* **Knative Serving (v1.17)** core (CRDs + controllers)
* **Kourier (v1.17)** (lightweight ingress for Knative)

---

# 1) Prereqs (run on your control-plane)

Make sure your cluster is healthy and `kubectl` can reach it. Knative recommends at least **6 CPUs / 6 GB RAM** for a one-node cluster, or **2 CPUs / 4 GB per node** for multi-node.

---

# 2) Install Knative Serving (v1.17.2)

```bash
# CRDs
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.17.2/serving-crds.yaml

# Core controllers
kubectl apply -f https://github.com/knative/serving/releases/download/knative-v1.17.2/serving-core.yaml
```

---

# 3) Add a networking layer (Kourier – recommended)

```bash
# Install Kourier
kubectl apply -f https://github.com/knative/net-kourier/releases/download/knative-v1.17.0/kourier.yaml

# Tell Knative to use Kourier
kubectl patch configmap/config-network \
  --namespace knative-serving \
  --type merge \
  --patch '{"data":{"ingress-class":"kourier.ingress.networking.knative.dev"}}'
```

Then fetch the ingress address:

```bash
kubectl --namespace kourier-system get service kourier
```

---

## CloudLab **doesn’t** have a LoadBalancer

Switch Kourier’s Service to **NodePort** and use your node’s public IP + port:

```bash
# Change LB → NodePort
kubectl -n kourier-system patch svc kourier -p '{"spec":{"type":"NodePort"}}'

# Get the NodePort and test endpoint
kubectl -n kourier-system get svc kourier -o wide
```

---

# 4) Verify Serving comes up

```bash
kubectl get pods -n knative-serving
kubectl get pods -n kourier-system
```

Wait until everything is `Running` or `Completed`.

---

# 5) Configure DNS (NodePort test mode)

Pick any suffix (e.g., `example.com`) and use `curl -H "Host:"` against the node IP + NodePort:

```bash
kubectl patch configmap/config-domain -n knative-serving --type merge \
  -p '{"data":{"example.com":""}}'
# later you'll curl with:  curl -H "Host: <service>.<ns>.example.com" http://<nodeIP>:<nodePort>
```

---

# 6) Deploy a “Hello” Knative Service and test

```bash
cat <<'YAML' | kubectl apply -f -
apiVersion: serving.knative.dev/v1
kind: Service
metadata:
  name: hello
  namespace: default
spec:
  template:
    spec:
      containers:
      - image: gcr.io/knative-samples/helloworld-go:latest
        env:
        - name: TARGET
          value: "Knative"
YAML

# Get the URL (works when Magic/Real DNS is set)
kubectl get ksvc hello

# If using NodePort, first find nodeIP + NodePort:
kubectl -n kourier-system get svc kourier -o jsonpath='{.spec.ports[?(@.port==80)].nodePort}{"\n"}'
# Then call it with Host header:
curl -H "Host: hello.default.example.com" http://<nodeIP>:<nodePort>
```

Knative relies on the `Host` header to route services when you aren’t using proper DNS.

---