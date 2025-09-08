# RKE2 Kubernetes Cluster Setup

This document provides a brief overview of the single-node RKE2 Kubernetes cluster set up as a Proof of Concept (PoC).

## Setup Overview
- Cluster was set up using Ansible. The repository will be provided later.
- Single-node RKE2 Kubernetes cluster with Rancher Management UI installed.
- Installed apps:
    - Docker registry
    - Postgres cluster (CloudNativePG)
    - Nginx Ingress

## Accessing the Cluster
- Use kubectl or the Rancher Management UI to interact with the cluster.
- From the k8s server:
    ```
    export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
    ```
    Then execute kubectl commands.
- Rancher UI: https://mgmtui.xulutions.net/
- Port 6443 (API access for kubectl) is blocked by UFW; whitelist your IP if needed:
    ```
    sudo ufw allow from <your-ip-address> to any port 6443
    ```

## Key Components

### Rancher
- Installed for cluster management.

### Cert-Manager
- Provides HTTPS certificates; certificates for Rancher and anonymizer are pre-configured:
    - anonymizer.xulutions.net (default namespace)
    - mgmtui.xulutions.net
- To create new certs, apply a Certificate manifest (via kubectl or Rancher UI). Adapt:
    - metadata.name (any name)
    - metadata.namespace (must match your app/ingress namespace)
    - spec.dnsNames

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
    name: example-com-tls
    namespace: my-namespace
spec:
    secretName: example-com-tls
    dnsNames:
        - example.com
        - www.example.com
    issuerRef:
        name: letsencrypt-production
        kind: ClusterIssuer
    usages:
        - digital signature
        - key encipherment
```

### Docker Registry
- Installed for image storage.
- No ingress yet; external pushes require an ingress or a kubectl port-forward.
- Tunnel example:
    ```
    kubectl port-forward svc/docker-registry -n registry 5000:5000
    ```
    Then access locally (from the k8s server) at:
    ```
    http://localhost:5000
    ```

### Postgres Cluster (CloudNativePG)
- Managed by CloudNativePG for scalable PostgreSQL.
- Docs: https://cloudnative-pg.io/
- Connection is currently allowed only from within the cluster (can be changed later).
- Example:
    ```
    psql -h endoregdblocal-rw.endopg.svc.cluster.local -p 5432 -d endoregDbLocal -U endoreg
    ```

## Deploying Applications
- Create Deployments under Workloads to start containers.
- Configure a Service (type: ClusterIP) to assign a DNS-routable address/IP within the cluster.
- For external access, create an Ingress:
    - Set the domain as the host.
    - Point to the Service.
    - Select HTTPS certificates (created beforehand via cert-manager).
