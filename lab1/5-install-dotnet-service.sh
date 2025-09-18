# Build cartservice (.NET)
cd ~/microservices-demo/src/cartservice
dotnet publish -c Release -r linux-x64 \
  -p:PublishSingleFile=true -p:SelfContained=true \
  -o ../../bin/cartservice
