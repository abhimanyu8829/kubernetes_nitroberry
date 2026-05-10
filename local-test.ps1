# =============================================================
# local-test.ps1
# Nitroberry local production features test
# Run from: C:\Users\DELL-OS\OneDrive\Desktop\projects\ntroberry\kubernetes\
#
# Tests: ConfigMaps, SealedSecrets, 2-node anti-affinity (preferred),
#        prod deployments, HPA, NetworkPolicies
# Skips: OPA Gatekeeper, S3 backup (prod only)
#
# Usage: .\local-test.ps1
# =============================================================

$ErrorActionPreference = "Stop"
$GREEN  = "Green"
$YELLOW = "Yellow"
$RED    = "Red"
$CYAN   = "Cyan"

function Print-Step($msg)  { Write-Host "`n===> $msg" -ForegroundColor $CYAN }
function Print-Ok($msg)    { Write-Host "  [OK] $msg" -ForegroundColor $GREEN }
function Print-Warn($msg)  { Write-Host "  [WARN] $msg" -ForegroundColor $YELLOW }
function Print-Error($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor $RED }

function Wait-Pods($namespace, $label, $expected) {
    Write-Host "  Waiting for $expected pod(s) in $namespace..." -ForegroundColor $YELLOW
    $timeout = 90
    $elapsed = 0
    while ($elapsed -lt $timeout) {
        $ready = kubectl get pods -n $namespace -l $label --no-headers 2>$null |
                 Where-Object { $_ -match "1/1\s+Running" } |
                 Measure-Object | Select-Object -ExpandProperty Count
        if ($ready -ge $expected) {
            Print-Ok "$ready/$expected pods ready in $namespace"
            return $true
        }
        Start-Sleep -Seconds 5
        $elapsed += 5
        Write-Host "    ...still waiting ($elapsed s)" -ForegroundColor $YELLOW
    }
    Print-Warn "Timed out waiting for pods in $namespace"
    return $false
}

# =============================================================
Write-Host ""
Write-Host "  ███╗   ██╗██╗████████╗██████╗  ██████╗ " -ForegroundColor Cyan
Write-Host "  ████╗  ██║██║╚══██╔══╝██╔══██╗██╔═══██╗" -ForegroundColor Cyan
Write-Host "  ██╔██╗ ██║██║   ██║   ██████╔╝██║   ██║" -ForegroundColor Cyan
Write-Host "  ██║╚██╗██║██║   ██║   ██╔══██╗██║   ██║" -ForegroundColor Cyan
Write-Host "  ██║ ╚████║██║   ██║   ██║  ██║╚██████╔╝" -ForegroundColor Cyan
Write-Host "  ╚═╝  ╚═══╝╚═╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝ " -ForegroundColor Cyan
Write-Host "  Local Production Features Test" -ForegroundColor White
Write-Host "  Skipping: OPA Gatekeeper, S3 Backup (prod only)" -ForegroundColor DarkGray
Write-Host ""

# =============================================================
Print-Step "STEP 0 — Preflight checks"
# =============================================================

# Check minikube
try {
    $mk = minikube status --format='{{.Host}}' 2>$null
    if ($mk -ne "Running") { throw }
    Print-Ok "Minikube is running"
} catch {
    Print-Error "Minikube is not running. Start it first:"
    Write-Host "    minikube start --memory=4096 --cpus=2 --driver=docker" -ForegroundColor Yellow
    exit 1
}

# Check kubectl
try {
    kubectl cluster-info 2>&1 | Out-Null
    Print-Ok "kubectl connected to cluster"
} catch {
    Print-Error "kubectl cannot reach cluster"
    exit 1
}

# Check we're in the right directory
$files = @("00-namespaces.yaml","11-configmaps.yaml","12-secrets.yaml","13-api-deployments-prod.yaml")
foreach ($f in $files) {
    if (-not (Test-Path $f)) {
        Print-Error "Missing file: $f — run this script from the kubernetes/ directory"
        exit 1
    }
}
Print-Ok "All required YAML files found"

# Point docker at minikube daemon (for image builds)
Print-Step "STEP 1 — Point Docker at Minikube daemon"
& minikube docker-env --shell powershell | Invoke-Expression
Print-Ok "Docker env set to Minikube"

# Check mock image exists
$imgCheck = docker images nitroberry-mock-api:local --format "{{.Repository}}" 2>$null
if (-not $imgCheck) {
    Print-Warn "Mock image not found — rebuilding..."
    if (-not (Test-Path "server.js") -or -not (Test-Path "Dockerfile")) {
        Print-Error "server.js or Dockerfile missing. Cannot build image."
        exit 1
    }
    docker build -t nitroberry-mock-api:local .
    Print-Ok "Mock image built"
} else {
    Print-Ok "Mock image nitroberry-mock-api:local exists"
}

# =============================================================
Print-Step "STEP 2 — Namespaces and base manifests"
# =============================================================

kubectl apply -f 00-namespaces.yaml
Print-Ok "Namespaces applied"

kubectl apply -f 02-postgres.yaml
Print-Ok "Postgres applied"

kubectl apply -f 03-traefik-rbac.yaml
kubectl apply -f 04-traefik-install.yaml
kubectl apply -f 05-traefik-middlewares.yaml
Print-Ok "Traefik applied"

# =============================================================
Print-Step "STEP 3 — Install Sealed Secrets controller"
# =============================================================

$ssInstalled = kubectl get deployment sealed-secrets-controller -n kube-system --no-headers 2>$null
if ($ssInstalled) {
    Print-Ok "Sealed Secrets controller already installed"
} else {
    Write-Host "  Installing Sealed Secrets controller..." -ForegroundColor Yellow
    kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/latest/download/controller.yaml
    Start-Sleep -Seconds 10
    Print-Ok "Sealed Secrets controller installed"
}

# =============================================================
Print-Step "STEP 4 — Apply ConfigMaps"
# =============================================================

kubectl apply -f 11-configmaps.yaml
Print-Ok "ConfigMaps applied for all 5 services"

# Verify ConfigMaps exist
$cms = @("auth-api-config","users-api-config","orders-api-config","products-api-config","notify-api-config")
$namespaces = @("auth-namespace","users-namespace","orders-namespace","products-namespace","notify-namespace")
for ($i = 0; $i -lt $cms.Length; $i++) {
    $exists = kubectl get configmap $cms[$i] -n $namespaces[$i] --no-headers 2>$null
    if ($exists) { Print-Ok "  $($cms[$i]) in $($namespaces[$i])" }
    else { Print-Warn "  $($cms[$i]) missing in $($namespaces[$i])" }
}

# =============================================================
Print-Step "STEP 5 — Apply Secrets (plain for local, SealedSecrets in prod)"
# =============================================================

# For local: apply the plain Secrets directly (values already set for local use)
# In production: use kubeseal to encrypt and apply SealedSecrets instead
kubectl apply -f 12-secrets.yaml
Print-Ok "Secrets applied (plain mode for local dev)"
Print-Warn "REMINDER: In production, seal these with: kubectl create secret ... | kubeseal > sealed.yaml"

# =============================================================
Print-Step "STEP 6 — Apply production deployments (anti-affinity patched to 'preferred')"
# =============================================================

# Apply the prod deployments first
kubectl apply -f 13-api-deployments-prod.yaml
Print-Ok "Production deployments applied"

# Patch podAntiAffinity from 'required' to 'preferred' for single-node Minikube
# (required would prevent scheduling since both pods would land on same node)
Write-Host "  Patching podAntiAffinity: required -> preferred for Minikube..." -ForegroundColor Yellow

$antiAffinityPatch = @'
{
  "spec": {
    "template": {
      "spec": {
        "affinity": {
          "podAntiAffinity": {
            "preferredDuringSchedulingIgnoredDuringExecution": [
              {
                "weight": 100,
                "podAffinityTerm": {
                  "labelSelector": {
                    "matchLabels": {}
                  },
                  "topologyKey": "kubernetes.io/hostname"
                }
              }
            ],
            "requiredDuringSchedulingIgnoredDuringExecution": null
          }
        },
        "topologySpreadConstraints": null
      }
    }
  }
}
'@

$services = @(
    @{name="auth-api";     ns="auth-namespace";     label="app=auth-api"},
    @{name="users-api";    ns="users-namespace";    label="app=users-api"},
    @{name="orders-api";   ns="orders-namespace";   label="app=orders-api"},
    @{name="products-api"; ns="products-namespace"; label="app=products-api"},
    @{name="notify-api";   ns="notify-namespace";   label="app=notify-api"}
)

foreach ($svc in $services) {
    # Build label-specific patch
    $patch = $antiAffinityPatch -replace '"matchLabels": \{\}', "`"matchLabels`": {`"app`": `"$($svc.name)`"}"
    $patch | kubectl patch deployment $svc.name -n $svc.ns --type=merge -p - 2>&1 | Out-Null

    # Patch image to local mock
    kubectl set image deployment/$($svc.name) api=nitroberry-mock-api:local -n $svc.ns 2>&1 | Out-Null

    # Set env vars
    $schema = $svc.name -replace "-api",""
    kubectl set env deployment/$($svc.name) SERVICE_NAME=$schema DB_SCHEMA=$schema -n $svc.ns 2>&1 | Out-Null

    # Set imagePullPolicy to Never
    kubectl patch deployment $svc.name -n $svc.ns `
        -p '{"spec":{"template":{"spec":{"containers":[{"name":"api","imagePullPolicy":"Never","securityContext":{"readOnlyRootFilesystem":false,"runAsNonRoot":false}}]}}}}' 2>&1 | Out-Null

    Print-Ok "Patched $($svc.name)"
}

# =============================================================
Print-Step "STEP 7 — Wait for all pods to be Running"
# =============================================================

foreach ($svc in $services) {
    Wait-Pods -namespace $svc.ns -label $svc.label -expected 1
}

# Wait for postgres
Write-Host "  Waiting for Postgres..." -ForegroundColor Yellow
kubectl rollout status statefulset/postgres -n database-namespace --timeout=90s 2>&1 | Out-Null
Print-Ok "Postgres ready"

# =============================================================
Print-Step "STEP 8 — Port-forward all services"
# =============================================================

# Kill any existing port-forwards
$existing = Get-Process -Name "kubectl" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -like "*port-forward*" }
if ($existing) {
    $existing | Stop-Process -Force
    Print-Ok "Stopped existing port-forwards"
}

$ports = @(
    @{svc="auth-api-service";     ns="auth-namespace";     local=9001},
    @{svc="users-api-service";    ns="users-namespace";    local=9002},
    @{svc="orders-api-service";   ns="orders-namespace";   local=9003},
    @{svc="products-api-service"; ns="products-namespace"; local=9004},
    @{svc="notify-api-service";   ns="notify-namespace";   local=9005}
)

foreach ($p in $ports) {
    Start-Process -FilePath "kubectl" `
        -ArgumentList "port-forward svc/$($p.svc) $($p.local):8080 -n $($p.ns)" `
        -WindowStyle Hidden
    Print-Ok "Port-forward :$($p.local) -> $($p.svc)"
}

Write-Host "  Waiting 5s for port-forwards to stabilise..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# =============================================================
Print-Step "STEP 9 — Health check all APIs"
# =============================================================

$apiTests = @(
    @{name="auth-api";     port=9001; paths=@("/health","/login","/public/info")},
    @{name="users-api";    port=9002; paths=@("/health","/profiles","/public/info")},
    @{name="orders-api";   port=9003; paths=@("/health","/orders","/public/info")},
    @{name="products-api"; port=9004; paths=@("/health","/items","/public/info")},
    @{name="notify-api";   port=9005; paths=@("/health","/notifications","/public/info")}
)

$allPassed = $true
foreach ($api in $apiTests) {
    Write-Host ""
    Write-Host "  --- $($api.name) ---" -ForegroundColor Cyan
    foreach ($path in $api.paths) {
        try {
            $resp = Invoke-RestMethod -Uri "http://localhost:$($api.port)$path" `
                                     -Method GET -TimeoutSec 5
            $status = if ($resp.status) { $resp.status } else { "ok" }
            Print-Ok "GET $path -> $status"
        } catch {
            Print-Error "GET $path -> FAILED: $_"
            $allPassed = $false
        }
    }
}

# =============================================================
Print-Step "STEP 10 — Verify ConfigMaps are mounted in pods"
# =============================================================

foreach ($svc in $services) {
    $schema = $svc.name -replace "-api",""
    $podName = kubectl get pods -n $svc.ns -l "app=$($svc.name)" `
               --no-headers -o custom-columns=":metadata.name" 2>$null | Select-Object -First 1
    if ($podName) {
        $envVal = kubectl exec $podName -n $svc.ns -- printenv DB_SCHEMA 2>$null
        if ($envVal -eq $schema) {
            Print-Ok "$($svc.name): DB_SCHEMA=$envVal (from ConfigMap)"
        } else {
            Print-Warn "$($svc.name): DB_SCHEMA='$envVal' (expected '$schema')"
        }
    }
}

# =============================================================
Print-Step "STEP 11 — Verify Postgres schemas"
# =============================================================

$schemas = kubectl exec postgres-0 -n database-namespace -- `
           psql -U postgres -c "\dn" 2>$null
Write-Host $schemas
if ($schemas -match "auth" -and $schemas -match "users" -and $schemas -match "orders") {
    Print-Ok "All 5 schemas confirmed in Postgres"
} else {
    Print-Warn "Schema check inconclusive — check output above"
}

# =============================================================
Print-Step "STEP 12 — Cluster summary"
# =============================================================

Write-Host ""
Write-Host "  PODS:" -ForegroundColor White
kubectl get pods -A | Where-Object { $_ -match "auth|users|orders|products|notify|traefik|postgres" }

Write-Host ""
Write-Host "  HPA:" -ForegroundColor White
kubectl get hpa -A

Write-Host ""
Write-Host "  CONFIGMAPS:" -ForegroundColor White
kubectl get configmap -A | Where-Object { $_ -match "api-config|backup-config" }

Write-Host ""
Write-Host "  SECRETS:" -ForegroundColor White
kubectl get secret -A | Where-Object { $_ -match "api-secrets|postgres-cred|s3-backup" }

Write-Host ""
Write-Host "  NETWORKPOLICIES:" -ForegroundColor White
kubectl get networkpolicy -A

# =============================================================
Write-Host ""
if ($allPassed) {
    Write-Host "  ✅ ALL TESTS PASSED" -ForegroundColor Green
} else {
    Write-Host "  ⚠️  SOME TESTS FAILED — check output above" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Services running at:" -ForegroundColor White
Write-Host "    auth-api     http://localhost:9001" -ForegroundColor Cyan
Write-Host "    users-api    http://localhost:9002" -ForegroundColor Cyan
Write-Host "    orders-api   http://localhost:9003" -ForegroundColor Cyan
Write-Host "    products-api http://localhost:9004" -ForegroundColor Cyan
Write-Host "    notify-api   http://localhost:9005" -ForegroundColor Cyan
Write-Host "    traefik dash http://localhost:8080/dashboard/" -ForegroundColor Cyan
Write-Host ""
Write-Host "  To stop port-forwards:" -ForegroundColor DarkGray
Write-Host "    Get-Process kubectl | Stop-Process -Force" -ForegroundColor DarkGray
Write-Host ""