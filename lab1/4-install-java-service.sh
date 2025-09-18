# Build adservice (Java)
cd ~/microservices-demo/src/adservice
chmod +x gradlew
./gradlew installDist
cp build/install/hipstershop/bin/AdService ../../bin/adservice
