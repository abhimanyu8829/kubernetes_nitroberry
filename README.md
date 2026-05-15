# Nitroberry — Production-Ready Kubernetes Microservices Architecture

<div align="center">

![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/postgresql-%23316192.svg?style=for-the-badge&logo=postgresql&logoColor=white)
![Traefik](https://img.shields.io/badge/traefik-%2324A1C1.svg?style=for-the-badge&logo=traefikproxy&logoColor=white)
![AWS ECR](https://img.shields.io/badge/AWS_ECR-%23FF9900.svg?style=for-the-badge&logo=amazon-aws&logoColor=white)

A **production-grade**, **bare-metal Kubernetes architecture** for microservices with **Traefik v3** ingress, **MetalLB** load balancing, **PostgreSQL 15** multi-schema database, **OPA Gatekeeper** policy enforcement, and **automated S3 backups**.

[Features](#-features) • [Architecture](#-architecture) • [ECR Registry](#-amazon-ecr-repositories) • [Quick Start](#-quick-start-local-development) • [Production Deployment](#-production-deployment) • [Update Guide](#-production-update-guide)

</div>

---

## 📋 Table of Contents

- [Features](#-features)
- [Architecture Overview](#-architecture-overview)
- [Repository Structure](#-repository-structure)
- [📦 Amazon ECR Repositories](#-amazon-ecr-repositories)
- [Prerequisites](#-prerequisites)
- [Quick Start (Local Development)](#-quick-start-local-development)
- [Production Deployment](#-production-deployment)
- [🛠 Production Update Guide](#-production-update-guide)
- [Security Features](#-security-features)
- [Troubleshooting](#-troubleshooting)

---

## ✨ Features

### Infrastructure
- ✅ **Bare-metal ready** with MetalLB L2/BGP load balancing.
- ✅ **7-Namespace isolation** — Dedicated environments for Auth, Cockpit, Messenger, Social, Task, Vault, and Workflow.
- ✅ **Production-grade deployments** with CPU/memory limits, liveness/readiness probes, and pod anti-affinity.
- ✅ **Horizontal Pod Autoscaling** (HPA) on all APIs (2–10 replicas).
- ✅ **Network policies** for zero-trust pod-to-pod communication.

### API Gateway & Routing
- ✅ **Traefik v3** ingress controller with declarative `IngressRoute` CRDs.
- ✅ **JWT authentication at the edge** — Middleware validates tokens before hitting backends.
- ✅ **Rate limiting** & **Security headers** enforced globally.
- ✅ **Let's Encrypt TLS** — Fully automated certificate management.

### Data Layer
- ✅ **PostgreSQL 15** StatefulSet with stable network identity.
- ✅ **Multi-schema isolation** — Each service owns its schema (e.g., `auth`, `task`, `social`).
- ✅ **Nightly S3 backups** — Automated `pg_dumpall` synced to AWS S3.

---

## 🏗 Architecture Overview

### System Diagram

```
                        Internet
                           │
                           │ (DNS: *.nitroberry.com)
                           ▼
                   ┌────────────────────┐
                   │  MetalLB (L2 ARP)  │
                   │  IP Pool Configuration │
                   └─────────┬──────────┘
                             │
                             ▼
         ┌──────────────────────────────────────────┐
         │       traefik-ingress namespace          │
         │  ┌────────────────────────────────────┐  │
         │  │     Traefik v3 (LoadBalancer)      │  │
         │  └────────────────────────────────────┘  │
         └──────────┬───────────────────────────────┘
                    │
         ┌──────────┴──────────────┐
         │    Host() routing       │
         └──────────┬──────────────┘
                    │
      ┌─────────────┼─────────────┬─────────────┬─────────────┬─────────────┬─────────────┐
      ▼             ▼             ▼             ▼             ▼             ▼             ▼
┌────────┐   ┌────────┐   ┌────────┐   ┌────────┐   ┌────────┐   ┌────────┐   ┌────────┐
│  auth  │   │ cockpit│   │messenger│  │ social │   │  task  │   │ vault  │   │workflow│
│  -api  │   │  -api  │   │  -api   │  │  -api  │   │  -api  │   │  -api  │   │  -api  │
├────────┤   ├────────┤   ├────────┤   ├────────┤   ├────────┤   ├────────┤   ├────────┤
│+Worker │   │+Worker │   │ (API)   │  │+Worker │   │+Worker │   │+Worker │   │+Worker │
└────┬───┘   └────┬───┘   └────┬───┘   └────┬───┘   └────┬───┘   └────┬───┘   └────┬───┘
     │            │            │            │            │            │            │
     └────────────┴────────────┴────────────┴────────────┴────────────┴────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │  database-ns     │
                    │  ┌────────────┐  │
                    │  │ PostgreSQL │  │
                    │  │ (Schemas)  │  │
                    │  └────────────┘  │
                    └──────────────────┘
                              │
                              ▼
                      ┌────────────────┐
                      │   AWS S3 Bucket│
                      └────────────────┘
```

### Namespace Architecture

| Namespace | Service | Purpose |
|-----------|---------|---------|
| `auth-namespace` | Auth | Authentication & Authorization |
| `cockpit-namespace` | Cockpit | Admin & Dashboard Services |
| `messenger-namespace` | Messenger | Messaging & Communication |
| `social-namespace` | Social | Social Networking Features |
| `task-namespace` | Task | Task Management & Scheduling |
| `vault-namespace` | Vault | Secure Storage & Sensitive Data |
| `workflow-namespace` | Workflow | Business Process Automation |

---

## 📁 Repository Structure

```
kubernetes_nitroberry/
│
├── 00-namespaces.yaml              # Global namespace definitions
├── 01-metallb.yaml                 # MetalLB IP Pool config
├── 02-postgres.yaml                # PostgreSQL StatefulSet
├── 03-traefik-rbac.yaml            # Ingress RBAC
├── 04-traefik-install.yaml         # Ingress Controller
├── 05-traefik-middlewares.yaml     # JWT, Rate-limit, Headers
├── 06-auth.yaml                    # Auth API + Worker
├── 07-cockpit.yaml                 # Cockpit API + Worker
├── 08-messenger.yaml               # Messenger API
├── 09-social.yaml                  # Social API + Worker
├── 10-task.yaml                    # Task API + Worker
├── 11-configmaps.yaml              # Environment variables
├── 12-secrets.yaml                 # Sensitive keys (Passwords, JWT)
├── 13-vault.yaml                   # Vault API + Worker
├── 14-postgres-s3-backup.yaml      # AWS S3 Backup CronJob
├── 14-workflow.yaml                # Workflow API + Worker
├── 15-opa-gatekeeper.yaml          # Security Constraints
```

---

## 📦 Amazon ECR Repositories

All container images are hosted on **Amazon ECR**. Each microservice (except Messenger) consists of an **API** container and a **Worker** container.

| Service | Container Type | ECR Repository Path | Use Case |
|---------|----------------|----------------------|----------|
| **Auth** | API | `nitroberry/auth-api` | Handling logins, JWT issuance, and RBAC |
| | Worker | `nitroberry/auth-worker` | Background token cleanup and auditing |
| **Cockpit** | API | `nitroberry/cockpit-api` | Main admin dashboard API |
| | Worker | `nitroberry/cockpit-worker` | System health monitoring and reporting |
| **Messenger** | API | `nitroberry/messenger-api` | Real-time chat and notification delivery |
| **Social** | API | `nitroberry/social-api` | Feed management, likes, and comments |
| | Worker | `nitroberry/social-worker` | Media processing and feed aggregation |
| **Task** | API | `nitroberry/task-api` | Task CRUD and scheduling API |
| | Worker | `nitroberry/task-worker` | Task reminders and periodic execution |
| **Vault** | API | `nitroberry/vault-api` | Secure credential and file storage |
| | Worker | `nitroberry/vault-worker` | Encryption key rotation and cleanup |
| **Workflow** | API | `nitroberry/workflow-api` | Business logic flow and state machine |
| | Worker | `nitroberry/workflow-worker` | Step execution and external integrations |

> **Registry URL**: `798701233691.dkr.ecr.ap-south-1.amazonaws.com`

---

## 🚀 Quick Start (Local Development)

Use this workflow to run the entire stack locally on **Minikube**.

1.  **Start Minikube**:
    ```bash
    minikube start --memory=4096 --cpus=2
    ```
2.  **Enable Ingress**:
    ```bash
    minikube addons enable ingress
    ```
3.  **Apply Infrastructure**:
    ```bash
    kubectl apply -f 00-namespaces.yaml
    kubectl apply -f 02-postgres.yaml
    kubectl apply -f 03-traefik-rbac.yaml
    kubectl apply -f 04-traefik-install.yaml
    kubectl apply -f 05-traefik-middlewares.yaml
    ```
4.  **Apply Configs**:
    ```bash
    kubectl apply -f 11-configmaps.yaml
    kubectl apply -f 12-secrets.yaml
    ```

---

## 🌍 Production Deployment

### Pre-Deployment Checklist
- [ ] Kubernetes cluster (v1.28+) running.
- [ ] Domain name pointed to your cluster load balancer IP.
- [ ] AWS S3 bucket created for backups.
- [ ] ECR repositories created and images pushed.

### Deployment Steps
1.  **Core Infra**: Apply namespaces, MetalLB, and Postgres (`00`, `01`, `02`).
2.  **Traefik**: Apply RBAC, Installation, and Middlewares (`03`, `04`, `05`).
3.  **Services**: Apply all service manifests (`06` through `14`).
4.  **Security**: Apply OPA policies (`15`).

---

---

## 🛠 Production Update Guide

Follow this checklist to ensure every value is correctly configured for your production environment.

### 📋 Mandatory Production Changes

| File | Section/Key | Action |
|------|-------------|--------|
| **`01-metallb.yaml`** | `spec.addresses` | Change `192.168.49.200-250` to your actual physical network IP range. |
| **`12-secrets.yaml`** | `postgres-password` | Set a strong, unique password for the main database. |
| | `db-password` | (Required for each service) Must match the `postgres-password`. |
| | `jwt-secret` | Generate a random 256-bit string (e.g., using `openssl rand -base64 32`). |
| | `database-url` | Update with the correct password: `postgres://postgres:PASSWORD@...` |
| | `AWS_ACCESS_KEY_ID` | Your AWS access key for S3 backups. |
| | `AWS_SECRET_ACCESS_KEY` | Your AWS secret key. |
| | `S3_BUCKET` | The name of your existing S3 bucket for DB dumps. |
| **`06` to `14` (APIs)** | `Host()` rule | Change `nitroberry.com` to your actual production domain. |
| | `image` tag | Change `:latest` to a specific version tag (e.g., `:v1.0.5`). |
| | `certResolver` | Ensure it matches the resolver defined in your Traefik setup (default: `myresolver`). |
| **`11-configmaps.yaml`**| `LOG_LEVEL` | Set to `info` or `warn` for production (avoid `debug`). |

### 1. Update Network Settings (MetalLB)
If your bare-metal server is on a different subnet, update `01-metallb.yaml`:
```yaml
spec:
  addresses:
    - 10.0.0.100-10.0.0.150  # Change to your available LAN IPs
```

### 2. Update Sensitive Data (Secrets)
**CRITICAL**: Do not deploy with default passwords. Open `12-secrets.yaml`:
1.  Generate a JWT Secret: `openssl rand -base64 32`
2.  Generate a DB Password: `openssl rand -base64 24`
3.  Replace all `REPLACE_WITH_...` strings in the file.
4.  **Note**: Ensure `database-url` in each secret is updated with the new password.

### 3. Update Domain / Hosts
Search and replace `nitroberry.com` with your real domain (e.g., `api.yourcompany.com`) in all files from `06-auth.yaml` to `14-workflow.yaml`.

Example in `06-auth.yaml`:
```yaml
- match: Host(`auth.yourdomain.com`)
```

### 4. Deploying New Image Versions
For production stability, never use `:latest`. Update the `image` field in your deployment files:
```yaml
# Before
image: 798701233691.dkr.ecr.ap-south-1.amazonaws.com/nitroberry/auth-api:latest

# After (Production)
image: 798701233691.dkr.ecr.ap-south-1.amazonaws.com/nitroberry/auth-api:v1.0.5
```
Then apply the change:
```bash
kubectl apply -f 06-auth.yaml
```

---

## 🔒 Security Features
- **Network Policies**: Services only communicate with the DB; no cross-service sniffing.
- **Non-Root Containers**: All apps run as non-root (UID 1000).
- **OPA Gatekeeper**: Blocks any insecure deployment attempts automatically.

---

## 🛠 Troubleshooting
- **Check Status**: `kubectl get pods -A`
- **View Logs**: `kubectl logs -l app=auth-api -n auth-namespace`
- **Describe Failure**: `kubectl describe pod <pod_name> -n <namespace>`