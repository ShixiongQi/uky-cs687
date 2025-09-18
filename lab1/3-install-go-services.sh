# Build frontend, productcatalogservice, shippingservice, checkoutservice (Go)
cd ~/microservices-demo
mkdir -p bin
for s in frontend productcatalogservice shippingservice checkoutservice; do
  (cd src/$s && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o ../../bin/$s)
done
