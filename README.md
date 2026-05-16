# Nitroberry — Production-Ready Kubernetes Microservices Architecture

<div align="center">

![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?style=for-the-badge&logo=kubernetes&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/postgresql-%23316192.svg?style=for-the-badge&logo=postgresql&logoColor=white)
![Traefik](https://img.shields.io/badge/traefik-%2324A1C1.svg?style=for-the-badge&logo=traefikproxy&logoColor=white)
![AWS ECR](https://img.shields.io/badge/AWS_ECR-%23FF9900.svg?style=for-the-badge&logo=amazon-aws&logoColor=white)
![ArgoCD](https://img.shields.io/badge/ArgoCD-%23ef7b4d.svg?style=for-the-badge&logo=argo&logoColor=white)

A **production-grade**, **GitOps-driven** Kubernetes architecture for 7 microservices. Featuring **ArgoCD + OCI Helm**, **Automated ECR Auth Refresh**, and **Traefik v3** Ingress.

</div>

---

## 🏗 System Architecture & GitOps Flow

![Nitroberry GitOps Flow](./nitroberry_gitops_flow_diagram_1778942229381.png)

### The Workflow:
1.  **Code Push**: Developer pushes to `main`.
2.  **GitHub Actions (CI)**:
    *   Builds and pushes Docker images to ECR.
    *   **Auto-increments** the Helm Chart version in `Chart.yaml`.
    *   Packages and pushes the Helm Chart as an **OCI Artifact** to ECR.
    *   Commits the version bump back to Git.
3.  **ECR (Mumbai)**: Acts as the single source of truth for both container images and Helm charts.
4.  **ArgoCD (CD)**: Detects the new chart version in ECR OCI and automatically synchronizes the cluster state.
5.  **ECR Helper (Security)**: A CronJob inside the cluster refreshes the 12-hour AWS ECR tokens every 8 hours, ensuring zero downtime for image/chart pulling.

---

## 🛠 What We Updated (Recent Changes)

To automate the production environment, the following core components were updated:

### 1. `.github/workflows/nitroberry-workflow.yaml` (The Engine)
*   **OCI Support**: Added `helm registry login` and `helm push` to handle Helm charts in ECR.
*   **Version Sync**: The CI now automatically reads `Chart.yaml`, increments the version, and sets the `appVersion` to match the Docker image tag.
*   **Git Writeback**: Added `contents: write` permissions so the CI can save the version bump back to the repository.

### 2. `ecr-helper.yaml` (The Auth Fix)
*   **Repository Secret Refresh**: Previously, only pod-level image secrets were refreshed. We added logic to also refresh the **ArgoCD Repository Secret** (`ecr-repo-creds`).
*   **Unified Auth**: This solves the ECR 12-hour expiry issue. Your cluster now has "perpetual" access to AWS registries without manual intervention.

### 3. `argocd-app.yaml` (The Controller)
*   Converted `repoURL` to the `oci://` format.
*   Enabled **Auto-Prune** and **Self-Healing** for production stability.

---

## 🚀 How to Deploy (Fresh Start)

### Step 1: Prerequisites
*   A running Kubernetes cluster (v1.28+).
*   `helm` and `kubectl` installed locally.
*   ArgoCD installed in the `argocd` namespace.
*   AWS IAM User with `AmazonEC2ContainerRegistryFullAccess`.

### Step 2: Bootstrap ECR Authentication
Since ArgoCD needs a token to pull the chart for the first time, run this command once:
```bash
# Get fresh token and create the secret ArgoCD needs
TOKEN=$(aws ecr get-login-password --region ap-south-1)
kubectl create secret generic ecr-repo-creds -n argocd \
  --from-literal=url=798701233691.dkr.ecr.ap-south-1.amazonaws.com \
  --from-literal=username=AWS \
  --from-literal=password=$TOKEN \
  --from-literal=enableOCI=true \
  --from-literal=type=helm

# Label it so ArgoCD detects it as a Repository
kubectl label secret ecr-repo-creds -n argocd argocd.argoproj.io/secret-type=repository --overwrite
```

### Step 3: Configure Production Values
Open `kubernetes_nitroberry/charts/nitroberry/values.yaml` and set:
*   `aws.access_key_id`: Your AWS key.
*   `aws.secret_access_key`: Your AWS secret.
*   `database.password`: A strong unique password.

### Step 4: Launch ArgoCD App
```bash
kubectl apply -f argocd-app.yaml
```

---

## 📋 Production Field Checklist

| File | Field | Purpose |
|------|-------|---------|
| `values.yaml` | `global.registry` | Your AWS ECR Domain. |
| `values.yaml` | `aws.region` | ECR Region (e.g. `ap-south-1`). |
| `argocd-app.yaml` | `targetRevision` | Must match the `version` in `Chart.yaml`. |
| `06` - `14` | `Host()` | Replace `nitroberry.com` with your production URL. |

---

## 🔒 Security Features
*   **Network Policies**: Hardened pod communication (Auth can only talk to DB).
*   **Non-Root**: All containers run with UID 1000 for safety.
*   **Token Refresh**: Automated AWS token rotation every 8 hours.

---

## 🛠 Troubleshooting
*   **Check Token Status**: `kubectl get secrets -A | grep ecr`
*   **Check ArgoCD Sync**: `kubectl get app nitroberry -n argocd`
*   **View CI Logs**: Check the "Package and Push Helm Chart" job in GitHub Actions.