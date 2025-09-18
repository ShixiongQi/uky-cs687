# Lab 1 Setup and Service Installation

This lab provides a set of scripts to install dependencies and compile multiple microservices (Go, Java, .NET, Python, and Node.js) on your node. Follow the instructions below carefully.

## Prerequisites
- A Ubuntu 24 environment with internet access.
- Permissions to install packages (sudo privileges).

## Step-by-Step Instructions

### 1. Install Dependencies
Run the following script to install all required packages and tools:
```bash
./1-install-deps.sh
````

### 2. Refresh Your Environment

Reload your shell configuration to update the environment variables:

```bash
source ~/.bashrc
```

### 3. Verify Installation

Check that all dependencies were installed correctly:

```bash
./2-verification.sh
```

### 4. Install Services One by One

Run each service installation script **in order**, as some depend on earlier ones:

```bash
./3-install-go-services.sh
./4-install-java-service.sh
./5-install-dotnet-service.sh
./6-install-python-service.sh
./7-install-nodejs-service.sh
```

## Notes

* Execute these scripts **from this directory** (`uky-cs687/lab1`).
* Use `chmod +x <script>` if a script is not executable.
* If any step fails, fix the error before proceeding to the next script.
* After completing all scripts, your environment should have all microservices installed and ready to run.
