# Hetzner RKE2 Deployment Guide (Endo API)

## Overview
This document describes deploying Endo API to a single-node RKE2 Kubernetes cluster (Hetzner) using in-cluster containerd and Makefile helpers.

## Prerequisites
- Root or sudo access on the RKE2 host
- kubeconfig at /etc/rancher/rke2/rke2.yaml
- Podman or Docker installed (for image build); containerd present via RKE2
- DNS A record pointing to the server (for ingress + TLS)
- Active cert-manager (optional but recommended)

## 1. System & Cluster Validation
```bash
systemctl status rke2-server --no-pager
kubectl get nodes -o wide
kubectl get pods -A
ctr version
which podman || which docker
```

## 2. Clone Repository
```bash
git clone <repo-url> endo-api
cd endo-api
```

## 3. Obtain Database Credentials
If using existing CloudNativePG cluster:
```bash
kubectl get secrets -n endopg
kubectl get secret <pg-app-secret> -n endopg -o jsonpath='{.data.password}' | base64 -d
```
Build DATABASE_URL:
```
postgresql://endoreg:<password>@endoregdblocal-rw.endopg.svc.cluster.local:5432/endoregDbLocal
```

## 4. Prepare Environment Variables
```bash
export DJANGO_SECRET_KEY=$(openssl rand -base64 48)
export DATABASE_URL="postgresql://endoreg:***@endoregdblocal-rw.endopg.svc.cluster.local:5432/endoregDbLocal"
export DJANGO_ALLOWED_HOSTS="endo-api.example.com,localhost"
export DJANGO_DEBUG=false
```

## 5. Build & Load Image
```bash
make build VERSION=1.0.0
make save  VERSION=1.0.0
sudo make load VERSION=1.0.0
sudo ctr -n k8s.io images ls | grep endo-api
```

## 6. Create Namespace, Config, Secrets
```bash
kubectl create ns endo-api || true
make k8s-config
make k8s-secrets
```

## 7. Deploy
```bash
make deploy VERSION=1.0.0 HOST=endo-api.example.com
kubectl -n endo-api rollout status deploy/endo-api
```

## 8. Verify
```bash
kubectl -n endo-api get all
kubectl -n endo-api logs -l app=endo-api --tail=200
kubectl -n endo-api exec deploy/endo-api -- curl -sSf http://localhost:8118/ || echo "Not ready"
```

## 9. Updating
```bash
make build VERSION=1.0.1
make save  VERSION=1.0.1
sudo make load VERSION=1.0.1
make deploy VERSION=1.0.1 HOST=endo-api.example.com
```

## 10. Rollback
```bash
make deploy VERSION=<previous-version> HOST=endo-api.example.com
```

## 11. Ingress & TLS
If certificate not pre-created:
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: endo-api-tls
  namespace: endo-api
spec:
  secretName: endo-api-tls
  dnsNames:
    - endo-api.example.com
  issuerRef:
    name: letsencrypt-production
    kind: ClusterIssuer
```
Apply, then redeploy ingress (make deploy).

## 12. Troubleshooting
| Symptom | Check |
|---------|-------|
| Pod CrashLoop | kubectl -n endo-api logs pod/... |
| DB errors | DATABASE_URL value & network (svc DNS) |
| 404 / TLS | Ingress host & certificate secret |
| Image not found | Confirm `ctr -n k8s.io images ls` contains tag |

## 13. Security Notes
- All secrets delivered via Kubernetes Secret (k8s-secrets target)
- No secrets baked in image (see container/Dockerfile.prod)
- Rotate DJANGO_SECRET_KEY on security events

## 14. References
- Makefile deployment: (see repository root)
- Deployment template: k8s/deployment.tmpl.yaml
- RKE2 cluster overview: docs/rke2_docs.md
- Container architecture: container/README.md

*Status: Initial Hetzner deployment doc created.*

## 15. Live Execution Runbook (SSH Session Documentation)

This section captures the actual steps performed on the Hetzner RKE2 host (root@213.133.99.8). Replace placeholders with real outputs as you proceed.

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
Notes:
# System
root
Linux k8s-server 6.8.0-79-generic #79-Ubuntu SMP PREEMPT_DYNAMIC Tue Aug 12 14:42:46 UTC 2025 x86_64 x86_64 x86_64 GNU/Linux
# Time
Tue Sep  9 09:23:59 AM UTC 2025
# Disk / Memory
Filesystem      Size  Used Avail Use% Mounted on
/dev/md2        436G   65G  350G  16% /
/dev/md1        989M  196M  743M  21% /boot
               total        used        free      shared  buff/cache   available
Mem:            62Gi       4.9Gi       714Mi        83Mi        57Gi        57Gi
Swap:             0B          0B          0B
# RKE2 service
active
● rke2-server.service - Rancher Kubernetes Engine v2 (server)
     Loaded: loaded (/usr/local/lib/systemd/system/rke2-server.service; enabled; preset: enabled)
     Active: active (running) since Tue 2025-09-02 19:08:02 CEST; 6 days ago
       Docs: https://github.com/rancher/rke2#readme
   Main PID: 231900 (rke2)
      Tasks: 553
     Memory: 11.9G (peak: 11.9G)
        CPU: 3d 6h 28min 44.012s
     CGroup: /system.slice/rke2-server.service
             ├─ 231900 "/usr/local/bin/rke2 server"
             ├─ 231922 containerd -c /var/lib/rancher/rke2/agent/etc/containerd/config.toml
             ├─ 232033 kubelet --volume-plugin-dir=/var/lib/kubelet/volumeplugins --file-check-frequency=5s --sync-frequency=30s --cloud-provider=external --config-dir=/var/lib/rancher/rke2/agent/etc/kubelet.conf.d --containerd=/run/k3s/containerd/containerd.sock --hostname-override=k8s-server --kubeconfig=/var/lib/rancher/rke2/agent/kubelet.kubeconfig --node-ip=213.133.99.8,2a01:4f8:a0:93ba::2 --node-labels= --read-only-port=0
             ├─ 232091 /var/lib/rancher/rke2/data/v1.33.4-rke2r1-daf85d39fe51/bin/containerd-shim-runc-v2 -namespace k8s.io -id f1a69c52190869708284119e16d01d382c544003cf4599d0c1c00d3cdc6caae9 -address /run/k3s/containerd/containerd.sock
             ├─ 232098 /var/lib/rancher/rke2/data/v1.33.4-rke2r1-daf85d39fe51/bin/containerd-shim-runc-v2 -namespace k8s.io -id 583fa2ad1dad6dc0e243cad5263de3411f866027903f9a261e6123547f112156 -address /run/k3s/containerd/containerd.sock
             ├─ 232275 /var/lib/rancher/rke2/data/v1.33.4-rke2r1-daf85d39fe51/bin/containerd-shim-runc-v2 -namespace k8s.io -id 0b9add2db571870c6aa1e563db79ac10b1df474de8eea28badf99ebd7e56e4d3 -address /run/k3s/containerd/containerd.sock
             ├─ 232363 /var/lib/rancher/rke2/data/v1.33.4-rke2r1-daf85d39fe51/bin/containerd-shim-runc-v2 -namespace k8s.io -id ce6c27cb6ab2ec3b83a29640e0e24aff9b42262ff1ae38e509e6638dd9c384b9 -address /run/k3s/containerd/containerd.sock
             ├─ 232383 /var/lib/rancher/rke2/data/v1.33.4-rke2r1-daf85d39fe51/bin/containerd-shim-runc-v2 -namespace k8s.io -id f9003c5298b4ce20a393d9aa3b49054b470c4ca45e8ce7396cd152d47ae0f85d -address /run/k3s/containerd/containerd.sock
             ├─ 232539 /var/lib/rancher/rke2/data/v1.33.4-rke2r1-daf85d39fe51/bin/containerd-shim-runc-v2 -namespace k8s.io -id 668d02f7345e1b23227829683ca0190aa4e4ef8eafb3f094cbf121d9e19bf000 -address /run/k3s/containerd/containerd.sock
             ├─ 233354 /var/lib/rancher/rke2/data/v1.33.4-rke2r1-daf85d39fe51/bin/containerd-shim-runc-v2 -namespace k8s.io -id ee9a855df322a5703d6a8f5535d38ba127983ee41f15245ad915db2aeca7d0f5 -address /run/k3s/containerd/containerd.sock
             ├─ 237080 /var/lib/rancher/rke2/data/v1.33.4-rke2r1-daf85d39fe51/bin/containerd-shim-runc-v2 -namespace k8s.io -id 775b7d3d06a23bdfaa124be56bde9301da1c3863ac3b57517457f8e4fddb145a -address /run/k3s/containerd/containerd.sock
# Kubernetes nodes
E0909 11:23:59.642464 1611684 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
E0909 11:23:59.642795 1611684 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
E0909 11:23:59.644073 1611684 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
E0909 11:23:59.644245 1611684 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
E0909 11:23:59.645515 1611684 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
The connection to the server localhost:8080 was refused - did you specify the right host or port?
# Core namespaces pods (short)
E0909 11:23:59.689811 1611697 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
E0909 11:23:59.690044 1611697 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
E0909 11:23:59.691334 1611697 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
E0909 11:23:59.691508 1611697 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
E0909 11:23:59.692872 1611697 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
The connection to the server localhost:8080 was refused - did you specify the right host or port?
# Containerd version
Client:
  Version:  1.7.27
  Revision: 05044ec0a9a75232cad458027ca83437aae3f4da
  Go version: go1.23.7

Server:
  Version:  1.7.27
  Revision: 05044ec0a9a75232cad458027ca83437aae3f4da
  UUID: 764a5139-3a37-4102-9b8a-a66e64f3451f
# Build tooling
/usr/bin/docker
# Ingress controllers
E0909 11:23:59.768651 1611719 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
E0909 11:23:59.768971 1611719 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
E0909 11:23:59.770306 1611719 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
E0909 11:23:59.770672 1611719 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
E0909 11:23:59.771994 1611719 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
The connection to the server localhost:8080 was refused - did you specify the right host or port?
# Existing certs
E0909 11:23:59.814275 1611733 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
E0909 11:23:59.814630 1611733 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
E0909 11:23:59.816042 1611733 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
E0909 11:23:59.816375 1611733 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
E0909 11:23:59.817736 1611733 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
The connection to the server localhost:8080 was refused - did you specify the right host or port?
# PG namespace resources
E0909 11:23:59.856412 1611746 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
E0909 11:23:59.856704 1611746 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
E0909 11:23:59.857966 1611746 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
E0909 11:23:59.858189 1611746 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
E0909 11:23:59.859455 1611746 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
E0909 11:23:59.859621 1611746 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
E0909 11:23:59.860943 1611746 memcache.go:265] "Unhandled Error" err="couldn't get current server API group list: Get \"http://localhost:8080/api?timeout=32s\": dial tcp 127.0.0.1:8080: connect: connection refused"
The connection to the server localhost:8080 was refused - did you specify the right host or port?
root@k8s-server ~ # 

```

#### Manual Diagnostics & Fixes:
```bash
# 1. Confirm kubeconfig path
ls -l /etc/rancher/rke2/rke2.yaml

# 2. Export it (fresh shell might have lost export)
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml

RKE2_BIN_DIR=$(ls -d /var/lib/rancher/rke2/data/*/bin | head -1)
ln -s ${RKE2_BIN_DIR}/crictl /usr/local/bin/crictl

cat >/etc/crictl.yaml <<'EOF'
runtime-endpoint: unix:///run/k3s/containerd/containerd.sock
image-endpoint: unix:///run/k3s/containerd/containerd.sock
timeout: 10
debug: false
EOF

# Test
crictl info | grep -E 'runtimeType|runtimeEndpoint|imageEndpoint'
crictl ps -a | head
crictl images | head

# 3. Basic kubeconfig sanity
stat $KUBECONFIG
head -20 $KUBECONFIG | sed -E 's/(token: ).*/\1***REDACTED***/'

# 4. Contexts
kubectl config get-contexts
kubectl config current-context || true

# 5. Cluster info (expect URLs with :6443)
kubectl cluster-info || echo "cluster-info failed"

# 6. If still 'localhost:8080', show server line
grep -n '^ *server:' $KUBECONFIG

# 7. Direct HTTPS probe to API (bypasses kubectl)
API_URL=$(grep '^ *server:' $KUBECONFIG | awk '{print $2}')
echo "API_URL=$API_URL"
curl -sk $API_URL/version || echo "curl version probe failed"

# 8. Check rke2 server logs for API errors
journalctl -u rke2-server -n 200 --no-pager | grep -Ei 'apiserver|error|fail' | tail -50

# 9. List static pod manifests (kube-apiserver etc.)
ls -1 /var/lib/rancher/rke2/agent/pod-manifests

# 10. Low-level container runtime pod list
CRICTL=$(command -v crictl || ls /var/lib/rancher/rke2/data/*/bin/crictl 2>/dev/null | head -1)
echo "CRICTL=$CRICTL"
$CRICTL ps -a | head -30
```

```bash
root@k8s-server ~ # stat $KUBECONFIG
  File: /etc/rancher/rke2/rke2.yaml
  Size: 2969            Blocks: 8          IO Block: 4096   regular file
Device: 9,2     Inode: 22939604    Links: 1
Access: (0644/-rw-r--r--)  Uid: (    0/    root)   Gid: (    0/    root)
Access: 2025-09-03 23:11:59.626036252 +0200
Modify: 2025-09-02 19:07:40.942933376 +0200
Change: 2025-09-02 19:07:40.942933376 +0200
 Birth: 2025-09-02 19:07:40.942933376 +0200


root@k8s-server ~ # head -20 $KUBECONFIG | sed -E 's/(token: ).*/\1***REDACTED***/'
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: XXXX
    server: https://127.0.0.1:6443
  name: default
contexts:
- context:
    cluster: default
    user: default
  name: default
current-context: default
kind: Config
preferences: {}
users:
- name: default
  user:
    client-certificate-data: XXX
    client-key-data: XXX

root@k8s-server ~ # kubectl config get-contexts
kubectl config current-context || true
CURRENT   NAME      CLUSTER   AUTHINFO   NAMESPACE
*         default   default   default    
default

root@k8s-server ~ # kubectl cluster-info || echo "cluster-info failed"
Kubernetes control plane is running at https://127.0.0.1:6443
CoreDNS is running at https://127.0.0.1:6443/api/v1/namespaces/kube-system/services/rke2-coredns-rke2-coredns:udp-53/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.

root@k8s-server ~ # grep -n '^ *server:' $KUBECONFIG
5:    server: https://127.0.0.1:6443

root@k8s-server ~ # API_URL=$(grep '^ *server:' $KUBECONFIG | awk '{print $2}')
echo "API_URL=$API_URL"
curl -sk $API_URL/version || echo "curl version probe failed"
API_URL=https://127.0.0.1:6443
{
  "kind": "Status",
  "apiVersion": "v1",
  "metadata": {},
  "status": "Failure",
  "message": "Unauthorized",
  "reason": "Unauthorized",
  "code": 401
}

Sep 09 11:30:39 k8s-server rke2[231900]: time="2025-09-09T11:30:39+02:00" level=error msg="Failed to process config: failed to process /var/lib/rancher/rke2/server/manifests/clusterissuer.yml: yaml: invalid map key: map[interface {}]interface {}{\"letsencrypt_email\":interface {}(nil)}"
Sep 09 11:30:54 k8s-server rke2[231900]: time="2025-09-09T11:30:54+02:00" level=error msg="Failed to process config: failed to process /var/lib/rancher/rke2/server/manifests/clusterissuer.yml: yaml: invalid map key: map[interface {}]interface {}{\"letsencrypt_email\":interface {}(nil)}"
Sep 09 11:31:09 k8s-server rke2[231900]: time="2025-09-09T11:31:09+02:00" level=error msg="Failed to process config: failed to process /var/lib/rancher/rke2/server/manifests/clusterissuer.yml: yaml: invalid map key: map[interface {}]interface {}{\"letsencrypt_email\":interface {}(nil)}"
Sep 09 11:31:24 k8s-server rke2[231900]: time="2025-09-09T11:31:24+02:00" level=error msg="Failed to process config: failed to process /var/lib/rancher/rke2/server/manifests/clusterissuer.yml: yaml: invalid map key: map[interface {}]interface {}{\"letsencrypt_email\":interface {}(nil)}"

root@k8s-server ~ # ls -1 /var/lib/rancher/rke2/agent/pod-manifests
cloud-controller-manager.yaml
etcd.yaml
kube-apiserver.yaml
kube-controller-manager.yaml
kube-proxy.yaml
kube-scheduler.yaml


root@k8s-server ~ # CRICTL=$(command -v crictl || ls /var/lib/rancher/rke2/data/*/bin/crictl 2>/dev/null | head -1)
echo "CRICTL=$CRICTL"
$CRICTL ps -a | head -30
CRICTL=/var/lib/rancher/rke2/data/v1.33.4-rke2r1-daf85d39fe51/bin/crictl
WARN[0000] Config "/etc/crictl.yaml" does not exist, trying next: "/var/lib/rancher/rke2/data/v1.33.4-rke2r1-daf85d39fe51/bin/crictl.yaml" 
WARN[0000] runtime connect using default endpoints: [unix:///run/containerd/containerd.sock unix:///run/crio/crio.sock unix:///var/run/cri-dockerd.sock]. As the default settings are now deprecated, you should set the endpoint instead. 
ERRO[0000] validate service connection: validate CRI v1 runtime API for endpoint "unix:///run/containerd/containerd.sock": rpc error: code = Unimplemented desc = unknown service runtime.v1.RuntimeService 
ERRO[0000] validate service connection: validate CRI v1 runtime API for endpoint "unix:///run/crio/crio.sock": rpc error: code = Unavailable desc = connection error: desc = "transport: Error while dialing: dial unix /run/crio/crio.sock: connect: no such file or directory" 
ERRO[0000] validate service connection: validate CRI v1 runtime API for endpoint "unix:///var/run/cri-dockerd.sock": rpc error: code = Unavailable desc = connection error: desc = "transport: Error while dialing: dial unix /var/run/cri-dockerd.sock: connect: no such file or directory" 
FATA[0000] validate service connection: validate CRI v1 runtime API for endpoint "unix:///var/run/cri-dockerd.sock": rpc error: code = Unavailable desc = connection error: desc = "transport: Error while dialing: dial unix /var/run/cri-dockerd.sock: connect: no such file or directory" 

root@k8s-server ~ # crictl info | grep -E 'runtimeType|runtimeEndpoint|imageEndpoint'
          "runtimeType": "io.containerd.runc.v2",
          "runtimeType": "io.containerd.runhcs.v1",

root@k8s-server ~ # crictl ps -a | head
CONTAINER           IMAGE               CREATED             STATE               NAME                             ATTEMPT             POD ID              POD                                                     NAMESPACE
e62ca478b76b3       887cb54b0ed2c       4 minutes ago       Running             kube-proxy                       0                   5fa0c6ed40a77       kube-proxy-k8s-server                                   kube-system
9c6e680829532       0d42704aaa7ba       10 hours ago        Exited              rke2-machineconfig-cleanup-pod   0                   791313bce1909       rke2-machineconfig-cleanup-cronjob-29289605-79mnl       fleet-default
b3f46d435bc78       0d42704aaa7ba       34 hours ago        Exited              rke2-machineconfig-cleanup-pod   0                   9ffdcb7e6ccee       rke2-machineconfig-cleanup-cronjob-29288165-vshjd       fleet-default
bb24c6c489e27       0d42704aaa7ba       2 days ago          Exited              rke2-machineconfig-cleanup-pod   0                   cffeaae6c62c5       rke2-machineconfig-cleanup-cronjob-29286725-2nksz       fleet-default
3c46041e54a4b       802541663949f       4 days ago          Running             ubuntu                           0                   d032285a8b335       ubuntu-7c74489fc5-rdvxj                                 registry
844eb4417cf2b       ad5708199ec7d       4 days ago          Running             nginx                            0                   d518d1f0d7337       nginx-76c7d65977-s2xvp                                  default
77f9f5b4b5e63       ad5708199ec7d       4 days ago          Running             nginx                            0                   b8589ea3f90aa       nginx-76c7d65977-4db5w                                  default
edd3a0f61368e       ad5708199ec7d       4 days ago          Running             nginx                            0                   6ffaca830919f       nginx-76c7d65977-cqs2q                                  default
779b86ab4beaa       ad5708199ec7d       4 days ago          Running             nginx                            0                   f18430d0f7354       nginx-76c7d65977-hxdj8                                  default
root@k8s-server ~ # crictl images | head
IMAGE                                                        TAG                                                   IMAGE ID            SIZE
docker.io/library/busybox                                    latest                                                0ed463b26daee       2.22MB
docker.io/library/nginx                                      latest                                                ad5708199ec7d       72.3MB
docker.io/library/registry                                   3                                                     3c52eedeec804       18.5MB
docker.io/library/ubuntu                                     latest                                                802541663949f       29.7MB
docker.io/rancher/fleet-agent                                v0.13.1                                               c09137670c121       29.2MB
docker.io/rancher/fleet                                      v0.13.1                                               3364d8f9ec6aa       115MB
docker.io/rancher/hardened-calico                            v3.30.2-build20250731                                 fb58c2c03555d       227MB
docker.io/rancher/hardened-cluster-autoscaler                v1.10.2-build20250611                                 cb9099d466cf0       14.1MB
docker.io/rancher/hardened-coredns                           v1.12.3-build20250806                                 30ccd42fb8596       28.9MB


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
export APP_VERSION=1.0.0
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
