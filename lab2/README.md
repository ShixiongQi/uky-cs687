# Lab 2 – Running the Microservices Demo

> **Prerequisite:** Complete **Lab 1** and ensure all microservices were successfully compiled.

---

## Phase 1 – Initial Attempts (Expect Failures)

### 1. Open Terminals  
You’ll need **10 separate terminals** (one for each service).  
- Use **tmux** or **byobu** to multiplex a single terminal.  
- Or open them manually (tedious but acceptable).

### 2. Run Microservices Individually

#### AdService (Fails at First)
```bash
cd ~/microservices-demo
PORT=9555 ./bin/adservice      # ❌ Does not work

cd ~/microservices-demo/src/adservice
PORT=9555 ./build/install/hipstershop/bin/AdService   # ✅ Works
````

#### CartService

```bash
cd ~/microservices-demo
./bin/cartservice/cartservice
```

#### CheckoutService

```bash
cd ~/microservices-demo
PORT=5050 PRODUCT_CATALOG_SERVICE_ADDR=3550 \
SHIPPING_SERVICE_ADDR=50051 PAYMENT_SERVICE_ADDR=50051 \
EMAIL_SERVICE_ADDR=5000 CURRENCY_SERVICE_ADDR=7000 \
CART_SERVICE_ADDR=7070 ./bin/checkoutservice
```

#### CurrencyService

```bash
cd ~/microservices-demo
DISABLE_PROFILER=1 PORT=7000 ./bin/currencyservice
```

#### EmailService (Fails at First)

```bash
cd ~/microservices-demo
DISABLE_PROFILER=1 PORT=8080 ./bin/emailservice    # ❌ Does not work

cp ./bin/emailservice ./src/emailservice/          # Copy binary
cd ~/microservices-demo/src/emailservice
DISABLE_PROFILER=1 PORT=8080 ./emailservice        # ✅ Works
```

#### Frontend (Fails Multiple Times)

```bash
cd ~/microservices-demo
PORT=8080 PRODUCT_CATALOG_SERVICE_ADDR=3550 \
CURRENCY_SERVICE_ADDR=7000 CART_SERVICE_ADDR=7070 \
RECOMMENDATION_SERVICE_ADDR=8080 SHIPPING_SERVICE_ADDR=50051 \
CHECKOUT_SERVICE_ADDR=5050 AD_SERVICE_ADDR=9555 \
SHOPPING_ASSISTANT_SERVICE_ADDR=80 ./bin/frontend  # ❌ Fails

cp ./bin/frontend ./src/frontend/

cd ~/microservices-demo/src/frontend
PORT=8080 PRODUCT_CATALOG_SERVICE_ADDR=3550 \
CURRENCY_SERVICE_ADDR=7000 CART_SERVICE_ADDR=7070 \
RECOMMENDATION_SERVICE_ADDR=8080 SHIPPING_SERVICE_ADDR=50051 \
CHECKOUT_SERVICE_ADDR=5050 AD_SERVICE_ADDR=9555 \
SHOPPING_ASSISTANT_SERVICE_ADDR=80 ./frontend        # ❌ Still fails

PORT=8081 PRODUCT_CATALOG_SERVICE_ADDR=3550 \
CURRENCY_SERVICE_ADDR=7000 CART_SERVICE_ADDR=7070 \
RECOMMENDATION_SERVICE_ADDR=8080 SHIPPING_SERVICE_ADDR=50051 \
CHECKOUT_SERVICE_ADDR=5050 AD_SERVICE_ADDR=9555 \
SHOPPING_ASSISTANT_SERVICE_ADDR=80 ./frontend        # ✅ Finally works
```

#### PaymentService

```bash
cd ~/microservices-demo
PORT=50052 DISABLE_PROFILER=1 ./bin/paymentservice    # ❌ Fails

cd ~/microservices-demo/src/paymentservice
PORT=50052 DISABLE_PROFILER=1 node index.js          # ✅ Works
```

#### ProductCatalogService

```bash
cd ~/microservices-demo
PORT=3550 DISABLE_PROFILER=1 ./bin/productcatalogservice   # ❌ Fails

cp ./bin/productcatalogservice ./src/productcatalogservice/
cd ~/microservices-demo/src/productcatalogservice
PORT=3550 DISABLE_PROFILER=1 ./productcatalogservice       # ✅ Works
```

#### RecommendationService

```bash
cd ~/microservices-demo
PRODUCT_CATALOG_SERVICE_ADDR=3550 PORT=8080 \
DISABLE_PROFILER=1 ./bin/recommendationservice
```

#### ShippingService

```bash
cd ~/microservices-demo
PORT=50052 DISABLE_PROFILER=1 ./bin/shippingservice
```

### 3. Browser Test

Find your node’s **public IP** (`ifconfig`, look for `128.x.x.x`) and open:

```
http://<IP>:<PORT>
```

using your frontend port.
👉 **Result:** The site does **not** load correctly.

---

## Phase 2 – Align All Ports

The failures are caused by **inconsistent port assignments**. Use this table:

| Service           | Port  |
| ----------------- | ----- |
| AdService         | 9555  |
| CartService       | 7070  |
| CheckoutService   | 5050  |
| CurrencyService   | 8083  |
| EmailService      | 8080  |
| Frontend          | 8081  |
| PaymentService    | 50052 |
| ProductCatalogSvc | 3550  |
| RecommendationSvc | 8082  |
| ShippingService   | 50051 |

Re-run services with these ports.

```bash
# Run Adservice
cd ~/microservices-demo/src/adservice
PORT=9555 ./build/install/hipstershop/bin/AdService
```

```bash
# Run CartService
cd ~/microservices-demo
PORT=7070 ./bin/cartservice/cartservice
```

```bash
# Run CheckoutService
cd ~/microservices-demo
PORT=5050 PRODUCT_CATALOG_SERVICE_ADDR=3550 SHIPPING_SERVICE_ADDR=50051 PAYMENT_SERVICE_ADDR=50052 EMAIL_SERVICE_ADDR=8080 CURRENCY_SERVICE_ADDR=8083 CART_SERVICE_ADDR=7070 ./bin/checkoutservice
```

```bash
# Run CurrencyService
cd ~/microservices-demo
DISABLE_PROFILER=1 PORT=8083 ./bin/currencyservice
```

```bash
# Run EmailService
cd ~/microservices-demo/src/emailservice/
DISABLE_PROFILER=1 PORT=8080 ./emailservice
```

```bash
# Run Frontend
cd ~/microservices-demo/src/frontend/
PORT=8081 PRODUCT_CATALOG_SERVICE_ADDR=3550 CURRENCY_SERVICE_ADDR=8083 CART_SERVICE_ADDR=7070 RECOMMENDATION_SERVICE_ADDR=8082 SHIPPING_SERVICE_ADDR=50051 CHECKOUT_SERVICE_ADDR=5050 AD_SERVICE_ADDR=9555 SHOPPING_ASSISTANT_SERVICE_ADDR=50051 ./frontend
```

```bash
# Run PaymentService via nodejs
cd ~/microservices-demo/src/paymentservice
PORT=50052 DISABLE_PROFILER=1 node index.js
```

```bash
# Run ProductCatService
cd ~/microservices-demo/src/productcatalogservice/
PORT=3550 DISABLE_PROFILER=1 ./productcatalogservice
```

```bash
# Run RecommendationService
cd ~/microservices-demo
PRODUCT_CATALOG_SERVICE_ADDR=3550 PORT=8082 DISABLE_PROFILER=1 ./bin/recommendationservice
```

```bash
# Run ShippingserviceService
cd ~/microservices-demo
PORT=50051 DISABLE_PROFILER=1 ./bin/shippingservice
```

After doing so, try the browser again—**it still may not fully work**.

---

## 📌 Phase 3 – Final Configuration and Successful Run

Even after port alignment, remaining issues are:

* **CartService** must enable HTTP/2 cleartext (h2c).
* **Frontend** must bypass any proxy settings for localhost.
* All environment variables must consistently use `localhost:<port>`.

### Correct Commands for Every Service

#### AdService

```bash
cd ~/microservices-demo/src/adservice
PORT=9555 ./build/install/hipstershop/bin/AdService
```

#### CartService (Enable h2c)

```bash
cd ~/microservices-demo
Kestrel__EndpointDefaults__Protocols=Http2 \
Kestrel__Endpoints__Grpc__Url=http://0.0.0.0:7070 \
./bin/cartservice/cartservice
```

#### CheckoutService

```bash
cd ~/microservices-demo
PORT=5050 PRODUCT_CATALOG_SERVICE_ADDR=localhost:3550 \
SHIPPING_SERVICE_ADDR=localhost:50051 PAYMENT_SERVICE_ADDR=localhost:50052 \
EMAIL_SERVICE_ADDR=localhost:8080 CURRENCY_SERVICE_ADDR=localhost:8083 \
CART_SERVICE_ADDR=localhost:7070 ./bin/checkoutservice
```

#### CurrencyService

```bash
cd ~/microservices-demo
DISABLE_PROFILER=1 PORT=8083 ./bin/currencyservice
```

#### EmailService

```bash
cd ~/microservices-demo/src/emailservice
DISABLE_PROFILER=1 PORT=8080 ./emailservice
```

#### Frontend (Proxy Bypass + gRPC Logging)

```bash
cd ~/microservices-demo/src/frontend
GRPC_GO_LOG_SEVERITY_LEVEL=info \
GRPC_GO_LOG_VERBOSITY_LEVEL=2 \
NO_PROXY=localhost,127.0.0.1 \
no_proxy=localhost,127.0.0.1 \
PORT=8081 \
PRODUCT_CATALOG_SERVICE_ADDR=localhost:3550 \
CURRENCY_SERVICE_ADDR=localhost:8083 \
CART_SERVICE_ADDR=localhost:7070 \
RECOMMENDATION_SERVICE_ADDR=localhost:8082 \
SHIPPING_SERVICE_ADDR=localhost:50051 \
CHECKOUT_SERVICE_ADDR=localhost:5050 \
AD_SERVICE_ADDR=9555 \
SHOPPING_ASSISTANT_SERVICE_ADDR=localhost:50051 \
./frontend
```

#### PaymentService

```bash
cd ~/microservices-demo/src/paymentservice
PORT=50052 DISABLE_PROFILER=1 node index.js
```

#### ProductCatalogService

```bash
cd ~/microservices-demo/src/productcatalogservice
PORT=3550 DISABLE_PROFILER=1 ./productcatalogservice
```

#### RecommendationService

```bash
cd ~/microservices-demo
PRODUCT_CATALOG_SERVICE_ADDR=localhost:3550 \
PORT=8082 DISABLE_PROFILER=1 ./bin/recommendationservice
```

#### ShippingService

```bash
cd ~/microservices-demo
PORT=50051 DISABLE_PROFILER=1 ./bin/shippingservice
```

### Final Browser Check

1. Get your node’s **public IP** (`ifconfig` → look for `128.x.x.x`).
2. Visit:

   ```
   http://<PUBLIC_IP>:8081
   ```
3. **Result:** The Online Boutique frontend now loads and functions correctly.

---

## Summary

* **Phase 1:** Run services directly to see initial failures and missing binaries.
* **Phase 2:** Align all port numbers using the provided table.
* **Phase 3:** Apply h2c settings for CartService, bypass proxies for Frontend, and rerun with corrected commands—the application now works fully.