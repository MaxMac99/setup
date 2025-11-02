// Traefik Ingress Controller Configuration
// NOTE: K3s ships with Traefik by default - you must disable it during K3s installation:
// curl -sfL https://get.k3s.io | sh -s - --disable traefik

import * as k8s from "@pulumi/kubernetes";
import * as pulumi from "@pulumi/pulumi";
import { authentikOutpostService } from "./authentik-outpost";
import { authentikNamespace } from "./authentik";

// Create namespace for Traefik
const traefikNamespace = new k8s.core.v1.Namespace("traefik", {
  metadata: {
    name: "traefik",
  },
});

// Install Traefik using Helm
const traefik = new k8s.helm.v3.Chart(
  "traefik",
  {
    chart: "traefik",
    namespace: traefikNamespace.metadata.name,
    fetchOpts: {
      repo: "https://traefik.github.io/charts",
    },
    values: {
      // Configure Traefik to use LoadBalancer service
      service: {
        type: "LoadBalancer",
        // Request specific IP from MetalLB pool (optional, MetalLB will auto-assign if not specified)
        // loadBalancerIP: "192.168.178.10",
      },
      // Enable dual-stack
      ipFamilyPolicy: "PreferDualStack",
      // Logs configuration - JSON format for Loki/Grafana
      logs: {
        general: {
          level: "INFO",
          format: "json",
        },
        access: {
          enabled: true,
          format: "json",
          fields: {
            defaultMode: "keep",
            headers: {
              defaultMode: "keep",
            },
          },
        },
      },
      // Enable Traefik dashboard API
      api: {
        dashboard: true,
        insecure: false, // Only accessible via IngressRoute, not insecure port
      },
      // Configure entry points
      ports: {
        web: {
          port: 80,
          exposedPort: 80,
        },
        websecure: {
          port: 443,
          exposedPort: 443,
          // Enable HTTP/3
          http3: {
            enabled: true,
          },
        },
        // Traefik dashboard (optional, for debugging)
        traefik: {
          port: 9000,
          exposedPort: 9000,
        },
      },
      // Enable dashboard API
      ingressRoute: {
        dashboard: {
          enabled: false, // We'll create custom IngressRoute with auth
        },
      },
      // Global redirect from HTTP to HTTPS using command-line arguments
      additionalArguments: [
        "--entrypoints.web.http.redirections.entryPoint.to=websecure",
        "--entrypoints.web.http.redirections.entryPoint.scheme=https",
        "--entrypoints.web.http.redirections.entrypoint.permanent=true",
      ],
    },
  },
  { dependsOn: [traefikNamespace] }
);

// Authentik Forward Auth Middleware
// Points to the dedicated Authentik outpost service for forward authentication
const authentikMiddleware = new k8s.apiextensions.CustomResource("traefik-authentik-middleware", {
  apiVersion: "traefik.io/v1alpha1",
  kind: "Middleware",
  metadata: {
    name: "authentik",
    namespace: traefikNamespace.metadata.name,
  },
  spec: {
    forwardAuth: {
      // MUST use public URL (not internal cluster URL) for domain-level forward auth
      // This ensures browser cookies are properly forwarded through the ingress
      address: "https://auth.mvissing.de/outpost.goauthentik.io/auth/traefik",
      trustForwardHeader: true,
      authResponseHeaders: [
        "X-authentik-username",
        "X-authentik-groups",
        "X-authentik-email",
        "X-authentik-name",
        "X-authentik-uid",
      ],
      authResponseHeadersRegex: "^X-authentik-",
    },
  },
}, { dependsOn: [traefik, authentikOutpostService] });

// Certificate for Traefik Internal Dashboard
const dashboardCertificate = new k8s.apiextensions.CustomResource("traefik-internal-cert", {
  apiVersion: "cert-manager.io/v1",
  kind: "Certificate",
  metadata: {
    name: "traefik-dashboard-tls",
    namespace: traefikNamespace.metadata.name,
  },
  spec: {
    secretName: "traefik-dashboard-tls",
    dnsNames: ["traefik-internal.mvissing.de"],
    issuerRef: {
      name: "letsencrypt-prod",
      kind: "ClusterIssuer",
      group: "cert-manager.io",
    },
  },
}, { dependsOn: [traefik] });

// IngressRoute for Traefik Internal Dashboard with Authentik Auth
const dashboardIngressRoute = new k8s.apiextensions.CustomResource("traefik-internal-dashboard", {
  apiVersion: "traefik.io/v1alpha1",
  kind: "IngressRoute",
  metadata: {
    name: "traefik-dashboard",
    namespace: traefikNamespace.metadata.name,
  },
  spec: {
    entryPoints: ["websecure"],
    routes: [
      {
        match: "Host(`traefik-internal.mvissing.de`)",
        kind: "Rule",
        middlewares: [
          {
            name: authentikMiddleware.metadata.name,
            namespace: traefikNamespace.metadata.name,
          },
        ],
        services: [
          {
            name: "api@internal",
            kind: "TraefikService",
          },
        ],
      },
    ],
    tls: {
      secretName: "traefik-dashboard-tls",
    },
  },
}, { dependsOn: [authentikMiddleware, dashboardCertificate] });

export { traefik, traefikNamespace, authentikMiddleware, dashboardCertificate, dashboardIngressRoute };