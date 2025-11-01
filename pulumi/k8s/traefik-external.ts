// External Traefik - Runs on ionos node for public internet access
// This is a second Traefik instance that handles external traffic

import * as k8s from "@pulumi/kubernetes";
import * as pulumi from "@pulumi/pulumi";
import { authentikOutpostService } from "./authentik-outpost";
import { authentikNamespace } from "./authentik";

// Create namespace for external ingress
const namespace = new k8s.core.v1.Namespace("traefik-external", {
  metadata: { name: "traefik-external" },
});

// Deploy Traefik as DaemonSet on ionos node only
const traefikExternal = new k8s.helm.v3.Release("traefik-external", {
  chart: "traefik",
  version: "32.1.1",
  namespace: namespace.metadata.name,
  repositoryOpts: {
    repo: "https://traefik.github.io/charts",
  },
  values: {
    // Run only on ionos (edge) node
    nodeSelector: {
      "edge": "true",
    },

    // Tolerate any taints on the edge node
    tolerations: [
      {
        operator: "Exists",
      },
    ],

    // Use DaemonSet to ensure it runs on ionos
    deployment: {
      kind: "DaemonSet",
    },

    // Update strategy for DaemonSet
    updateStrategy: {
      type: "RollingUpdate",
      rollingUpdate: {
        maxUnavailable: 2,  // Required to be > 1 when using hostNetwork
        maxSurge: 0,  // Must be 0 for DaemonSet when maxUnavailable is set
      },
    },

    // Use host network to bind to public IP
    hostNetwork: true,

    // Use cluster DNS even with hostNetwork
    dnsPolicy: "ClusterFirstWithHostNet",

    // Pod security context
    podSecurityContext: {
      runAsNonRoot: false,
      runAsUser: 0,
    },

    // Container security context - allow binding to privileged ports (80, 443)
    securityContext: {
      capabilities: {
        drop: ["ALL"],
        add: ["NET_BIND_SERVICE"],
      },
      runAsNonRoot: false,
      runAsUser: 0,
    },

    // Service configuration
    service: {
      enabled: true,
      type: "ClusterIP",  // Don't need LoadBalancer since we use hostNetwork
    },

    // Ports configuration
    ports: {
      web: {
        port: 80,
        exposedPort: 80,
        expose: {
          default: true,
        },
      },
      websecure: {
        port: 443,
        exposedPort: 443,
        expose: {
          default: true,
        },
        http3: {
          enabled: true,
        },
      },
      // Dashboard
      traefik: {
        port: 9000,
        expose: {
          default: false,  // Not exposed externally
        },
      },
    },

    // Logs configuration
    logs: {
      general: {
        level: "INFO",
      },
      access: {
        enabled: true,
      },
    },

    // Enable Traefik dashboard API
    api: {
      dashboard: true,
      insecure: false, // Only accessible via IngressRoute, not insecure port
    },

    // Enable IngressRoute CRDs
    ingressRoute: {
      dashboard: {
        enabled: false,  // Disable default dashboard, create custom one if needed
      },
    },

    // Provider configuration - watch all namespaces
    providers: {
      kubernetesCRD: {
        enabled: true,
        allowCrossNamespace: true,
      },
      kubernetesIngress: {
        enabled: true,
        publishedService: {
          enabled: false,  // We use hostNetwork, not LoadBalancer
        },
      },
    },

    // Dual-stack configuration
    ipFamilyPolicy: "PreferDualStack",

    // Disable automatic IngressClass creation (we create it explicitly below)
    ingressClass: {
      enabled: false,
    },

    // Global redirect from HTTP to HTTPS using command-line arguments
    additionalArguments: [
      "--entrypoints.web.http.redirections.entryPoint.to=websecure",
      "--entrypoints.web.http.redirections.entryPoint.scheme=https",
      "--entrypoints.web.http.redirections.entrypoint.permanent=true",
    ],
  },
});

// Create explicit IngressClass with fixed name
const traefikExternalIngressClass = new k8s.networking.v1.IngressClass("traefik-external-class", {
  metadata: {
    name: "traefik-external", // Explicitly set the name without hash
  },
  spec: {
    controller: "traefik.io/ingress-controller",
  },
}, { dependsOn: [traefikExternal] });

// Authentik Forward Auth Middleware for External Traefik
const authentikMiddlewareExternal = new k8s.apiextensions.CustomResource("traefik-external-authentik-middleware", {
  apiVersion: "traefik.io/v1alpha1",
  kind: "Middleware",
  metadata: {
    name: "authentik",
    namespace: namespace.metadata.name,
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
}, { dependsOn: [traefikExternal, authentikOutpostService] });

// Certificate for Traefik External Dashboard
const dashboardCertificateExternal = new k8s.apiextensions.CustomResource("traefik-external-cert", {
  apiVersion: "cert-manager.io/v1",
  kind: "Certificate",
  metadata: {
    name: "traefik-external-dashboard-tls",
    namespace: namespace.metadata.name,
  },
  spec: {
    secretName: "traefik-external-dashboard-tls",
    dnsNames: ["traefik-external.mvissing.de"],
    issuerRef: {
      name: "letsencrypt-prod",
      kind: "ClusterIssuer",
      group: "cert-manager.io",
    },
  },
}, { dependsOn: [traefikExternal] });

// IngressRoute for Traefik External Dashboard with Authentik Auth
const dashboardIngressRouteExternal = new k8s.apiextensions.CustomResource("traefik-external-dashboard", {
  apiVersion: "traefik.io/v1alpha1",
  kind: "IngressRoute",
  metadata: {
    name: "traefik-external-dashboard",
    namespace: namespace.metadata.name,
  },
  spec: {
    entryPoints: ["websecure"],
    routes: [
      {
        match: "Host(`traefik-external.mvissing.de`)",
        kind: "Rule",
        middlewares: [
          {
            name: authentikMiddlewareExternal.metadata.name,
            namespace: namespace.metadata.name,
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
      secretName: "traefik-external-dashboard-tls",
    },
  },
}, { dependsOn: [authentikMiddlewareExternal, dashboardCertificateExternal] });

export { traefikExternal, traefikExternalIngressClass, authentikMiddlewareExternal, dashboardCertificateExternal, dashboardIngressRouteExternal };