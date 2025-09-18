# Build currencyservice, paymentservice
deactivate 2>/dev/null || true
sudo apt-get install -y python3-dev gyp make g++

cd ~/microservices-demo/src/currencyservice
npm ci || npm install
npx pkg server.js   --targets node18-linux-x64   --output ../../bin/currencyservice


cd ~/microservices-demo/src/paymentservice
npm ci || npm install
npx pkg server.js   --targets node18-linux-x64   --output ../../bin/paymentservice