Deploy a Kubernetes cluster on **CloudLab** using **kubeadm**. 

---

## 1. Reserve and Access CloudLab Nodes

1. **Create a new experiment** on [CloudLab](https://www.cloudlab.us/).
2. Pick a cluster and node type (e.g., `c220g1`, `c220g2`) and reserve **1 control-plane (master)** and **≥1 workers**.
3. Choose **Ubuntu 22.04** or similar.
4. Enable **public IPs** for access and connect all nodes to a **private LAN** for pod traffic.
5. SSH into each node:

   ```bash
   ssh <username>@<public-ip>
   ```

---

## 2. Prepare Nodes (all master and workers)

### Disable swap and update

```bash
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
sudo apt update && sudo apt upgrade -y
```

### Install basic packages and containerd

```bash
sudo apt install -y curl apt-transport-https ca-certificates gnupg lsb-release conntrack
sudo apt install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd && sudo systemctl enable containerd
```

### Install CNI plugins

```bash
sudo mkdir -p /opt/cni/bin
curl -L https://github.com/containernetworking/plugins/releases/download/v1.4.0/cni-plugins-linux-amd64-v1.4.0.tgz \
 | sudo tar -C /opt/cni/bin -xz
```

### Kernel modules and sysctls

```bash
sudo modprobe br_netfilter nf_conntrack ip_tables iptable_nat overlay
echo br_netfilter | sudo tee /etc/modules-load.d/k8s.conf
cat <<EOF | sudo tee /etc/sysctl.d/99-k8s-net.conf
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system
```

<!-- ### Use legacy iptables

```bash
sudo apt install -y iptables arptables ebtables
sudo update-alternatives --set iptables  /usr/sbin/iptables-legacy
sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
sudo update-alternatives --set arptables /usr/sbin/arptables-legacy
sudo update-alternatives --set ebtables  /usr/sbin/ebtables-legacy
``` -->

---

## 3. Install Kubernetes Binaries

```bash
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
```

<!-- ---

## 4. Pin Each Node to Its Private LAN IP

CloudLab nodes have multiple NICs. Find the **experiment network interface**:

```bash
ip -o -4 addr show | awk '{print $2, $4}'
```

Suppose it’s `enp6s0f0` with IP `10.10.1.X`. Set kubelet:

```bash
echo 'KUBELET_EXTRA_ARGS=--cgroup-driver=systemd --node-ip=10.10.1.X' | sudo tee /etc/default/kubelet
sudo systemctl daemon-reload
sudo systemctl restart kubelet
``` -->

---

## 4. Initialize the Control Plane (master only)

```bash
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=10.10.1.<MASTER_IP>
```

Set up kubectl for your user:

```bash
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

---

## 5. Install Flannel CNI (master only)

Pin Flannel to the experiment NIC:

```bash
sudo kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
# sudo kubectl -n kube-flannel set env ds/kube-flannel-ds FLANNEL_IFACE=enp6s0f0
# sudo kubectl -n kube-flannel set env ds/kube-flannel-ds FLANNEL_BACKEND=vxlan
# sudo kubectl -n kube-flannel set env ds/kube-flannel-ds FLANNEL_MTU=1450
```

---

## 6. Join Worker Nodes

On **each worker**, run the `kubeadm join …` command printed by `kubeadm init`. Example:

```bash
sudo kubeadm join 10.10.1.<MASTER_IP>:6443 --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
```

---

## 7. Verify Cluster and Networking (master only)

```bash
sudo kubectl get nodes -o wide
sudo kubectl -n kube-flannel get pods -o wide
sudo kubectl -n kube-system get pods -o wide
```

Ensure:

* All nodes show `Ready`.
* Flannel pods `1/1 Running` and `/run/flannel/subnet.env` exists on each node.
* Kube-proxy pods are all `1/1 Running`.

---

## 8. Verify the cluster by deploying NGINX (master only)

### A. Create the Deployment (from the upstream example)

```bash
kubectl apply -f https://k8s.io/examples/application/deployment.yaml
kubectl get pods -l app=nginx -w
```

### B. Inspect the Deployment

```bash
kubectl describe deployment nginx-deployment
kubectl rollout status deployment/nginx-deployment
```

### C. Expose it as a Service (ClusterIP)

```bash
kubectl expose deployment nginx-deployment \
  --name=nginx-svc --port=80 --target-port=80 --type=ClusterIP

kubectl get svc nginx-svc
kubectl get endpoints nginx-svc
```

### D. Use `curl` **inside** the cluster

(Launch a short-lived curl pod and hit the service.)

```bash
kubectl run curl --image=curlimages/curl:8.8.0 --restart=Never -it --rm -- \
  curl -sSI http://nginx-svc
```

You should see `HTTP/1.1 200 OK` headers.

### E. Port-forward to test from your SSH session

```bash
# forward local port 8080 -> NGINX service port 80
kubectl port-forward svc/nginx-svc 8080:80

# forward local TCP 8080 on public IP (128.X.X.X) → Service nginx-svc:80
kubectl port-forward --address=128.X.X.X svc/nginx-svc 8080:80
```

In another terminal:

```bash
curl -sSI http://127.0.0.1:8080/
```

Expect `HTTP/1.1 200 OK`.

> Tip: You can also port-forward the **Deployment** or **Pod** directly:
>
> ```bash
> kubectl port-forward deploy/nginx-deployment 8080:80
> # or
> kubectl port-forward pod/$(kubectl get pod -l app=nginx -o jsonpath='{.items[0].metadata.name}') 8080:80
> ```

<!-- ### F. (Optional) NodePort test from outside

If your CloudLab security rules allow it:

```bash
kubectl expose deploy nginx-deployment --name=nginx-node --type=NodePort --port=80 --target-port=80
NODEPORT=$(kubectl get svc nginx-node -o jsonpath='{.spec.ports[0].nodePort}')
kubectl get nodes -o wide  # pick a node’s External IP (public)
curl -sSI http://<NODE_PUBLIC_IP>:$NODEPORT/
``` -->

### F. Clean up (optional)

```bash
kubectl delete svc nginx-svc nginx-node --ignore-not-found
kubectl delete deployment nginx-deployment
```

<!-- ## 8. Validate DNS

Deploy a busybox shell:

```bash
sudo kubectl run dns-shell --image=busybox:1.36 --restart=Never -it -- sh
# Inside the pod:
cat /etc/resolv.conf
nslookup kubernetes.default
nslookup kube-dns.kube-system.svc.cluster.local
exit
```

You should resolve `kubernetes.default` to `10.96.0.1`.

--- -->
<!-- 
## 10. Optional Enhancements

* **Ingress Controller:**

  ```bash
  sudo kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml
  ```
* **Storage:** Use NFS or hostPath PersistentVolumes for experiments.
* **Monitoring:** Install Prometheus and Grafana via Helm.

---