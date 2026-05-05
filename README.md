# Nitroberry — Bare Metal Kubernetes Architecture

A production-ready, multi-namespace Kubernetes architecture for bare-metal environments. Uses **Traefik v3** as the ingress controller, **MetalLB** for load balancing, and **PostgreSQL 15** as a shared multi-schema database — with a fully tested **local Minikube workflow** for development and demo.

---

## Repository structure

```
kubernetes_nitroberry/
├── 00-namespaces.yaml          # All 7 namespaces
├── 01-metallb.yaml             # MetalLB IP pool (bare-metal only, skip in Minikube)
├── 02-postgres.yaml            # PostgreSQL 15 StatefulSet + NetworkPolicy
├── 03-traefik-rbac.yaml        # Traefik ServiceAccount + ClusterRole
├── 04-traefik-install.yaml     # Traefik v3 Deployment + LoadBalancer Service
├── 05-traefik-middlewares.yaml # JWT auth + rate limiting + security headers
├── 06-auth-api.yaml            # auth-api: Deployment, Service, HPA, IngressRoute
├── 07-users-api.yaml           # users-api: Deployment, Service, HPA, IngressRoute
├── 08-orders-api.yaml          # orders-api: Deployment, Service, HPA, IngressRoute
├── 09-products-api.yaml        # products-api: Deployment, Service, HPA, IngressRoute
├── 10-notify-api.yaml          # notify-api: Deployment, Service, HPA, IngressRoute
├── configure.sh                # Automated sed script to swap all prod values
└── get_helm.sh                 # Official Helm installer script
```

---

## Architecture overview

```
External Traffic
      │
      ▼
MetalLB LoadBalancer IP  (bare-metal only)
      │
      ▼
┌─────────────────────────────┐
│     traefik-ingress         │
│  Traefik v3  +  Middlewares │
│  JWT · RateLimit · Headers  │
└──────┬──────────────────────┘
       │  routes by Host()
  ┌────┴──────────────────────────────────────┐
  ▼        ▼         ▼          ▼         ▼
auth     users     orders    products   notify
 api      api       api        api       api
  │        │         │          │         │
  └────────┴─────────┴──────────┴─────────┘
                     │
                     ▼
            database-namespace
             PostgreSQL 15
         (schemas: auth, users,
          orders, products, notify)
```

## Service grid

| Service | Namespace | Production subdomain | Local port | Public paths |
|---|---|---|---|---|
| auth-api | auth-namespace | `auth.yourdomain.com` | 9001 | `/login` `/health` `/public` |
| users-api | users-namespace | `users.yourdomain.com` | 9002 | `/health` `/public` |
| orders-api | orders-namespace | `orders.yourdomain.com` | 9003 | `/health` `/public` |
| products-api | products-namespace | `products.yourdomain.com` | 9004 | `/health` `/public` |
| notify-api | notify-namespace | `notify.yourdomain.com` | 9005 | `/health` `/public` |

All other paths require a valid JWT passed as `Authorization: Bearer <token>`.

---

## Local Minikube setup (fully tested)

Use this workflow to run the entire stack locally without a bare-metal cluster. This was tested end-to-end and produces live JSON API responses from all 5 services.

### Prerequisites

- Docker installed and running
- `minikube` installed
- `kubectl` installed (or use `minikube kubectl --`)

### Step 1 — Start Minikube

```bash
minikube start --memory=4096 --cpus=2 --driver=docker
minikube addons enable ingress
```

> If you get "cannot change the memory size for an existing cluster", delete first:
> `minikube delete && minikube start --memory=4096 --cpus=2 --driver=docker`

### Step 2 — Point Docker at Minikube's daemon

This is required so images built locally are available to the cluster without pushing to a registry. **Run this in every new terminal session.**

```bash
eval $(minikube docker-env)
```

### Step 3 — Build the mock API image

Since the production images (`nitroberry/auth-api:latest` etc.) don't exist yet, create a single Node.js mock server that all 5 services share, differentiated by environment variables.

Create `server.js`:

```bash
cat > server.js << 'EOF'
const http = require('http');
const SERVICE = process.env.SERVICE_NAME || 'api';
const PORT = process.env.PORT || 8080;
const SCHEMA = process.env.DB_SCHEMA || 'public';
const data = {
  auth:     { tokens: [{id:1,user:'alice',role:'admin'}] },
  users:    { profiles: [{id:1,name:'Alice',email:'alice@demo.local'},{id:2,name:'Bob',email:'bob@demo.local'}] },
  orders:   { orders: [{id:'ORD-001',status:'delivered',total:129.99},{id:'ORD-002',status:'processing',total:59.50}] },
  products: { items: [{id:'P001',name:'Keyboard',price:89.99,stock:142},{id:'P002',name:'USB Hub',price:49.99,stock:89}] },
  notify:   { notifications: [{id:1,type:'email',message:'Order shipped!',status:'sent'}] }
};
http.createServer((req,res) => {
  const p = req.url.split('?')[0];
  let body = {service:SERVICE,schema:SCHEMA,ts:new Date().toISOString()};
  if(p==='/health') body={...body,status:'healthy',uptime:process.uptime().toFixed(1)+'s'};
  else if(p==='/public/info') body={...body,version:'1.0.0'};
  else if(p==='/login') body={token:'eyJhbGciOiJIUzI1NiJ9.demo.sig',expires_in:3600};
  else body={...body,data:data[SCHEMA]||{}};
  res.writeHead(200,{'Content-Type':'application/json','X-Service':SERVICE,'Access-Control-Allow-Origin':'*'});
  res.end(JSON.stringify(body,null,2));
  console.log(new Date().toISOString().slice(11,19),req.method,req.url,'200');
}).listen(PORT,()=>console.log('['+SERVICE+'] :'+PORT+' schema='+SCHEMA));
EOF
```

Create `Dockerfile`:

```bash
cat > Dockerfile << 'EOF'
FROM node:20-alpine
WORKDIR /app
COPY server.js .
EXPOSE 8080
CMD ["node", "server.js"]
EOF
```

Build the image inside Minikube's Docker:

```bash
docker build -t nitroberry-mock-api:local .
```

Verify the image is present:

```bash
minikube ssh -- docker images | grep nitroberry
```

### Step 4 — Deploy namespaces and Postgres

```bash
kubectl apply -f 00-namespaces.yaml
kubectl apply -f 02-postgres.yaml
kubectl rollout status statefulset/postgres -n database-namespace
```

> Skip `01-metallb.yaml` — MetalLB is not needed in Minikube. Port-forward handles local access.

### Step 5 — Deploy Traefik

```bash
kubectl apply -f 03-traefik-rbac.yaml
kubectl apply -f 04-traefik-install.yaml
kubectl apply -f 05-traefik-middlewares.yaml
kubectl rollout status deployment/traefik -n traefik-ingress
```

> The JWT Traefik plugin (`jwt-verification`) requires network access to GitHub to download at startup. In a restricted environment it will crash Traefik. The middlewares file still applies — rate-limit and security-headers work fine. To disable only the JWT plugin, comment out the `--experimental.plugins.*` args in `04-traefik-install.yaml`.

### Step 6 — Deploy the 5 API services

Apply the original manifests (creates Services, HPAs, IngressRoutes, NetworkPolicies):

```bash
kubectl apply -f 06-auth-api.yaml
kubectl apply -f 07-users-api.yaml
kubectl apply -f 08-orders-api.yaml
kubectl apply -f 09-products-api.yaml
kubectl apply -f 10-notify-api.yaml
```

Patch all 5 deployments to use the local mock image instead of the placeholder registry images:

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

Expected output — 2 pods per service, all `Running`:

```
auth-namespace       auth-api-xxxxx     1/1     Running   0   60s
auth-namespace       auth-api-xxxxx     1/1     Running   0   60s
notify-namespace     notify-api-xxxxx   1/1     Running   0   60s
notify-namespace     notify-api-xxxxx   1/1     Running   0   60s
orders-namespace     orders-api-xxxxx   1/1     Running   0   60s
orders-namespace     orders-api-xxxxx   1/1     Running   0   60s
products-namespace   products-api-xxxxx 1/1     Running   0   60s
products-namespace   products-api-xxxxx 1/1     Running   0   60s
users-namespace      users-api-xxxxx    1/1     Running   0   60s
users-namespace      users-api-xxxxx    1/1     Running   0   60s
```

### Step 7 — Port-forward and test

Start all port-forwards in the background:

```bash
kubectl port-forward svc/auth-api-service     9001:8080 -n auth-namespace     &
kubectl port-forward svc/users-api-service    9002:8080 -n users-namespace    &
kubectl port-forward svc/orders-api-service   9003:8080 -n orders-namespace   &
kubectl port-forward svc/products-api-service 9004:8080 -n products-namespace &
kubectl port-forward svc/notify-api-service   9005:8080 -n notify-namespace   &
```

Test health endpoints for all services:

```bash
for PORT in 9001 9002 9003 9004 9005; do
  echo "=== :$PORT ===" && curl -s localhost:$PORT/health
  echo ""
done
```

Test data endpoints:

```bash
echo "--- AUTH: login ---"    && curl -s localhost:9001/login         && echo ""
echo "--- USERS: profiles ---" && curl -s localhost:9002/profiles      && echo ""
echo "--- ORDERS: orders ---"  && curl -s localhost:9003/orders        && echo ""
echo "--- PRODUCTS: items ---" && curl -s localhost:9004/items         && echo ""
echo "--- NOTIFY: notify ---"  && curl -s localhost:9005/notifications && echo ""
```

Expected response example (users-api):

```json
{
  "service": "users",
  "schema": "users",
  "ts": "2026-05-04T06:52:15.523Z",
  "data": {
    "profiles": [
      { "id": 1, "name": "Alice", "email": "alice@demo.local" },
      { "id": 2, "name": "Bob",   "email": "bob@demo.local"   }
    ]
  }
}
```

### Step 8 — Traefik dashboard (optional)

```bash
kubectl port-forward svc/traefik-service 8080:8080 -n traefik-ingress &
xdg-open http://localhost:8080/dashboard/
```

### Teardown

```bash
pkill -f "kubectl port-forward"   # stop all port-forwards
minikube stop                      # pause cluster, keeps state
minikube delete                    # destroy cluster entirely
```

---

## Production bare-metal deployment

### Prerequisites

- Ubuntu/Debian VM with Kubernetes control plane running (kubelet, kube-apiserver, etcd)
- MetalLB installed
- Network policies enabled on the cluster
- Persistent storage available (for Postgres PVC and Traefik ACME PVC)
- Ports 80 and 443 open in firewall
- DNS A record for `*.yourdomain.com` pointing to the MetalLB LoadBalancer IP

#### Install Kubernetes on a fresh Ubuntu VM

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y docker.io
sudo systemctl enable --now docker

sudo apt install -y apt-transport-https ca-certificates curl
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/kubernetes-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] \
  https://apt.kubernetes.io/ kubernetes-xenial main" \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update && sudo apt install -y kubelet kubeadm kubectl
sudo systemctl enable --now kubelet

sudo kubeadm init --pod-network-cidr=10.244.0.0/16
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.12/config/manifests/metallb-native.yaml
```

#### Install Helm

```bash
chmod +x get_helm.sh
./get_helm.sh               # latest
./get_helm.sh --version v3.14.0  # specific version
helm version                # verify
```

### Step 0 — Configure values for your environment

Edit `configure.sh` and set your values:

```bash
YOUR_DOMAIN="yourdomain.com"
YOUR_IP_RANGE="10.0.0.100-10.0.0.150"
YOUR_EMAIL="admin@yourdomain.com"
YOUR_DB_PASSWORD="YourSecurePass123!"
YOUR_REGISTRY="yourregistry.com"
IMAGE_TAG="v1.0.0"
```

Then run it:

```bash
chmod +x configure.sh
./configure.sh
```

This updates MetalLB IP range, all domain references, Let's Encrypt email, database password, and container image references across all YAML files in one pass.

### Step 1 — Namespaces and MetalLB

```bash
kubectl apply -f 00-namespaces.yaml
kubectl apply -f 01-metallb.yaml    # edit IP range first
```

### Step 2 — Postgres

```bash
kubectl apply -f 02-postgres.yaml
kubectl rollout status statefulset/postgres -n database-namespace
```

Creates a StatefulSet with a 10Gi PVC and auto-initialises 5 schemas: `auth`, `users`, `orders`, `products`, `notify`.

### Step 3 — Traefik

```bash
kubectl apply -f 03-traefik-rbac.yaml
kubectl apply -f 04-traefik-install.yaml
kubectl apply -f 05-traefik-middlewares.yaml
kubectl rollout status deployment/traefik -n traefik-ingress
```

### Step 4 — API services

```bash
kubectl apply -f 06-auth-api.yaml
kubectl apply -f 07-users-api.yaml
kubectl apply -f 08-orders-api.yaml
kubectl apply -f 09-products-api.yaml
kubectl apply -f 10-notify-api.yaml
```

### Verify

```bash
kubectl get pods -A
kubectl get svc -n traefik-ingress
kubectl get hpa -A
kubectl get ingressroute -A
```

Test DB connectivity from inside a pod:

```bash
kubectl exec -it <auth-pod-name> -n auth-namespace -- \
  psql -h postgres-service.database-namespace.svc.cluster.local -U postgres
```

---

## Production configuration reference

### 1 — MetalLB IP pool (`01-metallb.yaml`)

```yaml
spec:
  addresses:
  - 192.168.49.200-192.168.49.250   # replace with your VM's available IP range
```

### 2 — Domain names (files `06` through `10`)

In each IngressRoute, change the `Host()` matcher:

```yaml
- match: Host(`auth.nitroberry.com`) && PathPrefix(`/health`)
# becomes:
- match: Host(`auth.yourdomain.com`) && PathPrefix(`/health`)
```

### 3 — Let's Encrypt email (`04-traefik-install.yaml`)

```yaml
- --certificatesresolvers.myresolver.acme.email=admin@nitroberry.com
# replace with your email
```

### 4 — Database password

Must be updated in `02-postgres.yaml` (the Secret) and in each API YAML (the `DATABASE_URL` env var). The `configure.sh` script handles all of these automatically.

### 5 — Container images

Each API YAML has:

```yaml
image: nitroberry/auth-api:latest
```

Replace with your registry:

```yaml
image: yourregistry.com/auth-api:v1.0.0
```

And remove the `imagePullPolicy: Never` patch applied during local development.

---

## Security and scaling

### Middlewares

- **JWT validation** — enforced at the Traefik layer for all non-public paths. Uses the `jwt-verification` plugin (`github.com/traefik-plugins/jwt-verification v0.2.1`).
- **Rate limiting** — 100 requests/sec average, burst of 50, applied globally.
- **Security headers** — HSTS (1 year, preload), XSS filter, content-type sniff protection, `X-Frame-Options: SAMEORIGIN`.

### Network policies

Every namespace has a `NetworkPolicy` that allows:
- **Ingress**: only from `traefik-ingress` namespace on port 8080
- **Egress**: only to `database-namespace` on port 5432

No cross-service API traffic is permitted through network policy.

### Autoscaling (HPA)

All 5 APIs have identical HPA config:

| Setting | Value |
|---|---|
| Min replicas | 2 |
| Max replicas | 10 |
| CPU threshold | 70% utilisation |

---

## Troubleshooting

### Pods not starting

```bash
kubectl get pods -A
kubectl logs <pod-name> -n <namespace>
kubectl describe pod <pod-name> -n <namespace>
kubectl get events -A --sort-by='.lastTimestamp'
```

### `ErrImageNeverPull` in Minikube

The local image is not visible to the cluster. Make sure you built it after running `eval $(minikube docker-env)` in the same terminal session:

```bash
eval $(minikube docker-env)
docker build -t nitroberry-mock-api:local .
minikube ssh -- docker images | grep nitroberry  # confirm it's there
```

### `CrashLoopBackOff` — syntax error in server.js

If the heredoc copy produced `data[SCHEMA]||` without `{}`, Node.js will crash. Fix:

```bash
grep "data\[SCHEMA\]" server.js          # check the line
sed -i 's/data\[SCHEMA\]||}/data[SCHEMA]||{}}/g' server.js  # fix if needed
docker build -t nitroberry-mock-api:local .
for SVC in auth users orders products notify; do
  kubectl rollout restart deployment/${SVC}-api -n ${SVC}-namespace
done
```

### MetalLB not assigning IPs

```bash
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
kubectl get svc -A | grep LoadBalancer
```

### Traefik not routing

```bash
kubectl get ingressroute -A
kubectl logs -n traefik-ingress deployment/traefik
kubectl port-forward -n traefik-ingress svc/traefik-service 8080:8080
# then open http://localhost:8080/dashboard/
```

### SSL certificate issues

```bash
kubectl logs -n traefik-ingress deployment/traefik | grep acme
```

Ensure ports 80 and 443 are reachable from the internet (Let's Encrypt needs to reach your server for the TLS-ALPN-01 challenge).

### Database connection issues

```bash
kubectl get pods -n database-namespace
kubectl logs statefulset/postgres -n database-namespace
kubectl run test-pg --image=postgres:15 --rm -it -- \
  psql -h postgres-service.database-namespace.svc.cluster.local -U postgres
```

### Network policy issues

```bash
kubectl get networkpolicy -A
kubectl run test-dns --image=busybox --rm -it -- \
  nslookup postgres-service.database-namespace.svc.cluster.local
```

### Quick health check

```bash
#!/bin/bash
echo "=== Nitroberry Health Check ==="
kubectl cluster-info
kubectl get nodes
kubectl get pods -A
kubectl get svc -n traefik-ingress
kubectl get ipaddresspool -n metallb-system 2>/dev/null || echo "(metallb not installed)"
kubectl get hpa -A
echo "=== Done ==="
```