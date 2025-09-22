Docker run guide (no Kubernetes) for Online Boutique. You’ll start a private Docker network, then bring up each dependency in a sane order and verify as you go.

---

# 0) Prep once

```bash
# Create an isolated network so containers can resolve each other by name
docker network create boutique

# Choose where your images come from:
#   (A) Your own registry (if you built & pushed): docker.io/<you>
#   (B) Official registry: gcr.io/google-samples/microservices-demo
export REG="<your-docker-hub-id>"   # change to your Docker Hub ID if using your images
export TAG="v0.10.0"                                    # or your tag

# Helper: run this to quickly resolve a service name from inside the network
# docker run --rm --network boutique nicolaka/netshoot dig productcatalogservice
```

---

# 1) Redis (Cart DB)

```bash
docker run -d --name redis-cart --network boutique \
  --restart unless-stopped \
  redis:alpine \
  redis-server --save "" --appendonly no
```

**Verify:**

```bash
docker logs redis-cart --tail 20
```

---

# 2) Product Catalog

```bash
docker run -d --name productcatalogservice --network boutique \
  --restart unless-stopped \
  -e PORT=3550 \
  -e DISABLE_PROFILER=1 \
  $REG/productcatalogservice:$TAG
```

(Exposes gRPC on **3550** inside the network.)

---

# 3) Currency

```bash
docker run -d --name currencyservice --network boutique \
  --restart unless-stopped \
  -e DISABLE_PROFILER=1 \
  -e PORT=8083 \
  $REG/currencyservice:$TAG
```

(Exposes HTTP on **8083**.)

---

# 4) Payment

```bash
docker run -d --name paymentservice --network boutique \
  --restart unless-stopped \
  -e PORT=50052 \
  -e DISABLE_PROFILER=1 \
  $REG/paymentservice:$TAG
```

(gRPC on **50052**.)

---

# 5) Shipping

```bash
docker run -d --name shippingservice --network boutique \
  --restart unless-stopped \
  -e PORT=50051 \
  -e DISABLE_PROFILER=1 \
  $REG/shippingservice:$TAG
```

(gRPC on **50051**.)

---

# 6) Email

```bash
docker run -d --name emailservice --network boutique \
  --restart unless-stopped \
  -e DISABLE_PROFILER=1 \
  -e PORT=8080 \
  $REG/emailservice:$TAG
```

(HTTP on **8080**.)

---

# 7) Recommendation

Depends on Product Catalog.

```bash
docker run -d --name recommendationservice --network boutique \
  --restart unless-stopped \
  -e PRODUCT_CATALOG_SERVICE_ADDR=productcatalogservice:3550 \
  -e PORT=8082 \
  -e DISABLE_PROFILER=1 \
  $REG/recommendationservice:$TAG
```

(HTTP on **8082**.)

---

# 8) Cart

Depends on Redis.

```bash
docker run -d --name cartservice --network boutique \
  --restart unless-stopped \
  -e REDIS_ADDR=redis-cart:6379 \
  $REG/cartservice:$TAG
```

(HTTP on **7070**.)

---

# 9) Checkout

Depends on many services.

```bash
docker run -d --name checkoutservice --network boutique \
  --restart unless-stopped \
  -e PORT=5050 \
  -e PRODUCT_CATALOG_SERVICE_ADDR=productcatalogservice:3550 \
  -e SHIPPING_SERVICE_ADDR=shippingservice:50051 \
  -e PAYMENT_SERVICE_ADDR=paymentservice:50052 \
  -e EMAIL_SERVICE_ADDR=emailservice:8080 \
  -e CURRENCY_SERVICE_ADDR=currencyservice:8083 \
  -e CART_SERVICE_ADDR=cartservice:7070 \
  $REG/checkoutservice:$TAG
```

(HTTP on **5050**.)

---

# 10) Ads

```bash
docker run -d --name adservice --network boutique \
  --restart unless-stopped \
  -e PORT=9555 \
  $REG/adservice:$TAG
```

(gRPC on **9555**.)

---

# 11) Frontend (expose to your host)

Depends on everything above. This is the only container we’ll **publish** to localhost.

```bash
docker run -d --name frontend --network boutique \
  --restart unless-stopped \
  -p 8080:8081 \
  -e PORT=8081 \
  -e PRODUCT_CATALOG_SERVICE_ADDR=productcatalogservice:3550 \
  -e CURRENCY_SERVICE_ADDR=currencyservice:8083 \
  -e CART_SERVICE_ADDR=cartservice:7070 \
  -e RECOMMENDATION_SERVICE_ADDR=recommendationservice:8082 \
  -e SHIPPING_SERVICE_ADDR=shippingservice:50051 \
  -e CHECKOUT_SERVICE_ADDR=checkoutservice:5050 \
  -e AD_SERVICE_ADDR=adservice:9555 \
  -e SHOPPING_ASSISTANT_SERVICE_ADDR=localhost:50051 \
  $REG/frontend:$TAG
```

Open: [http://localhost:8081](http://localhost:8081)

---

# (Optional) 12) Load Generator

```bash
docker run -d --name loadgenerator --network boutique \
  --restart unless-stopped \
  -e FRONTEND_ADDR=frontend:8081 \
  -e USERS=10 \
  $REG/loadgenerator:$TAG
```

---

## How to verify each step

* Check logs for any service:

  ```bash
  docker logs <container-name> --tail 100
  ```
* Check it’s running:

  ```bash
  docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
  ```
* From your host:

  * Frontend: `curl -I http://localhost:8081`
  * Currency (internal): `docker exec -it frontend curl -s http://currencyservice:8083/`
    (Most other services are gRPC or internal; using `curl` from within a container on the same network is handy.)

---

## Common tweaks

* **Restart a flapping service** after deps are up:

  ```bash
  docker restart frontend
  ```
* **Clean stop**:

  ```bash
  docker rm -f loadgenerator frontend adservice checkoutservice shippingservice \
    paymentservice emailservice recommendationservice cartservice currencyservice \
    productcatalogservice redis-cart
  docker network rm boutique
  ```
* **Switch to your own images** (if you built/pushed earlier):
  Set `REG=docker.io/<your-id>` and `TAG=<your-tag>` before running the commands.
