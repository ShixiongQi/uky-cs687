Build **all** Online Boutique (microservices-demo) images and push them to **Docker Hub**.

> The repo contains 11 services: `adservice, cartservice, checkoutservice, currencyservice, emailservice, frontend, loadgenerator, paymentservice, productcatalogservice, recommendationservice, shippingservice`. They live under `src/` in the repo. ([GitHub](https://github.com/GoogleCloudPlatform/microservices-demo))

---

# Register your Docker Hub via the Website

- Visit https://hub.docker.com/signup
- Choose a Docker ID (this becomes your namespace, e.g., docker.io/your-id).
- Enter your email and create a password.
- Check your email for a verification message and confirm your account.
<!-- (Optional but recommended) Enable two-factor authentication under Account Settings → Security. -->

# 1) Prereqs (one-time)

Install Docker
```bash
sudo apt update
sudo apt install -y ca-certificates curl gnupg lsb-release

# Add Docker’s official GPG key
sudo mkdir -m 0755 -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up the repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start and enable the service
sudo systemctl enable --now docker
```

Post-install steps (Optional, to run Docker without `sudo`):
```bash
sudo groupadd docker    # may already exist
sudo usermod -aG docker $USER
newgrp docker
```

```bash
# Docker (24+ recommended), Git
docker --version
git --version

# Log in to Docker Hub (creates repos on first push if they don't already exist)
docker login
```

If you’ll deploy to **mixed CPU architectures** (x86\_64 + arm64), set up Buildx once:

```bash
docker buildx create --name microdemo --use
# optional but helpful to emulate other arch locally
docker run --privileged --rm tonistiigi/binfmt --install all
```

---

# 2) Clone a known release (recommended)

Use a tagged release so your images are traceable (e.g., the latest as of now is `v0.10.3`). ([GitHub][1])

```bash
git clone https://github.com/GoogleCloudPlatform/microservices-demo.git
cd microservices-demo
git checkout v0.10.0
```

---

# 3) Set a few variables

```bash
# replace with your Docker Hub username/org
export REG="docker.io/<your-dockerhub-username>"

# choose a tag (use the git tag for reproducibility)
export TAG="v0.10.0"

# the list of services in this repo
export SERVICES="adservice cartservice checkoutservice currencyservice emailservice \
frontend loadgenerator paymentservice productcatalogservice recommendationservice shippingservice"
```

---

# 4A) Quick build & push (single-arch)

If you’re building on the same architecture you’ll run (e.g., amd64->amd64 or arm64->arm64):

```bash
for svc in $SERVICES; do
  if [ "$svc" = "cartservice" ]; then
    # CartService's Dockerfile and context are nested in src/
    docker build -t $REG/$svc:$TAG \
      -f ./src/$svc/src/Dockerfile ./src/$svc/src
  else
    docker build -t $REG/$svc:$TAG \
      -f ./src/$svc/Dockerfile ./src/$svc
  fi
  docker push $REG/$svc:$TAG
done

```

---

# 4B) Multi-arch build & push (recommended)

Build once for **linux/amd64** and **linux/arm64** and push a manifest list so it runs anywhere:

```bash
for svc in $SERVICES; do
  if [ "$svc" = "cartservice" ]; then
    docker buildx build \
      --platform linux/amd64,linux/arm64 \
      -t $REG/$svc:$TAG \
      -f ./src/$svc/src/Dockerfile ./src/$svc/src \
      --push
  else
    docker buildx build \
      --platform linux/amd64,linux/arm64 \
      -t $REG/$svc:$TAG \
      -f ./src/$svc/Dockerfile ./src/$svc \
      --push
  fi
done

```

---

# 5) Sanity-check your pushes

```bash
# pull one image back to verify
docker pull $REG/frontend:$TAG
```

You should now have 11 images on Docker Hub, one per service, all tagged `v0.10.0`.

---

## Notes & tips

* If a build fails because of language toolchains (Go/Java/.NET/Node/Python), just re-run; each service’s Dockerfile fetches its own dependencies during build.
* If you plan to deploy the app’s Kubernetes manifests using **your** images, point your manifests (or Helm/Kustomize overlays) at `docker.io/<you>/<service>:<tag>`. The repo’s README lists each service so you can match names 1:1.
* Prefer building from a tagged release (e.g., `v0.10.0`) rather than `main` for reproducibility.