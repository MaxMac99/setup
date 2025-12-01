// Diun - Docker Image Update Notifier
// Monitors container images and notifies when updates are available
// Provides Prometheus metrics for Grafana dashboard

import * as k8s from "@pulumi/kubernetes";
import * as pulumi from "@pulumi/pulumi";
import { namespaceName } from "./namespace";
import { ntfyInternalUrl } from "./ntfy";

const config = new pulumi.Config();
const ntfyUsername = config.requireSecret("ntfy-username");
const ntfyPassword = config.requireSecret("ntfy-password");

// PVC for Diun database
const diunPVC = new k8s.core.v1.PersistentVolumeClaim("diun-pvc", {
  metadata: {
    name: "diun-data",
    namespace: namespaceName,
  },
  spec: {
    accessModes: ["ReadWriteOnce"],
    storageClassName: "local-path",
    resources: {
      requests: {
        storage: "1Gi",
      },
    },
  },
});

// Secret for ntfy credentials
const diunSecret = new k8s.core.v1.Secret("diun-secret", {
  metadata: {
    name: "diun-secret",
    namespace: namespaceName,
  },
  type: "Opaque",
  stringData: {
    DIUN_NOTIF_NTFY_USERNAME: ntfyUsername,
    DIUN_NOTIF_NTFY_PASSWORD: ntfyPassword,
  },
});

// ConfigMap for Diun configuration
const diunConfig = new k8s.core.v1.ConfigMap("diun-config", {
  metadata: {
    name: "diun-config",
    namespace: namespaceName,
  },
  data: {
    "diun.yml": `
watch:
  # Check for updates every 6 hours
  schedule: "0 */6 * * *"
  # Compare digests
  compareDigest: true
  # First run should check all images
  firstCheckNotif: false

providers:
  kubernetes:
    # Watch all namespaces
    namespaces: []
    # Watch all pods by default
    watchByDefault: true

# Notification via ntfy (credentials via env vars)
notif:
  ntfy:
    endpoint: ${ntfyInternalUrl}
    topic: diun-updates
    priority: 3
    timeout: 10s
`,
  },
});

// ServiceAccount for Diun to access Kubernetes API
const diunServiceAccount = new k8s.core.v1.ServiceAccount("diun-sa", {
  metadata: {
    name: "diun",
    namespace: namespaceName,
  },
});

// ClusterRole for Diun to list pods across all namespaces
const diunClusterRole = new k8s.rbac.v1.ClusterRole("diun-cluster-role", {
  metadata: {
    name: "diun",
  },
  rules: [
    {
      apiGroups: [""],
      resources: ["pods"],
      verbs: ["get", "list", "watch"],
    },
  ],
});

// ClusterRoleBinding
const diunClusterRoleBinding = new k8s.rbac.v1.ClusterRoleBinding("diun-cluster-role-binding", {
  metadata: {
    name: "diun",
  },
  roleRef: {
    apiGroup: "rbac.authorization.k8s.io",
    kind: "ClusterRole",
    name: diunClusterRole.metadata.name,
  },
  subjects: [{
    kind: "ServiceAccount",
    name: diunServiceAccount.metadata.name,
    namespace: namespaceName,
  }],
});

// Deployment for Diun
const diunDeployment = new k8s.apps.v1.Deployment("diun", {
  metadata: {
    name: "diun",
    namespace: namespaceName,
  },
  spec: {
    replicas: 1,
    selector: {
      matchLabels: {
        app: "diun",
      },
    },
    template: {
      metadata: {
        labels: {
          app: "diun",
        },
        annotations: {
          "prometheus.io/scrape": "true",
          "prometheus.io/port": "8080",
          "prometheus.io/path": "/metrics",
        },
      },
      spec: {
        serviceAccountName: diunServiceAccount.metadata.name,
        containers: [{
          name: "diun",
          image: "crazymax/diun:4.28.0",
          args: ["serve"],
          env: [
            {
              name: "TZ",
              value: "Europe/Berlin",
            },
          ],
          envFrom: [{
            secretRef: {
              name: diunSecret.metadata.name,
            },
          }],
          ports: [{
            name: "http",
            containerPort: 8080,
          }],
          volumeMounts: [
            {
              name: "config",
              mountPath: "/etc/diun",
            },
            {
              name: "data",
              mountPath: "/data",
            },
          ],
          resources: {
            requests: {
              cpu: "50m",
              memory: "64Mi",
            },
            limits: {
              cpu: "200m",
              memory: "128Mi",
            },
          },
        }],
        volumes: [
          {
            name: "config",
            configMap: {
              name: diunConfig.metadata.name,
            },
          },
          {
            name: "data",
            persistentVolumeClaim: {
              claimName: diunPVC.metadata.name,
            },
          },
        ],
      },
    },
  },
});

// Service for Prometheus scraping
const diunService = new k8s.core.v1.Service("diun-service", {
  metadata: {
    name: "diun",
    namespace: namespaceName,
  },
  spec: {
    selector: {
      app: "diun",
    },
    ports: [{
      name: "http",
      port: 8080,
      targetPort: 8080,
    }],
  },
});

export { diunDeployment, diunService };

// Usage:
//
// Set ntfy credentials before deploying:
//   pulumi config set --secret ntfy-username "your-username"
//   pulumi config set --secret ntfy-password "your-password"
//
// Diun automatically watches all pods in the cluster and checks for image updates.
//
// Prometheus Metrics:
//   diun_image_info - Info about monitored images
//   diun_image_result - Update check results
//
// Notifications:
//   Updates are sent to ntfy topic "diun-updates"
//   Subscribe in ntfy app to receive push notifications
//
// Manual commands:
//   kubectl exec -n monitoring deploy/diun -- diun image list
//   kubectl exec -n monitoring deploy/diun -- diun image inspect <image>