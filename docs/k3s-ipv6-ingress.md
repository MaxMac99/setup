# K3s Dual-Stack IPv6 Ingress Setup

This document describes the dual-stack (IPv4 + IPv6) ingress configuration for the K3s cluster with external access via ionos.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         Internet                                 │
│                  (IPv4 + IPv6 Traffic)                          │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
                  ┌──────────────┐
                  │    ionos     │  Public IPv4 + IPv6
                  │  (K3s agent) │  Traefik External
                  └──────┬───────┘
                         │
                   WireGuard Tunnel
                (192.168.178.0/24)
               (fda8:a1db:5685::/64)
                         │
          ┌──────────────┴──────────────┐
          │                             │
    ┌─────▼─────┐   ┌──────────┐   ┌──────────┐
    │ k3s-node1 │   │k3s-node2 │   │k3s-node3 │
    │  (server) │   │ (server) │   │ (server) │
    └─────┬─────┘   └────┬─────┘   └────┬─────┘
          │              │              │
          └──────────────┴──────────────┘
                         │
                  MetalLB LoadBalancer
                  (192.168.178.10-20)
                         │
                  Traefik Internal
                         │
          ┌──────────────┼──────────────┐
          │              │              │
     ┌────▼────┐   ┌────▼────┐   ┌────▼────┐
     │ Grafana │   │Paperless│   │  Other  │
     │         │   │   NGX   │   │   Apps  │
     └─────────┘   └─────────┘   └─────────┘
```

## Components

### 1. K3s Cluster (Home)

**Nodes:**
- `k3s-node1`: 192.168.178.5 / fda8:a1db:5685::5 (server, first node)
- `k3s-node2`: 192.168.178.6 / fda8:a1db:5685::6 (server)
- `k3s-node3`: 192.168.178.7 / fda8:a1db:5685::7 (server)

**Configuration:**
- Dual-stack enabled (IPv4 + IPv6)
- Pod CIDR: 10.42.0.0/16, fd01::/48
- Service CIDR: 10.43.0.0/16, fd02::/112

### 2. ionos (Cloud Gateway)

**Location:** Cloud (IONOS VPS)

**IPs:**
- Private (WireGuard): 192.168.178.201 / fda8:a1db:5685::201
- Public: (Your IONOS public IPv4 and IPv6)

**Role:** K3s agent node with `node-role.kubernetes.io/edge=true` label

**Purpose:** External ingress point for internet traffic

### 3. MetalLB

**IP Pool:**
- IPv4: 192.168.178.10-192.168.178.20
- IPv6: fda8:a1db:5685::10-fda8:a1db:5685::20

**Purpose:** Provides LoadBalancer IPs for internal Traefik

### 4. Traefik (Dual Instance)

#### Internal Traefik (K3s Built-in)
- **Namespace:** kube-system
- **Type:** LoadBalancer (via MetalLB)
- **IP:** 192.168.178.10 (assigned by MetalLB)
- **Purpose:** Handles local network traffic

#### External Traefik (ionos)
- **Namespace:** traefik-external
- **Type:** DaemonSet (hostNetwork)
- **Node:** Runs only on ionos (edge node)
- **Purpose:** Handles internet traffic on public IPs

## Traffic Flow

### Local Access (at home)

```
Device (192.168.178.x)
    ↓
FritzBox DNS → grafana.yourdomain.local → 192.168.178.10
    ↓
Traefik Internal (LoadBalancer)
    ↓
Grafana Pod
```

### External Access (away from home)

```
Device (Internet)
    ↓
Public DNS → grafana.yourdomain.com → ionos_public_ip
    ↓
ionos: Traefik External (hostNetwork on ports 80/443)
    ↓
WireGuard tunnel
    ↓
Grafana Pod (via K8s Service)
```

## DNS Configuration (Split-Horizon)

### Option 1: Different Subdomains

**Local (FritzBox DNS):**
- `grafana.home` → 192.168.178.10
- `paperless.home` → 192.168.178.10

**Public DNS:**
- `grafana.yourdomain.com` → ionos IPv4
- `grafana.yourdomain.com` → ionos IPv6 (AAAA record)

### Option 2: Same Domain, Different Resolution

**Local DNS Override (FritzBox):**
- `grafana.yourdomain.com` → 192.168.178.10

**Public DNS:**
- `grafana.yourdomain.com` → ionos IPs

**Setup in FritzBox:**
1. Go to Network → Network Settings → DNS Rebind Protection
2. Add custom DNS entries for your domain
3. Point to 192.168.178.10

## Deployment Steps

### 1. Rebuild K3s Nodes

```bash
# On maxdata (host machine)
cd ~/Git/setup
sudo nixos-rebuild switch --flake .#k3s-node1
sudo nixos-rebuild switch --flake .#k3s-node2
sudo nixos-rebuild switch --flake .#k3s-node3
```

### 2. Deploy ionos as Agent

```bash
# Deploy ionos configuration
nixos-rebuild switch --flake .#ionos --target-host max@ionos_ip
```

**Verify ionos joined:**
```bash
kubectl get nodes
# Should show: k3s-node1, k3s-node2, k3s-node3, ionos
```

### 3. Deploy Infrastructure via Pulumi

```bash
cd ~/Git/setup/pulumi/k8s
pulumi up
```

This deploys:
- MetalLB with IP pools
- Internal Traefik configuration (LoadBalancer)
- External Traefik on ionos (DaemonSet)

### 4. Verify Traefik Instances

```bash
# Check internal Traefik
kubectl get svc -n kube-system traefik
# Should show LoadBalancer IP (192.168.178.10)

# Check external Traefik
kubectl get pods -n traefik-external -o wide
# Should show pod running on ionos node
```

### 5. Configure DNS

**For testing without DNS:**
```bash
# Local access
curl -H "Host: grafana.yourdomain.com" http://192.168.178.10

# External access
curl -H "Host: grafana.yourdomain.com" http://ionos_public_ip
```

## Example Application Deployment

Here's how to deploy an app that works with both ingress points:

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: apps
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: grafana
  namespace: apps
spec:
  replicas: 1
  selector:
    matchLabels:
      app: grafana
  template:
    metadata:
      labels:
        app: grafana
    spec:
      containers:
      - name: grafana
        image: grafana/grafana:latest
        ports:
        - containerPort: 3000
---
apiVersion: v1
kind: Service
metadata:
  name: grafana
  namespace: apps
spec:
  selector:
    app: grafana
  ports:
  - port: 80
    targetPort: 3000
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  namespace: apps
  annotations:
    traefik.ingress.kubernetes.io/router.entrypoints: web,websecure
spec:
  rules:
  - host: grafana.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana
            port:
              number: 80
```

**Both Traefik instances will automatically discover this Ingress!**

## Security Considerations

1. **Firewall on ionos:**
   - Only ports 22 (SSH), 80 (HTTP), 443 (HTTPS), 56527 (WireGuard) are open
   - All other traffic blocked

2. **WireGuard Encryption:**
   - All traffic between ionos and home is encrypted
   - Preshared keys for additional security

3. **Private IPs:**
   - K3s nodes use private IPs (192.168.178.x, fda8:a1db:5685::x)
   - Not directly routable from internet
   - Only accessible via WireGuard tunnel

4. **SSL/TLS:**
   - Use cert-manager to automatically provision Let's Encrypt certificates
   - Traefik handles TLS termination

## Troubleshooting

### ionos not joining cluster

```bash
# On ionos, check K3s logs
journalctl -u k3s -f

# Check WireGuard connectivity
ping 192.168.178.5  # Should reach k3s-node1
```

### External Traefik not starting

```bash
# Check if ionos node has correct label
kubectl get node ionos --show-labels
# Should have: node-role.kubernetes.io/edge=true

# Check pod status
kubectl get pods -n traefik-external -o wide
kubectl logs -n traefik-external <pod-name>
```

### Split traffic not working

1. Verify DNS resolution:
   ```bash
   # From local network
   nslookup grafana.yourdomain.com
   # Should return 192.168.178.10

   # From internet
   nslookup grafana.yourdomain.com
   # Should return ionos public IP
   ```

2. Check Ingress is created:
   ```bash
   kubectl get ingress -A
   ```

3. Test direct access:
   ```bash
   # Local
   curl -v http://192.168.178.10 -H "Host: grafana.yourdomain.com"

   # External
   curl -v http://ionos_ip -H "Host: grafana.yourdomain.com"
   ```

## Next Steps

1. **Set up cert-manager** for automatic SSL certificates
2. **Configure external DNS** to point to ionos public IPs
3. **Set up local DNS overrides** in FritzBox
4. **Deploy applications** (Grafana, Paperless-ngx, etc.)
5. **Configure monitoring** for both Traefik instances

## Notes

- MetalLB IP pool (192.168.178.10-20) is reserved for LoadBalancer services
- IPv6 ranges use ULA (fd00::/8) for privacy - not globally routable
- ionos acts as IPv4 gateway (DS-Lite workaround)
- Both IPv4 and IPv6 traffic flow through ionos for external access
