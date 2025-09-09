# Hetzner RKE2 Deployment Guide (Endo API)

### Phase 0: Session Prep
Record session (optional but recommended):
```bash
script -a hetzner_deploy_session_$(date +%Y%m%d_%H%M%S).log
set -euo pipefail
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

# Install Nix
sh <(curl -L https://nixos.org/nix/install) --daemon

# Install DevEnv
nix-env --install --attr devenv -f https://github.com/NixOS/nixpkgs/tarball/nixpkgs-unstable
```

### Phase 1: Baseline System & Cluster Audit
```bash
echo "# System" ; whoami ; uname -a
echo "# Time" ; date -u
echo "# Disk / Memory" ; df -h | grep -E '^/|Filesystem' ; free -h
echo "# RKE2 service" ; systemctl is-active rke2-server ; systemctl --no-pager status rke2-server | head -20
echo "# Kubernetes nodes"; kubectl get nodes -o wide
echo "# Core namespaces pods (short)"; kubectl get pods -A --field-selector=status.phase!=Succeeded | head -50
echo "# Containerd version"; ctr version || true
echo "# Build tooling"; which podman || which docker || echo "No docker/podman installed"
echo "# Ingress controllers"; kubectl get pods -A | grep -i ingress || true
echo "# Existing certs"; kubectl get certificate -A || true
echo "# PG namespace resources"; kubectl get pods,svc,secrets -n endopg | head -50 || true
```
Document any anomalies:
```

```

#### Manual Diagnostics & Fixes:
```bash

```

### Phase 2: Repository Acquisition
```bash
cd /root
test -d endo-api || git clone https://github.com/wg-lux/endo-api endo-api
cd endo-api
git checkout container
git fetch --all
git submodule init
git submodule update --remote --recursive
git status
```
Record commit:
```bash
git log -1 --oneline
```

### Phase 3: Version & Variables
Choose a version tag (do not overwrite an existing pushed tag):
```bash
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export APP_VERSION=1.0.1
export HOSTNAME_PUBLIC="endo-api.xulutions.net"   # adjust
export DJANGO_SECRET_KEY=$(openssl rand -base64 48)
export POSTGRES_APP_USER="endoreg"
PG_SECRET_NAME=endoregdblocal-user
kubectl get secret "$PG_SECRET_NAME" -n endopg -o jsonpath='{.data.password}' | base64 -d > /tmp/pgpwd.txt
export DB_PASSWORD=$(cat /tmp/pgpwd.txt)
export DATABASE_URL="postgresql://${POSTGRES_APP_USER}:${DB_PASSWORD}@endoregdblocal-rw.endopg.svc.cluster.local:5432/endoregDbLocal"
export DJANGO_ALLOWED_HOSTS="${HOSTNAME_PUBLIC},localhost"
export DJANGO_DEBUG=false
printenv | grep -E 'APP_VERSION|DJANGO_|DATABASE_URL'

cat > .deploy.env <<EOF
KUBECONFIG=${KUBECONFIG}
APP_VERSION=${APP_VERSION}
DJANGO_SECRET_KEY=${DJANGO_SECRET_KEY}
DATABASE_URL=${DATABASE_URL}
DJANGO_ALLOWED_HOSTS=${DJANGO_ALLOWED_HOSTS}
DJANGO_DEBUG=${DJANGO_DEBUG}
HOSTNAME_PUBLIC=${HOSTNAME_PUBLIC}
EOF
```

### Phase 4: Image Build & Load (Local Build → RKE2 containerd)
```bash
devenv shell
make build VERSION=${APP_VERSION}
make save  VERSION=${APP_VERSION}
sudo make load VERSION=${APP_VERSION}
sudo ctr -n k8s.io images ls | grep endo-api | grep ${APP_VERSION}
```
If image missing, check:
```bash
grep build -n Makefile
```

### Phase 5: Namespace, ConfigMap, Secrets
```bash
kubectl create ns endo-api || true
# Export env (ensure current shell has them)
set -a; source .deploy.env; set +a
make k8s-config
make k8s-secrets
kubectl get configmap,secret -n endo-api
```
Verify secret keys:
```bash

kubectl -n endo-api get secret endo-api-secrets 
kubectl -n endo-api get secret endo-api-secrets -o jsonpath='{.data.DATABASE_URL}' | base64 -d; echo kubectl -n endo-api get secret endo-api-secrets -o jsonpath='{.data.DJANGO_SECRET_KEY}' | base64 -d | head -c 16; echo
```

### Phase 6: Deployment & Rollout
```bash
make deploy VERSION=${APP_VERSION} HOST=${HOSTNAME_PUBLIC}
kubectl -n endo-api rollout status deploy/endo-api --timeout=120s
kubectl -n endo-api get deploy,rs,pods,svc,ingress
```
Pod logs (initial tail):
```bash
kubectl -n endo-api logs -l app=endo-api --tail=200
```

Restart Rollout
```bash
kubectl -n endo-api rollout restart deploy/endo-api

```

### Phase 7: In-Pod Health Probe
```bash
kubectl -n endo-api exec deploy/endo-api -- curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8118/ || echo "probe-failed"
```

### Phase 8: Ingress & TLS Validation
(If cert-manager used and ingress created)
```bash
kubectl -n endo-api get ingress
kubectl -n endo-api describe ingress
kubectl -n endo-api get secret endo-api-tls || echo "No TLS secret yet"
# External test (run from a machine with DNS resolution)
curl -vk https://${HOSTNAME_PUBLIC}/ 2>&1 | grep -Ei 'certificate|HTTP/'
```

### Phase 9: Post-Deployment Checklist
| Check | Command | Result |
|-------|---------|--------|
| Deployment Available | kubectl -n endo-api get deploy endo-api -o jsonpath='{.status.availableReplicas}' |  |
| Container Running | kubectl -n endo-api get pods -l app=endo-api |  |
| Service Endpoints | kubectl -n endo-api get endpoints |  |
| App HTTP 200 (internal) | curl inside pod |  |
| Image Tag Matches | ctr images ls |  |

### Phase 10: Update Test (Example 1.0.1)
```bash
export APP_VERSION=1.0.1
make build VERSION=${APP_VERSION}
make save  VERSION=${APP_VERSION}
sudo make load VERSION=${APP_VERSION}
make deploy VERSION=${APP_VERSION} HOST=${HOSTNAME_PUBLIC}
kubectl -n endo-api rollout status deploy/endo-api
```

### Phase 11: Rollback Example
```bash
PREV=1.0.0
make deploy VERSION=${PREV} HOST=${HOSTNAME_PUBLIC}
kubectl -n endo-api rollout status deploy/endo-api
```

### Phase 12: Quick Triage Commands
```bash
# Pod events
kubectl -n endo-api describe pod $(kubectl -n endo-api get pods -l app=endo-api -o name | head -1) | sed -n '/Events:/,$p'
# CrashLoop last 50 log lines
kubectl -n endo-api logs -l app=endo-api --tail=50
# DNS resolution inside pod
kubectl -n endo-api exec deploy/endo-api -- getent hosts endoregdblocal-rw.endopg.svc.cluster.local
```

### Phase 13: Cleanup (If Needed)
```bash
kubectl delete ns endo-api
sudo ctr -n k8s.io images rm $(sudo ctr -n k8s.io images ls | grep endo-api | awk '{print $1}') || true
```

### Phase 14: Artifacts Collected
List:
```
- Session log file(s)
- .deploy.env
- Image tags used
- Rollout history (kubectl -n endo-api rollout history deploy/endo-api)
```

### Notes / Deviations
```
