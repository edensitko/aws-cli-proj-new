# 🚀 AWS EC2 Deployment with Docker

## 📌 Project Overview

This project automates the deployment of **AWS EC2 instances** with Nginx, using **Docker** and **AWS CLI**. It sets up an **EC2-based infrastructure** with two services:

- **Red Service** (Accessible via `/red`)
- **Blue Service** (Accessible via `/blue`)

The deployment process is containerized using **Docker**, ensuring a consistent environment across different systems.

---

## 🏗️ Features

- 🏭 **Automated EC2 Deployment** using AWS CLI
- 🔄 **Dockerized Deployment Script** for consistency
- 🌐 **Nginx-based Web Services**
- 🔒 **AWS Security Group Configuration**
- 📌 **EBS and EFS Integration** (Optional)
- ⚡ **Auto-fetching Public IPs for Access**

---

## 📦 Project Structure

```
.
├── Dockerfile                # Docker container setup
├── setup_red_blue_nginx.sh   # AWS deployment script
├── README.md                 # Project documentation
└── .dockerignore             # Ignore files during build
```

---

## 🔧 Prerequisites

Before running the project, ensure you have:

1. **Docker Installed** → [Install Docker](https://docs.docker.com/get-docker/)
2. **An Active AWS Account**

💡 **Note:** You do **not** need to install AWS CLI on your local machine since the Docker container includes it.

---

## 🚀 How to Run

### **Step 1: Build Docker Image**

Run the following command to build the Docker image:

```bash
docker build -t my-aws-runner .
```

### **Step 2: Run Deployment in Docker**

#### Option 1: Using Local AWS Credentials

```bash
docker run --rm -v ~/.aws:/root/.aws:ro my-aws-runner
```

#### Option 2: Passing AWS Credentials Manually

```bash
docker run --rm \
  -e AWS_ACCESS_KEY_ID=AKIA************ \
  -e AWS_SECRET_ACCESS_KEY=************ \
  -e AWS_DEFAULT_REGION=us-east-1 \
  my-aws-runner
```

### **Step 3: Verify Deployment**

Once the script runs successfully, it will output:

```bash
Red Service URL: http://<RED_IP>/red
Blue Service URL: http://<BLUE_IP>/blue
```

Use these URLs to verify the services are running.

---

## ⚙️ How It Works

1. **Dockerfile** sets up a container with **AWS CLI**.
2. **`setup_red_blue_nginx.sh`** executes within the container:
   - Creates an AWS Security Group
   - Launches EC2 instances
   - Configures Nginx to serve the Red & Blue services
   - Retrieves Public IPs & displays them
3. The container runs the script and then **terminates** (`--rm` flag ensures cleanup).

---

## 🛠️ Customization

You can modify the **EC2 instance type**, **Nginx config**, or **AWS region** inside `setup_red_blue_nginx.sh` before building the Docker image.

Example:

```bash
INSTANCE_TYPE="t2.micro"
REGION="us-east-1"
```

---

## 🤝 Contributing

Feel free to open an **Issue** or **Pull Request** to improve this project! 🚀

# aws-cli-proj
