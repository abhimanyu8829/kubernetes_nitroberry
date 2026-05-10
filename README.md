# Nitroberry — Production-Ready Kubernetes Microservices Architecture

<div align="center">

![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/postgresql-%23316192.svg?style=for-the-badge&logo=postgresql&logoColor=white)
![Traefik](https://img.shields.io/badge/traefik-%2324A1C1.svg?style=for-the-badge&logo=traefikproxy&logoColor=white)

A **production-grade**, **bare-metal Kubernetes architecture** for microservices with **Traefik v3** ingress, **MetalLB** load balancing, **PostgreSQL 15** multi-schema database, **OPA Gatekeeper** policy enforcement, and **automated S3 backups**.

[Features](#-features) • [Architecture](#-architecture) • [Quick Start](#-quick-start) • [Production Deployment](#-production-deployment) • [API Reference](#-api-reference)

</div>

---

## 📋 Table of Contents

- [Features](#-features)
- [Architecture Overview](#-architecture-overview)
- [Repository Structure](#-repository-structure)
- [Prerequisites](#-prerequisites)
- [Quick Start (Local Development)](#-quick-start-local-development)
- [Production Deployment](#-production-deployment)
- [Configuration Reference](#-configuration-reference)
- [Security Features](#-security-features)
- [Monitoring & Operations](#-monitoring--operations)
- [Troubleshooting](#-troubleshooting)
- [API Reference](#-api-reference)
- [Contributing](#-contributing)

---

## ✨ Features

### Infrastructure
- ✅ **Bare-metal ready** with MetalLB L2/BGP load balancing — no cloud provider needed
- ✅ **Multi-namespace isolation** (7 dedicated namespaces) — blast-radius containment per service
- ✅ **Production-grade deployments** with CPU/memory limits, liveness/readiness probes, and pod anti-affinity for HA
- ✅ **Horizontal Pod Autoscaling** (HPA) on all APIs (2–10 replicas, 70% CPU threshold)
- ✅ **Network policies** for zero-trust pod-to-pod communication — services cannot talk to each other directly
- ✅ **StatefulSet PostgreSQL** with stable DNS, ordered restarts, and persistent volume claims

### API Gateway & Routing
- ✅ **Traefik v3** ingress controller with IngressRoute CRDs — declarative routing in Git
- ✅ **JWT authentication at the edge** — tokens validated by Traefik before traffic reaches any service
- ✅ **Rate limiting** (100 req/s avg, 50 burst) — protects all services from abuse automatically
- ✅ **Security headers** (HSTS, XSS protection, X-Frame-Options, nosniff) on every response
- ✅ **Let's Encrypt TLS** via ACME (TLS-ALPN-01) — certificates auto-renewed, zero manual effort
- ✅ **Subdomain-per-service routing** — clean, isolated URLs per microservice

### Data Layer
- ✅ **PostgreSQL 15** StatefulSet with 10Gi persistent storage and stable network identity
- ✅ **Multi-schema isolation** — each microservice owns its schema; no cross-service table access
- ✅ **Nightly S3 backups** via CronJob (`pg_dumpall` → gzip → S3) with timestamped filenames
- ✅ **Network-isolated** — only API pods in their namespace can reach port 5432
- ✅ **Point-in-time restore** capability from any S3 snapshot

### Security & Compliance
- ✅ **OPA Gatekeeper** — 6 admission-control policies block non-compliant workloads at deploy time
- ✅ **Sealed Secrets** — cluster-encrypted secrets safe to commit to Git (GitOps-friendly)
- ✅ **Non-root containers** with read-only root filesystems and all Linux capabilities dropped
- ✅ **No privileged containers** — enforced by OPA policy, not just convention
- ✅ **12-factor compliance** — ConfigMaps for config, Secrets for credentials, no hardcoded values
- ✅ **`:latest` tag banned** in production namespaces by OPA policy

### Developer Experience
- ✅ **Minikube-compatible** — full stack runs locally on a laptop with 4 GB RAM
- ✅ **Mock API server** included (Node.js) — realistic health, login, and data endpoints
- ✅ **One-command local test** via `local-test.ps1` (Windows) — builds, deploys, and verifies all services
- ✅ **`configure.sh`** — single script replaces domain, IP pool, email, registry across all manifests
- ✅ **Comprehensive health endpoints** (`/health`, `/public/info`) on every service — ready for uptime monitors

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
                  │  192.168.49.200-250│
                  └─────────┬──────────┘
                            │
                            ▼
        ┌──────────────────────────────────────────┐
        │       traefik-ingress namespace          │
        │  ┌────────────────────────────────────┐  │
        │  │     Traefik v3 (LoadBalancer)      │  │
        │  │  Port 80/443 + 8080 (dashboard)    │  │
        │  │                                    │  │
        │  │  Middlewares:                      │  │
        │  │    • JWT validation (plugin)       │  │
        │  │    • Rate limiting (100/s)         │  │
        │  │    • Security headers (HSTS)       │  │
        │  │    • Let's Encrypt (TLS-ALPN-01)   │  │
        │  └────────────────────────────────────┘  │
        └──────────┬───────────────────────────────┘
                   │
        ┌──────────┴──────────────┐
        │    Host() routing       │
        └──────────┬──────────────┘
                   │
     ┌─────────────┼─────────────┬─────────────┬─────────────┐
     ▼             ▼             ▼             ▼             ▼
┌────────┐   ┌────────┐   ┌────────┐   ┌────────┐   ┌────────┐
│  auth  │   │ users  │   │ orders │   │products│   │ notify │
│  -api  │   │  -api  │   │  -api  │   │  -api  │   │  -api  │
├────────┤   ├────────┤   ├────────┤   ├────────┤   ├────────┤
│2 pods  │   │2 pods  │   │2 pods  │   │2 pods  │   │2 pods  │
│HPA 2-10│   │HPA 2-10│   │HPA 2-10│   │HPA 2-10│   │HPA 2-10│
│:8080   │   │:8080   │   │:8080   │   │:8080   │   │:8080   │
└────┬───┘   └────┬───┘   └────┬───┘   └────┬───┘   └────┬───┘
     │            │            │            │            │
     └────────────┴────────────┴────────────┴────────────┘
                             │
                             ▼
                   ┌──────────────────┐
                   │  database-ns     │
                   │  ┌────────────┐  │
                   │  │ PostgreSQL │  │
                   │  │     15     │  │
                   │  │ StatefulSet│  │
                   │  │  (10Gi PVC)│  │
                   │  │            │  │
                   │  │ Schemas:   │  │
                   │  │  • auth    │  │
                   │  │  • users   │  │
                   │  │  • orders  │  │
                   │  │  • products│  │
                   │  │  • notify  │  │
                   │  └────────────┘  │
                   └──────────────────┘
                             │
                             │ (nightly backup)
                             ▼
                     ┌────────────────┐
                     │   AWS S3 Bucket│
                     │ versioned+gzip │
                     └────────────────┘
```

### Namespace Architecture

| Namespace | Purpose | Resources |
|-----------|---------|-----------|
| `traefik-ingress` | API Gateway & Ingress | Traefik Deployment, LoadBalancer Service, Middlewares |
| `auth-namespace` | Authentication Service | Deployment (2-10 pods), Service, HPA, IngressRoute, NetworkPolicy |
| `users-namespace` | User Management Service | Deployment (2-10 pods), Service, HPA, IngressRoute, NetworkPolicy |
| `orders-namespace` | Order Processing Service | Deployment (2-10 pods), Service, HPA, IngressRoute, NetworkPolicy |
| `products-namespace` | Product Catalog Service | Deployment (2-10 pods), Service, HPA, IngressRoute, NetworkPolicy |
| `notify-namespace` | Notification Service | Deployment (2-10 pods), Service, HPA, IngressRoute, NetworkPolicy |
| `database-namespace` | Shared Database | PostgreSQL StatefulSet (1 replica), Service, NetworkPolicy, Backup CronJob |

---

## 📁 Repository Structure

```
kubernetes_nitroberry/
│
├── 00-namespaces.yaml              # All 7 namespaces
├── 01-metallb.yaml                 # MetalLB IP pool (bare-metal only)
├── 02-postgres.yaml                # PostgreSQL 15 StatefulSet + init schemas
├── 03-traefik-rbac.yaml            # Traefik ServiceAccount + RBAC
├── 04-traefik-install.yaml         # Traefik v3 Deployment + LoadBalancer
├── 05-traefik-middlewares.yaml     # JWT, rate-limit, security headers
├── 06-auth-api.yaml                # Auth API: Deployment, Service, HPA, IngressRoute
├── 07-users-api.yaml               # Users API: Deployment, Service, HPA, IngressRoute
├── 08-orders-api.yaml              # Orders API: Deployment, Service, HPA, IngressRoute
├── 09-products-api.yaml            # Products API: Deployment, Service, HPA, IngressRoute
├── 10-notify-api.yaml              # Notify API: Deployment, Service, HPA, IngressRoute
├── 11-configmaps.yaml              # Non-sensitive config for all 5 APIs
├── 12-secrets.yaml                 # Secrets + Sealed Secrets workflow
├── 13-api-deployments-prod.yaml    # Production deployments with:
│                                   #   • Resource requests/limits
│                                   #   • Pod anti-affinity
│                                   #   • Readiness/liveness probes
│                                   #   • securityContext (non-root, read-only FS)
├── 14-postgres-s3-backup.yaml      # Nightly backup CronJob (pg_dumpall → S3)
├── 15-opa-gatekeeper.yaml          # OPA Gatekeeper policies (6 constraints)
│
├── configure.sh                    # Automated configuration script
├── get_helm.sh                     # Official Helm installer
├── local-test.ps1                  # PowerShell test script (Windows/Minikube)
│
├── server.js                       # Mock API server (Node.js)
├── Dockerfile                      # Mock API Docker image
│
└── README.md                       # This file
```

---

## 🔧 Prerequisites

### For Local Development (Minikube)

- **Docker** (running)
- **Minikube** (v1.32+)
- **kubectl** (v1.28+)
- **Git** (for cloning)

### For Production (Bare Metal)

- **Kubernetes cluster** (v1.28+) — 3+ nodes recommended
- **kubectl** configured for cluster access
- **Helm 3** (optional, for MetalLB installation)
- **Domain name** with DNS configured
- **AWS S3 bucket** (for database backups)
- **kubeseal** CLI (for Sealed Secrets)

### Optional Tools

- **curl** or **httpie** (for API testing)
- **jq** (for JSON parsing)
- **stern** (for multi-pod log tailing)

---

## 🚀 Quick Start (Local Development)

Use this workflow to run the entire stack locally on **Minikube** without a bare-metal cluster.

### Step 1: Start Minikube

```bash
minikube start --memory=4096 --cpus=2 --driver=docker
minikube addons enable ingress
```

> **Note**: If you get "cannot change memory size for an existing cluster", delete first:
> ```bash
> minikube delete && minikube start --memory=4096 --cpus=2 --driver=docker
> ```

### Step 2: Point Docker at Minikube's Daemon

This makes locally-built images available to the cluster without pushing to a registry.

**Linux/macOS:**
```bash
eval $(minikube docker-env)
```

**Windows PowerShell:**
```powershell
& minikube docker-env --shell powershell | Invoke-Expression
```

> ⚠️ **Important**: Run this in **every new terminal session** where you build images.

### Step 3: Build the Mock API Image

Since the production images (`yourregistry.com/auth-api:v1.0.0` etc.) don't exist yet, we use a single mock Node.js server:

```bash
# Files are already in the repo (server.js + Dockerfile)
docker build -t nitroberry-mock-api:local .

# Verify the image is visible to Minikube
minikube ssh -- docker images | grep nitroberry
```

### Step 4: Deploy Core Infrastructure

```bash
# Namespaces
kubectl apply -f 00-namespaces.yaml

# PostgreSQL (skip MetalLB — not needed in Minikube)
kubectl apply -f 02-postgres.yaml
kubectl rollout status statefulset/postgres -n database-namespace

# Traefik
kubectl apply -f 03-traefik-rbac.yaml
kubectl apply -f 04-traefik-install.yaml
kubectl apply -f 05-traefik-middlewares.yaml
kubectl rollout status deployment/traefik -n traefik-ingress
```

### Step 5: Deploy API Services

Apply the original manifests (creates Services, HPAs, IngressRoutes, NetworkPolicies):

```bash
kubectl apply -f 06-auth-api.yaml
kubectl apply -f 07-users-api.yaml
kubectl apply -f 08-orders-api.yaml
kubectl apply -f 09-products-api.yaml
kubectl apply -f 10-notify-api.yaml
```

Patch all 5 deployments to use the local mock image:

```bash
for SVC in auth users orders products notify; do
  kubectl set image deployment/${SVC}-api api=nitroberry-mock-api:local -n ${SVC}-namespace
  kubectl set env deployment/${SVC}-api SERVICE_NAME=${SVC} DB_SCHEMA=${SVC} -n ${SVC}-namespace
  kubectl patch deployment ${SVC}-api -n ${SVC}-namespace \
    -p '{"spec":{"template":{"spec":{"containers":[{"name":"api","imagePullPolicy":"Never"}]}}}}'
done
```

Wait for all pods to be running:

```bash
kubectl get pods -A | grep -E "auth|users|orders|products|notify"
```

### Step 6: Port-Forward and Test

Start port-forwards in the background:

```bash
kubectl port-forward svc/auth-api-service     9001:8080 -n auth-namespace     &
kubectl port-forward svc/users-api-service    9002:8080 -n users-namespace    &
kubectl port-forward svc/orders-api-service   9003:8080 -n orders-namespace   &
kubectl port-forward svc/products-api-service 9004:8080 -n products-namespace &
kubectl port-forward svc/notify-api-service   9005:8080 -n notify-namespace   &
```

Test all health endpoints:

```bash
for PORT in 9001 9002 9003 9004 9005; do
  echo "=== localhost:$PORT ==="
  curl -s localhost:$PORT/health | jq
  echo ""
done
```

Test data endpoints:

```bash
curl -s localhost:9001/login | jq        # Auth: JWT token
curl -s localhost:9002/profiles | jq    # Users: user profiles
curl -s localhost:9003/orders | jq      # Orders: order list
curl -s localhost:9004/items | jq       # Products: product catalog
curl -s localhost:9005/notifications | jq  # Notify: notifications
```

### Step 7: Access Traefik Dashboard

```bash
kubectl port-forward -n traefik-ingress svc/traefik-service 8080:8080
# Open http://localhost:8080/dashboard/
```

### Automated Testing (Windows)

Use the included PowerShell script for one-command testing:

```powershell
.\local-test.ps1
```

This script:
- ✅ Validates Minikube is running
- ✅ Builds the mock image (if missing)
- ✅ Deploys all infrastructure
- ✅ Applies ConfigMaps and Secrets
- ✅ Patches deployments for local use
- ✅ Port-forwards all services
- ✅ Runs health checks on all APIs
- ✅ Verifies database schemas

---

## 🌍 Production Deployment

### Pre-Deployment Checklist

- [ ] Kubernetes cluster running (3+ nodes, each with ≥ 4 CPU / 8 GB RAM)
- [ ] `kubectl` configured with `cluster-admin` access
- [ ] Domain name registered; DNS provider accessible
- [ ] AWS S3 bucket created with versioning **enabled**
- [ ] Container images built and pushed to your private registry
- [ ] Sealed Secrets controller installed on the cluster
- [ ] `metrics-server` installed (required for HPA)
- [ ] Firewall: ports **80**, **443**, and **6443** open to the internet
- [ ] Image pull secret created (if using a private registry)

### Step 1: Install Prerequisites

#### MetalLB (for bare-metal clusters)

```bash
# Using Helm (recommended)
helm repo add metallb https://metallb.github.io/metallb
helm install metallb metallb/metallb -n metallb-system --create-namespace

# Or using kubectl
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
```

#### Sealed Secrets Controller

```bash
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/latest/download/controller.yaml

# Install kubeseal CLI (macOS)
brew install kubeseal

# Or download binary (Linux/Windows)
wget https://github.com/bitnami-labs/sealed-secrets/releases/latest/download/kubeseal-linux-amd64
chmod +x kubeseal-linux-amd64
sudo mv kubeseal-linux-amd64 /usr/local/bin/kubeseal
```

#### Metrics Server (required for HPA)

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Verify it is running
kubectl rollout status deployment/metrics-server -n kube-system
kubectl top nodes   # should show CPU/memory
```

#### OPA Gatekeeper

```bash
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/release-3.14/deploy/gatekeeper.yaml
kubectl rollout status deployment/gatekeeper-controller-manager -n gatekeeper-system
```

#### Image Pull Secret (private registry)

```bash
# Create once per namespace that pulls private images
for NS in auth-namespace users-namespace orders-namespace products-namespace notify-namespace; do
  kubectl create secret docker-registry registry-credentials \
    --namespace=$NS \
    --docker-server=yourregistry.azurecr.io \
    --docker-username=$REGISTRY_USER \
    --docker-password=$REGISTRY_PASSWORD
done
```

Then reference it in `13-api-deployments-prod.yaml`:

```yaml
spec:
  imagePullSecrets:
    - name: registry-credentials
```

### Step 2: Configure for Your Environment

Edit `configure.sh` with your values:

```bash
#!/bin/bash
# Production configuration

YOUR_DOMAIN="nitroberry.com"                    # Your root domain
YOUR_IP_RANGE="10.0.0.100-10.0.0.150"          # MetalLB IP pool
YOUR_EMAIL="admin@nitroberry.com"               # Let's Encrypt email
YOUR_DB_PASSWORD="$(openssl rand -base64 32)"   # Strong DB password
YOUR_REGISTRY="yourregistry.azurecr.io"         # Container registry
IMAGE_TAG="v1.0.0"                              # Image version tag
```

Run the configuration script:

```bash
chmod +x configure.sh
./configure.sh
```

This automatically updates:
- ✅ MetalLB IP range in `01-metallb.yaml`
- ✅ Domain names in all IngressRoute manifests (`06-10`)
- ✅ Let's Encrypt email in `04-traefik-install.yaml`
- ✅ Database passwords in all manifests
- ✅ Container image references to your registry

### Step 3: Build and Push Container Images

Build your actual API images and push to your registry:

```bash
# Example: auth-api
cd auth-api/
docker build -t yourregistry.azurecr.io/auth-api:v1.0.0 .
docker push yourregistry.azurecr.io/auth-api:v1.0.0

# Repeat for: users-api, orders-api, products-api, notify-api
```

Update image references in `13-api-deployments-prod.yaml`:

```yaml
containers:
  - name: api
    image: yourregistry.azurecr.io/auth-api:v1.0.0  # Update this line
```

### Step 4: Create and Seal Secrets

Generate strong secrets:

```bash
# Database password
DB_PASSWORD=$(openssl rand -base64 32)

# JWT secret (256-bit)
JWT_SECRET=$(openssl rand -base64 32)

# AWS credentials
AWS_ACCESS_KEY_ID="your-aws-key"
AWS_SECRET_ACCESS_KEY="your-aws-secret"
```

Create SealedSecret for Postgres:

```bash
kubectl create secret generic postgres-credentials \
  --namespace=database-namespace \
  --from-literal=postgres-password="$DB_PASSWORD" \
  --from-literal=postgres-user='postgres' \
  --dry-run=client -o yaml | \
  kubeseal --format yaml > sealed-postgres-credentials.yaml

kubectl apply -f sealed-postgres-credentials.yaml
```

Create SealedSecret for Auth API:

```bash
kubectl create secret generic auth-api-secrets \
  --namespace=auth-namespace \
  --from-literal=db-password="$DB_PASSWORD" \
  --from-literal=jwt-secret="$JWT_SECRET" \
  --from-literal=database-url="postgres://postgres:$DB_PASSWORD@postgres-service.database-namespace.svc.cluster.local:5432/postgres?options=-csearch_path%3Dauth" \
  --dry-run=client -o yaml | \
  kubeseal --format yaml > sealed-auth-api-secrets.yaml

kubectl apply -f sealed-auth-api-secrets.yaml
```

Repeat for: `users-api-secrets`, `orders-api-secrets`, `products-api-secrets`, `notify-api-secrets`

Create SealedSecret for S3 backups:

```bash
kubectl create secret generic aws-s3-backup-credentials \
  --namespace=database-namespace \
  --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
  --from-literal=AWS_DEFAULT_REGION='us-east-1' \
  --from-literal=S3_BUCKET='nitroberry-db-backups' \
  --dry-run=client -o yaml | \
  kubeseal --format yaml > sealed-s3-credentials.yaml

kubectl apply -f sealed-s3-credentials.yaml
```

### Step 5: Deploy Infrastructure

```bash
# Namespaces
kubectl apply -f 00-namespaces.yaml

# MetalLB (with updated IP pool)
kubectl apply -f 01-metallb.yaml

# PostgreSQL
kubectl apply -f 02-postgres.yaml
kubectl rollout status statefulset/postgres -n database-namespace

# Wait for Postgres to be ready
kubectl wait --for=condition=ready pod -l app=postgres -n database-namespace --timeout=300s
```

### Step 6: Deploy Traefik

```bash
kubectl apply -f 03-traefik-rbac.yaml
kubectl apply -f 04-traefik-install.yaml
kubectl apply -f 05-traefik-middlewares.yaml

# Wait for Traefik to be ready
kubectl rollout status deployment/traefik -n traefik-ingress

# Get LoadBalancer IP
kubectl get svc -n traefik-ingress traefik-service
```

**Configure DNS**: Point your domain's A records to the LoadBalancer IP:

```
auth.nitroberry.com      → 10.0.0.100
users.nitroberry.com     → 10.0.0.100
orders.nitroberry.com    → 10.0.0.100
products.nitroberry.com  → 10.0.0.100
notify.nitroberry.com    → 10.0.0.100
```

### Step 7: Deploy ConfigMaps

```bash
kubectl apply -f 11-configmaps.yaml

# Verify ConfigMaps
kubectl get configmap -A | grep api-config
```

### Step 8: Deploy Production API Services

```bash
# Apply production deployments (with resource limits, anti-affinity, probes)
kubectl apply -f 13-api-deployments-prod.yaml

# Apply original service/HPA/IngressRoute manifests
kubectl apply -f 06-auth-api.yaml
kubectl apply -f 07-users-api.yaml
kubectl apply -f 08-orders-api.yaml
kubectl apply -f 09-products-api.yaml
kubectl apply -f 10-notify-api.yaml

# Wait for all deployments
kubectl rollout status deployment/auth-api -n auth-namespace
kubectl rollout status deployment/users-api -n users-namespace
kubectl rollout status deployment/orders-api -n orders-namespace
kubectl rollout status deployment/products-api -n products-namespace
kubectl rollout status deployment/notify-api -n notify-namespace
```

### Step 9: Deploy Database Backups

```bash
# Apply backup CronJob
kubectl apply -f 14-postgres-s3-backup.yaml

# Manually trigger first backup (test)
kubectl create job --from=cronjob/postgres-s3-backup manual-backup-001 -n database-namespace

# Check backup logs
kubectl logs -n database-namespace -l job-name=manual-backup-001
```

### Step 10: Deploy OPA Gatekeeper Policies

```bash
kubectl apply -f 15-opa-gatekeeper.yaml

# Verify policies
kubectl get constrainttemplates
kubectl get constraints
```

### Step 11: Verification

```bash
# Check all pods are running
kubectl get pods -A

# Check HPAs are seeing metrics (TARGETS column should not show <unknown>)
kubectl get hpa -A

# Check IngressRoutes
kubectl get ingressroute -A

# Check NetworkPolicies
kubectl get networkpolicy -A

# Test API health endpoints
curl -k https://auth.nitroberry.com/health
curl -k https://users.nitroberry.com/health
curl -k https://orders.nitroberry.com/health
curl -k https://products.nitroberry.com/health
curl -k https://notify.nitroberry.com/health

# Verify TLS certificate is valid (no -k flag)
curl -v https://auth.nitroberry.com/health 2>&1 | grep -E "SSL|issuer|expire"

# Confirm OPA constraints are active
kubectl get constraints
```

---

## 🔄 Rolling Updates & Rollbacks

### Deploy a New Image Version

```bash
# Update the image tag in a running deployment
kubectl set image deployment/auth-api \
  api=yourregistry.azurecr.io/auth-api:v1.1.0 \
  -n auth-namespace

# Watch the rolling update progress
kubectl rollout status deployment/auth-api -n auth-namespace
```

### Rollback a Bad Deploy

```bash
# View rollout history
kubectl rollout history deployment/auth-api -n auth-namespace

# Roll back to the previous version immediately
kubectl rollout undo deployment/auth-api -n auth-namespace

# Roll back to a specific revision
kubectl rollout undo deployment/auth-api -n auth-namespace --to-revision=2
```

### Apply Manifest Changes Without Downtime

```bash
# Server-side apply (preferred — tracks field ownership)
kubectl apply --server-side -f 13-api-deployments-prod.yaml

# Force a restart of all pods without changing the image
kubectl rollout restart deployment/auth-api -n auth-namespace
```

---

## 🚀 CI/CD Pipeline Integration

### GitHub Actions Example

Create `.github/workflows/deploy.yml` in your repository:

```yaml
name: Build & Deploy

on:
  push:
    branches: [main]

env:
  REGISTRY: yourregistry.azurecr.io
  IMAGE_TAG: ${{ github.sha }}

jobs:
  build-push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Log in to registry
        run: echo "${{ secrets.REGISTRY_PASSWORD }}" | docker login $REGISTRY -u ${{ secrets.REGISTRY_USER }} --password-stdin

      - name: Build and push images
        run: |
          for SVC in auth users orders products notify; do
            docker build -t $REGISTRY/${SVC}-api:$IMAGE_TAG ./${SVC}-api/
            docker push $REGISTRY/${SVC}-api:$IMAGE_TAG
          done

  deploy:
    needs: build-push
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up kubectl
        uses: azure/setup-kubectl@v3

      - name: Configure kubeconfig
        run: echo "${{ secrets.KUBECONFIG_B64 }}" | base64 -d > kubeconfig.yaml

      - name: Rolling deploy all services
        env:
          KUBECONFIG: kubeconfig.yaml
        run: |
          for SVC in auth users orders products notify; do
            kubectl set image deployment/${SVC}-api \
              api=$REGISTRY/${SVC}-api:$IMAGE_TAG \
              -n ${SVC}-namespace
            kubectl rollout status deployment/${SVC}-api -n ${SVC}-namespace
          done
```

### Required GitHub Secrets

| Secret | Description |
|--------|-------------|
| `REGISTRY_USER` | Container registry username |
| `REGISTRY_PASSWORD` | Container registry password |
| `KUBECONFIG_B64` | Base64-encoded kubeconfig with cluster access |

Encode your kubeconfig:
```bash
base64 -w 0 ~/.kube/config
```

---

## 💾 Disaster Recovery

### Full Cluster Restore Procedure

If you need to rebuild from scratch after a complete cluster failure:

```bash
# 1. Re-provision the Kubernetes cluster (3+ nodes)
# 2. Install prerequisites
kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/latest/download/controller.yaml
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/release-3.14/deploy/gatekeeper.yaml
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# 3. Apply all manifests in order
kubectl apply -f 00-namespaces.yaml
kubectl apply -f 01-metallb.yaml
kubectl apply -f 02-postgres.yaml
kubectl wait --for=condition=ready pod -l app=postgres -n database-namespace --timeout=300s
kubectl apply -f 03-traefik-rbac.yaml
kubectl apply -f 04-traefik-install.yaml
kubectl apply -f 05-traefik-middlewares.yaml
kubectl apply -f 11-configmaps.yaml

# 4. Re-apply all sealed secrets from Git
kubectl apply -f sealed-postgres-credentials.yaml
kubectl apply -f sealed-auth-api-secrets.yaml
kubectl apply -f sealed-s3-credentials.yaml
# ... repeat for each service

# 5. Deploy services
kubectl apply -f 13-api-deployments-prod.yaml
kubectl apply -f 06-auth-api.yaml 07-users-api.yaml 08-orders-api.yaml 09-products-api.yaml 10-notify-api.yaml

# 6. Restore latest database backup from S3
LATEST=$(aws s3 ls s3://nitroberry-db-backups/backups/ | sort | tail -1 | awk '{print $4}')
aws s3 cp s3://nitroberry-db-backups/backups/$LATEST .
gunzip -c $LATEST | kubectl exec -i postgres-0 -n database-namespace -- psql -U postgres

# 7. Deploy backup job and OPA policies
kubectl apply -f 14-postgres-s3-backup.yaml
kubectl apply -f 15-opa-gatekeeper.yaml
```

### Backup Verification (run monthly)

```bash
# List all available backups
aws s3 ls s3://nitroberry-db-backups/backups/ --human-readable --summarize

# Restore to a temporary pod to verify integrity
kubectl run restore-test --image=postgres:15 --rm -it -- bash
# Inside the pod:
# aws s3 cp s3://nitroberry-db-backups/backups/<file>.sql.gz - | gunzip | psql -h <host> -U postgres
```

---

## 📈 Monitoring Stack (Recommended Add-ons)

The base architecture is observable via `kubectl`. For production, add:

### Prometheus + Grafana

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kube-prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --set grafana.adminPassword=changeme

# Access Grafana dashboard
kubectl port-forward -n monitoring svc/kube-prometheus-grafana 3000:80
# Open http://localhost:3000 (admin / changeme)
```

### Loki (Log Aggregation)

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm install loki grafana/loki-stack \
  --namespace monitoring \
  --set grafana.enabled=false
```

### Key Dashboards to Import

| Dashboard | Grafana ID | What it shows |
|-----------|-----------|---------------|
| Kubernetes cluster overview | `7249` | Node CPU, memory, pod counts |
| Traefik metrics | `17347` | Request rate, error rate, latency |
| PostgreSQL exporter | `9628` | Query performance, connections |
| HPA overview | `10257` | Replica counts, scaling events |

---

## ⚙️ Configuration Reference

### Environment Variables (ConfigMaps)

Each API service uses the following non-sensitive configuration:

| Variable | Example Value | Description |
|----------|---------------|-------------|
| `PORT` | `8080` | HTTP listen port |
| `DB_SCHEMA` | `auth` | PostgreSQL schema name |
| `DB_HOST` | `postgres-service.database-namespace.svc.cluster.local` | Database hostname |
| `DB_PORT` | `5432` | Database port |
| `DB_NAME` | `postgres` | Database name |
| `DB_USER` | `postgres` | Database username |
| `JWT_ALGORITHM` | `HS256` | JWT signing algorithm (auth-api only) |
| `LOG_LEVEL` | `info` | Logging level |
| `ENV` | `production` | Environment name |

### Secrets

Each API service uses the following sensitive configuration:

| Secret Key | Description |
|------------|-------------|
| `database-url` | Full PostgreSQL connection string with password |
| `db-password` | Database password |
| `jwt-secret` | JWT signing secret (auth-api only) |

### Resource Limits (Production)

All API pods have identical resource constraints:

```yaml
resources:
  requests:
    cpu: "100m"      # 0.1 CPU core minimum
    memory: "128Mi"  # 128 MiB minimum
  limits:
    cpu: "500m"      # 0.5 CPU core maximum
    memory: "256Mi"  # 256 MiB maximum
```

### HPA Configuration

```yaml
spec:
  minReplicas: 2       # Always at least 2 pods (HA)
  maxReplicas: 10      # Scale up to 10 under load
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70  # Scale at 70% CPU
```

### Network Policies

Each API has a NetworkPolicy that:

**Ingress**: Only allows traffic from `traefik-ingress` namespace on port 8080
```yaml
ingress:
  - from:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: traefik-ingress
    ports:
      - protocol: TCP
        port: 8080
```

**Egress**: Only allows traffic to `database-namespace` on port 5432
```yaml
egress:
  - to:
      - namespaceSelector:
          matchLabels:
            kubernetes.io/metadata.name: database-namespace
    ports:
      - protocol: TCP
        port: 5432
```

---

## 🔒 Security Features

### 1. JWT Authentication (Traefik Middleware)

All non-public API paths require a valid JWT token:

```yaml
# Public paths (no JWT)
PathPrefix(`/login`) || PathPrefix(`/health`) || PathPrefix(`/public`)

# Protected paths (JWT required)
Authorization: Bearer <token>
```

The JWT middleware validates:
- ✅ Token signature (HS256 algorithm)
- ✅ Token expiration
- ✅ Header format: `Authorization: Bearer <token>`

### 2. Rate Limiting

Global rate limiting via Traefik middleware:

```yaml
rateLimit:
  average: 100  # 100 requests/second average
  burst: 50     # Allow bursts up to 50 above average
```

### 3. Security Headers

All responses include:

```http
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
X-Content-Type-Options: nosniff
X-Frame-Options: SAMEORIGIN
X-XSS-Protection: 1; mode=block
```

### 4. OPA Gatekeeper Policies

Six active constraint templates enforce:

| Policy | Effect |
|--------|--------|
| **RequireResourceLimits** | Every container must have CPU and memory requests/limits |
| **RequireLabels** | All pods must have `app` and `managed-by` labels |
| **BlockPrivilegedContainers** | No `privileged: true` containers allowed |
| **BlockRootContainers** | All pods must set `runAsNonRoot: true` |
| **RequireReadOnlyRootFS** | All containers must use `readOnlyRootFilesystem: true` |
| **BlockLatestTag** | No `:latest` image tags in production namespaces |

### 5. Sealed Secrets

Sensitive data is encrypted with the cluster's public key and safe to commit to Git:

```bash
# Create a SealedSecret
kubectl create secret generic my-secret \
  --from-literal=password='supersecret' \
  --dry-run=client -o yaml | \
  kubeseal --format yaml > my-sealed-secret.yaml

# Commit the SealedSecret to Git (safe!)
git add my-sealed-secret.yaml

# The controller decrypts it into a regular Secret
kubectl apply -f my-sealed-secret.yaml
```

### 6. Pod Security

All production pods run with:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 1000
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: ["ALL"]
```

---

## 📊 Monitoring & Operations

### Health Checks

All APIs expose the following endpoints:

| Path | Auth Required | Response |
|------|---------------|----------|
| `/health` | ❌ No | `{"status":"healthy","uptime":"123.4s"}` |
| `/public/info` | ❌ No | `{"version":"1.0.0"}` |
| `/login` | ❌ No | `{"token":"eyJ...","expires_in":3600}` (auth-api only) |
| All other paths | ✅ Yes | Service-specific data |

### Readiness & Liveness Probes

```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 10
  failureThreshold: 3

livenessProbe:
  httpGet:
    path: /health
    port: 8080
  initialDelaySeconds: 15
  periodSeconds: 20
  failureThreshold: 3
```

### Database Backups

Automated nightly backups via CronJob:

```yaml
schedule: "0 2 * * *"  # 02:00 UTC daily
```

Backup process:
1. `pg_dumpall` dumps all databases
2. `gzip` compresses the dump
3. AWS CLI streams to S3: `s3://bucket/backups/nitroberry_YYYY-MM-DD_HH-MM-SS.sql.gz`

Manual backup:

```bash
kubectl create job --from=cronjob/postgres-s3-backup manual-backup-$(date +%s) -n database-namespace
```

Restore from backup:

```bash
# Download backup
aws s3 cp s3://nitroberry-db-backups/backups/nitroberry_2024-01-15_02-00-00.sql.gz .

# Restore to database
gunzip -c nitroberry_2024-01-15_02-00-00.sql.gz | \
  kubectl exec -i postgres-0 -n database-namespace -- \
    psql -U postgres
```

### Log Aggregation

View logs for all pods in a namespace:

```bash
# Using kubectl
kubectl logs -n auth-namespace -l app=auth-api --tail=100 -f

# Using stern (recommended)
stern -n auth-namespace auth-api
```

### Scaling Operations

**Manual scaling:**

```bash
# Scale up auth-api to 5 replicas
kubectl scale deployment auth-api -n auth-namespace --replicas=5

# Check current replicas
kubectl get deployment auth-api -n auth-namespace
```

**Autoscaling status:**

```bash
# View HPA status
kubectl get hpa -A

# Describe HPA
kubectl describe hpa auth-api-hpa -n auth-namespace
```

### Database Maintenance

**Connect to database:**

```bash
kubectl exec -it postgres-0 -n database-namespace -- \
  psql -U postgres
```

**List all schemas:**

```sql
\dn
```

**Switch to a schema:**

```sql
SET search_path TO auth;
\dt
```

---

## 🔍 Troubleshooting

### Common Issues

#### Pods Not Starting

```bash
# Check pod status
kubectl get pods -A

# View pod logs
kubectl logs <pod-name> -n <namespace>

# Describe pod (shows events)
kubectl describe pod <pod-name> -n <namespace>

# View all recent events
kubectl get events -A --sort-by='.lastTimestamp' | tail -20
```

#### `ErrImagePull` / `ImagePullBackOff`

**Minikube:**
```bash
# Ensure Docker is pointed at Minikube
eval $(minikube docker-env)

# Rebuild image
docker build -t nitroberry-mock-api:local .

# Verify image exists
minikube ssh -- docker images | grep nitroberry

# Restart deployment
kubectl rollout restart deployment/auth-api -n auth-namespace
```

**Production:**
```bash
# Check image exists in registry
docker pull yourregistry.azurecr.io/auth-api:v1.0.0

# Check image pull secret (if using private registry)
kubectl get secret -n auth-namespace
kubectl describe secret <image-pull-secret> -n auth-namespace
```

#### Database Connection Issues

```bash
# Check Postgres is running
kubectl get pods -n database-namespace

# View Postgres logs
kubectl logs postgres-0 -n database-namespace

# Test connection from a pod
kubectl run test-pg --image=postgres:15 --rm -it -- \
  psql -h postgres-service.database-namespace.svc.cluster.local -U postgres

# Check NetworkPolicy
kubectl get networkpolicy -A
```

#### Traefik Not Routing

```bash
# Check Traefik is running
kubectl get pods -n traefik-ingress

# View Traefik logs
kubectl logs -n traefik-ingress deployment/traefik

# Access Traefik dashboard
kubectl port-forward -n traefik-ingress svc/traefik-service 8080:8080
# Open http://localhost:8080/dashboard/

# Check IngressRoutes
kubectl get ingressroute -A
kubectl describe ingressroute auth-api-websecure -n auth-namespace
```

#### SSL/TLS Certificate Issues

```bash
# Check Traefik ACME logs
kubectl logs -n traefik-ingress deployment/traefik | grep acme

# Verify DNS is pointing to LoadBalancer IP
nslookup auth.nitroberry.com

# Ensure ports 80 and 443 are open
curl -I http://auth.nitroberry.com
curl -I https://auth.nitroberry.com
```

#### MetalLB Not Assigning IPs

```bash
# Check MetalLB pods
kubectl get pods -n metallb-system

# View MetalLB logs
kubectl logs -n metallb-system -l app=metallb

# Check IP pool configuration
kubectl get ipaddresspool -n metallb-system -o yaml

# Check LoadBalancer services
kubectl get svc -A | grep LoadBalancer
```

#### HPA Not Scaling

```bash
# Check HPA status
kubectl get hpa -A

# Describe HPA
kubectl describe hpa auth-api-hpa -n auth-namespace

# Check metrics-server is running
kubectl get deployment metrics-server -n kube-system

# View current resource usage
kubectl top pods -n auth-namespace
```

#### OPA Gatekeeper Blocking Deployments

```bash
# Check Gatekeeper admission webhooks
kubectl get validatingwebhookconfigurations | grep gatekeeper

# View constraint violations
kubectl get constraints

# Describe a specific constraint
kubectl describe requireresourcelimits require-resource-limits

# Temporarily disable a constraint (for testing)
kubectl patch requireresourcelimits require-resource-limits \
  -p '{"spec":{"enforcementAction":"dryrun"}}' --type=merge
```

### Quick Health Check Script

Save as `health-check.sh`:

```bash
#!/bin/bash
echo "=== Nitroberry Health Check ==="
echo ""

echo "Cluster Info:"
kubectl cluster-info

echo ""
echo "Nodes:"
kubectl get nodes

echo ""
echo "All Pods:"
kubectl get pods -A | grep -E "traefik|auth|users|orders|products|notify|postgres"

echo ""
echo "LoadBalancer Services:"
kubectl get svc -A | grep LoadBalancer

echo ""
echo "HPA Status:"
kubectl get hpa -A

echo ""
echo "OPA Gatekeeper Constraints:"
kubectl get constraints 2>/dev/null || echo "(OPA not installed)"

echo ""
echo "=== Done ==="
```

```bash
chmod +x health-check.sh
./health-check.sh
```

---

## 📖 API Reference

### Service Endpoints

| Service | Production Domain | Local Port | Schema |
|---------|-------------------|------------|--------|
| auth-api | `https://auth.nitroberry.com` | 9001 | `auth` |
| users-api | `https://users.nitroberry.com` | 9002 | `users` |
| orders-api | `https://orders.nitroberry.com` | 9003 | `orders` |
| products-api | `https://products.nitroberry.com` | 9004 | `products` |
| notify-api | `https://notify.nitroberry.com` | 9005 | `notify` |

### Auth API

**Public Endpoints:**

```bash
# Health check
GET /health
Response: {"service":"auth","status":"healthy","uptime":"123.4s"}

# Login (returns demo JWT)
GET /login
Response: {"token":"eyJhbGci...","expires_in":3600}

# Public info
GET /public/info
Response: {"service":"auth","version":"1.0.0"}
```

**Protected Endpoints:**

```bash
# All other paths require JWT
GET /validate
Headers: Authorization: Bearer <token>
Response: {"service":"auth","data":{"tokens":[...]}}
```

### Users API

```bash
# Health
GET /health

# Public info
GET /public/info

# User profiles (JWT required)
GET /profiles
Headers: Authorization: Bearer <token>
Response: {
  "service":"users",
  "data":{
    "profiles":[
      {"id":1,"name":"Alice","email":"alice@demo.local"},
      {"id":2,"name":"Bob","email":"bob@demo.local"}
    ]
  }
}
```

### Orders API

```bash
# Health
GET /health

# Public info
GET /public/info

# Orders list (JWT required)
GET /orders
Headers: Authorization: Bearer <token>
Response: {
  "service":"orders",
  "data":{
    "orders":[
      {"id":"ORD-001","status":"delivered","total":129.99},
      {"id":"ORD-002","status":"processing","total":59.50}
    ]
  }
}
```

### Products API

```bash
# Health
GET /health

# Public info
GET /public/info

# Product catalog (JWT required)
GET /items
Headers: Authorization: Bearer <token>
Response: {
  "service":"products",
  "data":{
    "items":[
      {"id":"P001","name":"Keyboard","price":89.99,"stock":142},
      {"id":"P002","name":"USB Hub","price":49.99,"stock":89}
    ]
  }
}
```

### Notify API

```bash
# Health
GET /health

# Public info
GET /public/info

# Notifications (JWT required)
GET /notifications
Headers: Authorization: Bearer <token>
Response: {
  "service":"notify",
  "data":{
    "notifications":[
      {"id":1,"type":"email","message":"Order shipped!","status":"sent"}
    ]
  }
}
```

### Response Headers

All responses include:

```http
X-Service: auth-api             # Service identifier
Access-Control-Allow-Origin: *  # CORS (configure as needed)
Content-Type: application/json
```

---

## 🤝 Contributing

Contributions are welcome! Please follow these guidelines:

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/amazing-feature`
3. **Test locally**: Run `./local-test.ps1` (Windows) or deploy to Minikube
4. **Commit your changes**: `git commit -m 'Add amazing feature'`
5. **Push to the branch**: `git push origin feature/amazing-feature`
6. **Open a Pull Request**

### Development Workflow

1. Make changes to YAML manifests
2. Test in Minikube:
   ```bash
   kubectl apply -f <changed-file>.yaml
   kubectl rollout restart deployment/<affected-deployment>
   ```
3. Verify with health checks
4. Update README if needed
5. Submit PR

---

<div align="center">


[⬆ Back to Top](#nitroberry--production-ready-kubernetes-microservices-architecture)

</div>