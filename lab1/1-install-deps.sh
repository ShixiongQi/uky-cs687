# Install deps
sudo apt update
sudo apt install -y \
  build-essential pkg-config cmake ninja-build \
  git curl unzip wget \
  openjdk-21-jdk \
  nodejs npm \
  python3 python3-pip python3-venv \
  protobuf-compiler libprotobuf-dev \
  redis-server

# Use JDK 21 for this shell (adjust path if different)
echo 'export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64' >> ~/.bashrc
echo 'export PATH=$JAVA_HOME/bin:$PATH' >> ~/.bashrc

# Install dotnet 9.0
curl -L https://dot.net/v1/dotnet-install.sh -o dotnet-install.sh
chmod +x dotnet-install.sh
# install SDK 9.x into ~/.dotnet
./dotnet-install.sh --channel 9.0

# add to PATH for this shell (and add to ~/.bashrc to persist)
echo 'export PATH=$HOME/.dotnet:$HOME/.dotnet/tools:$PATH' >> ~/.bashrc
dotnet --info | head -n 20

# Install a recent Go (≥1.22):
wget https://go.dev/dl/go1.22.5.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.22.5.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
source ~/.bashrc

cd ~/
git clone https://github.com/GoogleCloudPlatform/microservices-demo.git 