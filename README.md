# Jerney — GitOps on Azure Kubernetes Service

A 3-tier web application (frontend, backend, PostgreSQL) deployed on AKS using a fully automated GitOps pipeline. The focus of this project is the end-to-end DevOps workflow: infrastructure provisioning, containerisation, GitOps-driven deployment, and CI/CD automation.

---

## Architecture Overview

```
GitHub Actions
     │
     ├── Terraform ──────────────► Azure (AKS + Resource Group)
     │                                      │
     ├── Docker Build & Push                │ ArgoCD installed via Helm
     │        │                             │
     │        ▼                             ▼
     │   Docker Hub              ArgoCD (root-application)
     │                                      │
     └── Bootstrap root-app                 ├── ingress-nginx (Helm chart)
              │                             │       └── Azure LoadBalancer (public IP)
              │                             │
              └──────────────────────────── └── jerney-stack (Helm chart)
                                                    ├── Frontend (nginx)
                                                    ├── Backend (Node.js)
                                                    └── PostgreSQL (StatefulSet)
```

---

## DevOps Workflow

### 1. Infrastructure as Code — Terraform

Terraform provisions and manages all cloud infrastructure. State is stored remotely in Azure Blob Storage for team collaboration and consistency.

**What Terraform provisions:**
- Azure Resource Group
- AKS cluster (`Standard_B2s` node, system-assigned managed identity)
- ArgoCD installed into the cluster via the official Helm chart

**Remote state backend (`backend.tf`):**
```
Azure Storage Account → jerney-tfstate container → terraform.tfstate
```

**Authentication:** GitHub Actions authenticates to Azure using **OIDC (Workload Identity Federation)** — no static credentials or secrets stored.

```
Terraform/
├── main.tf        # AKS cluster resource
├── argocd.tf      # ArgoCD Helm release
├── backend.tf     # Azure remote state + provider config
├── variables.tf   # Input variables
└── outputs.tf     # Cluster outputs
```

---

### 2. Containerisation — Docker

Both application services use **multi-stage Docker builds** to produce minimal, secure production images.

**Backend (`node:20-alpine`):**
- Stage 1: install production dependencies only
- Stage 2: copy artifacts, run as non-root user (`appuser`), use `dumb-init` for correct PID 1 signal handling
- Exposes port `5000`

**Frontend (`nginx:1.27-alpine`):**
- Stage 1: `node:20-alpine` builds the static assets (`npm run build`)
- Stage 2: `nginx` serves the static files, proxies `/api/*` to the backend
- Runs as non-root user (`nginx`)
- Backend hostname injected at runtime via `envsubst` (`${BACKEND_HOST}`) — avoids hardcoding Kubernetes service names in the image

**Security practices applied:**
- Non-root users in all containers
- `dumb-init` for proper signal handling (backend)
- Minimal base images (`alpine`)
- Production-only dependencies

---

### 3. CI/CD Pipeline — GitHub Actions

The pipeline is defined in `.github/workflows/ci.yaml` and triggered manually via `workflow_dispatch` with three modes:

| Mode | What it does |
|---|---|
| `apply_all` | Terraform apply + Docker build & push + GitOps sync |
| `app_only` | Skip Terraform → Docker build & push + GitOps sync |
| `destroy` | Terraform destroy only |

**Pipeline jobs:**

```
infrastructure          build_and_push
(Terraform apply)  ──►  (Docker build & push to Docker Hub)
        │                         │
        └──────────┬──────────────┘
                   ▼
        gitops_sync_and_output
        ├── Update values.yaml with new image tag (yq)
        ├── Commit & push to Git (triggers ArgoCD sync)
        ├── Bootstrap ArgoCD root-application (kubectl apply)
        └── Print public IP + ArgoCD credentials
```

**Image tagging:** Each build is tagged with the full Git commit SHA (`${{ github.sha }}`), providing full traceability between a running container and the exact commit it was built from.

**GitOps update step:** After building, the pipeline uses `yq` to patch `values.yaml` with the new image tag and commits it back to the repo. ArgoCD detects this change and rolls out the new version automatically — no `kubectl` deployment commands needed.

---

### 4. GitOps — ArgoCD (App of Apps Pattern)

ArgoCD watches the Git repository and reconciles the cluster state to match. The **App of Apps pattern** is used so that ArgoCD manages its own child applications declaratively.

```
argo/
├── root-app.yaml              # Bootstrapped once by GitHub Actions
└── argocd-apps/
    ├── nginx-ingress.yaml     # Child app: installs ingress-nginx Helm chart
    └── jerney-stack.yaml      # Child app: deploys the application Helm chart
```

**How it works:**

1. GitHub Actions runs `kubectl apply -f argo/root-app.yaml` once after Terraform provisions the cluster
2. The `root-application` watches `argo/argocd-apps/` in the repo
3. ArgoCD creates two child applications from the manifests in that folder:
   - **`ingress-nginx`** — installs the nginx ingress controller into the `ingress-basic` namespace; Azure provisions a public LoadBalancer IP automatically
   - **`jerney-stack`** — deploys the application Helm chart (frontend, backend, postgres, Ingress resource)
4. Any push to `main` that changes Helm templates or `values.yaml` is automatically detected and synced

**Sync policy on all apps:**
```yaml
syncPolicy:
  automated:
    prune: true      # remove resources deleted from Git
    selfHeal: true   # revert any manual changes to the cluster
```

---

### 5. Kubernetes — Helm Chart

The application is packaged as a Helm chart, making it configurable and reusable.

```
argo/charts/jerney-app/
├── Chart.yaml
├── values.yaml                          # Image tags, ports, replicas, DB config
└── templates/
    ├── frontend/
    │   ├── deploy-frontend.yaml         # Deployment + Service + BACKEND_HOST env var
    │   └── ingress.yaml                 # Ingress resource (path-based routing)
    ├── backend/
    │   └── deploy-backend.yaml          # Deployment + Service + DB env vars
    └── db/
        └── db-stateful-set.yaml         # StatefulSet + headless Service + PVC (8Gi)
```

**Ingress routing:**

| Path | Backend service | Notes |
|---|---|---|
| `/*` | frontend:80 | Serves the React SPA |
| `/api/*` | backend:5000 | Strips `/api` prefix via `rewrite-target` |

**Key design decisions:**
- All resource names use `{{ .Release.Name }}` prefix — safe for multiple deployments in the same cluster
- `BACKEND_HOST` is injected as an env var from the Helm release name, avoiding hardcoded service names in the Docker image
- PostgreSQL uses a `StatefulSet` with a `PersistentVolumeClaim` to survive pod restarts
- Headless service for PostgreSQL enables stable DNS resolution from the backend

---

## End-to-End Flow: From Code Push to Live App

```
1. Developer pushes code to main
         │
2. GitHub Actions triggers
         │
3. Docker images built (multi-stage) and pushed to Docker Hub
         │
4. values.yaml updated with new image SHA, committed back to repo
         │
5. ArgoCD detects the Git change (polls every 3 minutes or via webhook)
         │
6. ArgoCD syncs jerney-stack → Kubernetes rolls out new pods
         │
7. New pods come up, old pods terminate (rolling update)
         │
8. Traffic served through nginx ingress → Azure LoadBalancer public IP
```

---

## Repository Structure

```
.
├── .github/workflows/
│   └── ci.yaml                  # Main CI/CD pipeline
├── Terraform/
│   ├── main.tf                  # AKS cluster
│   ├── argocd.tf                # ArgoCD Helm install
│   ├── backend.tf               # Remote state + providers
│   └── variables.tf
├── argo/
│   ├── root-app.yaml            # ArgoCD App of Apps bootstrap
│   ├── argocd-apps/
│   │   ├── nginx-ingress.yaml   # nginx ingress controller app
│   │   └── jerney-stack.yaml    # application stack app
│   └── charts/jerney-app/       # Application Helm chart
└── Jerney/
    ├── frontend/                # React app + Dockerfile
    └── backend/                 # Node.js API + Dockerfile
```

---

## Prerequisites

| Tool | Purpose |
|---|---|
| Terraform >= 0.14 | Infrastructure provisioning |
| Azure CLI | Authenticate and get AKS credentials |
| kubectl | Interact with the cluster |
| Helm | Local chart development/testing |

**Required GitHub Secrets:**

| Secret | Description |
|---|---|
| `AZURE_CLIENT_ID` | OIDC app registration client ID |
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription ID |
| `DOCKERHUB_USERNAME` | Docker Hub username |
| `DOCKERHUB_TOKEN` | Docker Hub access token |

---

## Deploying from Scratch

```bash
# 1. Trigger the pipeline in GitHub Actions → choose 'apply_all'
#    This will: provision AKS → install ArgoCD → build images → bootstrap GitOps

# 2. Get AKS credentials
az aks get-credentials --resource-group jerney-rg --name jerney-aks --admin

# 3. Access ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Username: admin
# Password: kubectl -n argocd get secret argocd-initial-admin-secret \
#             -o jsonpath="{.data.password}" | base64 -d

# 4. Get the public IP
kubectl get svc ingress-nginx-controller -n ingress-basic
```

## Tearing Down

Trigger the pipeline in GitHub Actions and choose `destroy`. Terraform will remove all Azure resources.
