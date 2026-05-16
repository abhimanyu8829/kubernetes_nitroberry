# NitroBerry — Production‑Ready Kubernetes Microservices Architecture

<div align="center">

![GitOps Flow Diagram](file:///C:/Users/DELL-OS/.gemini/antigravity/brain/a76cc1b5-4939-4bca-b8b5-ec5867502be4/nitroberry_gitops_flow_diagram_1778942229381.png)

</div>

---

## 📋 Table of Contents
- [Overview](#overview)
- [Full Architecture Diagram](#full-architecture-diagram)
- [Prerequisites](#prerequisites)
- [Step‑by‑Step Deployment Guide](#step‑by‑step-deployment-guide)
- [GitHub Actions CI – Updated Workflow](#github-actions-ci---updated-workflow)
- [ArgoCD & OCI Helm Chart Support](#argocd---oci-helm-chart-support)
- [ECR Token Refresh – No Expiry](#ecr-token-refresh---no-expiry)
- [Production Checklist – Values to Replace](#production-checklist---values-to-replace)
- [Rollback Procedure](#rollback-procedure)
- [Security & Best Practices](#security--best-practices)
- [Troubleshooting](#troubleshooting)

---

## 🌟 Overview
NitroBerry is a **bare‑metal, production‑grade Kubernetes platform** that runs **seven micro‑services** (Auth, Cockpit, Messenger, Social, Task, Vault, Workflow).  
Each service (except Messenger) ships **two containers** – an **API** and a **Worker** – all images live in **AWS ECR (Mumbai region)**.  
GitHub Actions builds immutable image tags (`0.0.0.x`), pushes them to ECR, packages the Helm chart as an **OCI artifact**, and finally pushes the chart back to the same ECR registry.

ArgoCD runs inside the cluster, pulls the OCI Helm chart directly from ECR, and **auto‑syncs** whenever a new chart version appears.  No `kubectl apply` is ever executed on production VMs.

---

## 📐 Full Architecture Diagram
The diagram above visualises the complete **GitOps flow**:
1. **Developer pushes code** → GitHub Actions builds Docker image.
2. **CI pushes the image** and **updates the Helm chart** (new `Chart.yaml` version, `appVersion` set to the image tag).
3. **Helm chart is stored as OCI** in the same ECR registry.
4. **ArgoCD pulls the OCI chart** (requires an ECR token).
5. **CronJob `ecr-token-refresh`** runs every 8 h, regenerates the AWS token and updates two secrets:
   - `ecr-regcred` (used by all Pods for image pulls)
   - `ecr-repo-creds` (used by ArgoCD to pull the Helm chart).  
   This eliminates the 12‑hour token expiry problem.
6. **ArgoCD syncs** → **Rolling Update** of all services.

---

## 🛠 Prerequisites
| Item | Details |
|------|---------|
| **Kubernetes** | v1.28+ (bare‑metal or any conforming distribution) |
| **AWS** | IAM user/role with `AmazonEC2ContainerRegistryFullAccess` and read/write to the S3 bucket used for DB backups |
| **AWS Secrets** | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION` – stored in GitHub Secrets (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`) |
| **GitHub** | Repository with the files in this repo; a **Personal Access Token** (`repo` scope) stored as secret `GH_PAT` (used by CI to push the bumped `Chart.yaml`). |
| **Domain** | A wildcard DNS (`*.nitroberry.com`) pointing at the MetalLB LoadBalancer IP. |
| **ECR Repositories** | One repo per service (e.g. `nitroberry/auth-api`, `nitroberry/auth-worker`, …) **and** a repo to host the Helm chart (`nitroberry/helm`). |

---

## 🚀 Step‑by‑Step Deployment Guide
1. **Create the AWS credential secret** (run once):
   ```bash
   kubectl create secret generic ecr-regcred \
     --docker-server=798701233691.dkr.ecr.ap-south-1.amazonaws.com \
     --docker-username=AWS \
     --docker-password=$(aws ecr get-login-password --region ap-south-1) \
     -n argocd
   ```
2. **Deploy the ECR token refresh CronJob** (this also creates the ArgoCD repository secret):
   ```bash
   kubectl apply -f charts/nitroberry/templates/ecr-helper.yaml
   ```
3. **Apply core infrastructure** – namespaces, MetalLB, PostgreSQL, Traefik, OPA Gatekeeper:
   ```bash
   kubectl apply -f 00-namespaces.yaml
   kubectl apply -f 01-metallb.yaml
   kubectl apply -f 02-postgres.yaml
   kubectl apply -f 03-traefik-rbac.yaml
   kubectl apply -f 04-traefik-install.yaml
   kubectl apply -f 05-traefik-middlewares.yaml
   ```
4. **Configure `values.yaml`**:
   * Replace **all** `REPLACE_WITH_…` placeholders (DB passwords, JWT secret, AWS keys, S3 bucket).  
   * Update the `host` fields under each service to your real domain (e.g. `auth.mycompany.com`).
   * Adjust MetalLB IP range in `01-metallb.yaml` to match your LAN/subnet.
5. **Commit the updated `values.yaml`** and push to `main`. This triggers the CI pipeline.
6. **CI pipeline** builds Docker images, pushes them, bumps the chart version, pushes the chart to ECR, and pushes the version bump back to Git (requires `GH_PAT`).
7. **ArgoCD automatically detects the new chart version** (because `argocd-app.yaml` points at `oci://…` with `automated` sync) and rolls out a **RollingUpdate** of all services.
8. **Verify**:
   ```bash
   kubectl get pods -A
   argocd app get nitroberry   # should show Health=Healthy, Sync=Synced
   ```

---

## 📁 GitHub Actions CI – Updated Workflow (`.github/workflows/nitroberry-workflow.yaml`)
### Key Changes
| Change | Reason |
|--------|--------|
| `permissions: contents: write` | Allows the workflow to commit the bumped `Chart.yaml` back to the repo. |
| New **`helm-release`** job | Packages the Helm chart, auto‑increments `version` in `Chart.yaml`, sets `appVersion` to the Docker tag, pushes the chart to the **OCI** registry, and commits the version bump. |
| Uses `GH_PAT` (or default `GITHUB_TOKEN`) for the checkout step so the push succeeds. |
| The Helm chart push uses `helm registry login` with the same AWS credentials used for Docker. |

You can view the full YAML in the repo – it is the file you already have under `.github/workflows/nitroberry-workflow.yaml`.

---

## 🌐 ArgoCD & OCI Helm Chart Support
- **`argocd-app.yaml`** now uses `repoURL: oci://798701233691.dkr.ecr.ap-south-1.amazonaws.com`.
- **`targetRevision`** matches the `version` field in `Chart.yaml`.  When the CI bumps the chart version, ArgoCD sees the new OCI artifact and syncs automatically.
- **`automated` policy** is enabled with `prune: true` and `selfHeal: true` – any drift is corrected without manual `kubectl apply`.

---

## 🔑 ECR Token Refresh – No Expiry
The file `templates/ecr-helper.yaml` creates a **CronJob** that runs every **8 hours**:
1. Calls `aws ecr get-login-password`.
2. Re‑creates the `ecr-regcred` secret in **every namespace** (so Pods can always pull images).
3. Updates the **ArgoCD repository secret** `ecr-repo-creds` (labelled `argocd.argoproj.io/secret-type=repository`).
4. Labels the secret so ArgoCD recognises it automatically.

Because the CronJob runs **continuously**, the 12‑hour token expiry is no longer an operational risk – the cluster always has a fresh token.

---

## ✅ Production Checklist – Values to Replace
| File | Field | Example Replacement |
|------|-------|----------------------|
| `values.yaml` | `aws.access_key_id` / `aws.secret_access_key` | Your real AWS IAM keys (or use External Secrets) |
| `values.yaml` | `database.password` | Strong random password (e.g. `openssl rand -base64 24`) |
| `values.yaml` | `jwt-secret` | 256‑bit base64 string (`openssl rand -base64 32`) |
| `01-metallb.yaml` | `addresses` | `10.0.0.50-10.0.0.100` (your LAN range) |
| Service manifests (`06‑auth.yaml` … `14‑workflow.yaml`) | `Host()` | `auth.mycompany.com` (replace `nitroberry.com`) |
| Service manifests | `image:` tag | Replace `:latest` with the immutable tag generated by CI (`0.0.0.52`) |
| `argocd-app.yaml` | `targetRevision` | Must match the `version` in `Chart.yaml` (e.g., `1.0.3`) |

---

## 🔙 Rollback Procedure
1. Find the previous chart version in ECR: `oci://…/nitroberry` list tags.
2. Edit the ArgoCD Application (or run `argocd app set nitroberry --revision <old‑version>`).
3. ArgoCD will **downgrade** all services to the previous chart – the rollback is instant and atomic.

---

## 🔐 Security & Best Practices
- **Never commit raw secrets** – use **External Secrets Operator** or **sealed‑secrets** for production.
- **NetworkPolicies** already restrict pods to talk only to the database and Traefik.
- **PodSecurityContext** enforces non‑root containers and read‑only root filesystem.
- **OPA Gatekeeper** validates container images, resource limits, and securityContext on every apply.
- **Metrics‑Server** must be installed for HPA to work.
- **PostgreSQL HA**: the current StatefulSet is single‑replica; for real HA use **AWS RDS** or a dedicated Postgres operator.

---

## 🛠 Troubleshooting
| Symptom | Quick Check |
|---------|-------------|
| Pods stuck in `ImagePullBackOff` | Verify `ecr-regcred` exists in the pod namespace and contains a valid token (`kubectl get secret ecr-regcred -n <ns> -o yaml`). |
| ArgoCD shows `OutOfSync` but no changes | Make sure the `Chart.yaml` version matches the image tag (`appVersion`). |
| Rollback does not happen | Confirm the older chart version exists in the ECR OCI registry and that `argocd-app.yaml` points at the correct `targetRevision`. |
| HPA not scaling | Ensure `metrics-server` is installed and the `resources.requests`/`limits` are defined. |

---

## 🎉 You’re Ready!
Follow the checklist, commit your configuration, push to `main`, and let the **GitHub Actions CI** + **ArgoCD** orchestrate a fully automated, production‑grade rollout of NitroBerry.

Happy deploying! 🚀