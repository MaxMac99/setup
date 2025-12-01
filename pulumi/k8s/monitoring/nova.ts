// Nova - Helm Release Update Checker
// Runs as a CronJob to check for outdated Helm releases
// Sends notifications to ntfy when updates are available

import * as k8s from "@pulumi/kubernetes";
import * as pulumi from "@pulumi/pulumi";
import { namespaceName } from "./namespace";
import { ntfyInternalUrl } from "./ntfy";

const config = new pulumi.Config();
const ntfyUsername = config.requireSecret("ntfy-username");
const ntfyPassword = config.requireSecret("ntfy-password");

// ServiceAccount for Nova to access Helm releases
const novaServiceAccount = new k8s.core.v1.ServiceAccount("nova-sa", {
  metadata: {
    name: "nova",
    namespace: namespaceName,
  },
});

// ClusterRole for Nova to list Helm releases (secrets) across all namespaces
const novaClusterRole = new k8s.rbac.v1.ClusterRole("nova-cluster-role", {
  metadata: {
    name: "nova",
  },
  rules: [
    {
      apiGroups: [""],
      resources: ["secrets"],
      verbs: ["get", "list"],
    },
  ],
});

// ClusterRoleBinding
const novaClusterRoleBinding = new k8s.rbac.v1.ClusterRoleBinding("nova-cluster-role-binding", {
  metadata: {
    name: "nova",
  },
  roleRef: {
    apiGroup: "rbac.authorization.k8s.io",
    kind: "ClusterRole",
    name: novaClusterRole.metadata.name,
  },
  subjects: [{
    kind: "ServiceAccount",
    name: novaServiceAccount.metadata.name,
    namespace: namespaceName,
  }],
});

// Secret for ntfy credentials
const novaSecret = new k8s.core.v1.Secret("nova-secret", {
  metadata: {
    name: "nova-secret",
    namespace: namespaceName,
  },
  type: "Opaque",
  stringData: {
    NTFY_USERNAME: ntfyUsername,
    NTFY_PASSWORD: ntfyPassword,
  },
});

// CronJob for Nova
const novaCronJob = new k8s.batch.v1.CronJob("nova", {
  metadata: {
    name: "nova",
    namespace: namespaceName,
  },
  spec: {
    // Run every 6 hours (same as Diun)
    schedule: "30 */6 * * *",
    concurrencyPolicy: "Forbid",
    successfulJobsHistoryLimit: 3,
    failedJobsHistoryLimit: 3,
    jobTemplate: {
      spec: {
        template: {
          spec: {
            serviceAccountName: novaServiceAccount.metadata.name,
            restartPolicy: "OnFailure",
            containers: [{
              name: "nova",
              image: "ghcr.io/fairwindsops/nova:3.10.1",
              command: ["/bin/sh", "-c"],
              args: [pulumi.interpolate`
                # Run nova and capture output
                OUTPUT=$(nova find --wide 2>&1)

                # Check if there are outdated releases (nova exits 0 even with outdated)
                if echo "$OUTPUT" | grep -q "outdated"; then
                  # Send notification to ntfy
                  curl -s -u "$NTFY_USERNAME:$NTFY_PASSWORD" \
                    -H "Title: Helm Charts Update Available" \
                    -H "Priority: 3" \
                    -H "Tags: helm,update" \
                    -d "$OUTPUT" \
                    "${ntfyInternalUrl}/nova-updates"
                  echo "Updates found, notification sent"
                else
                  echo "All Helm releases are up to date"
                fi

                # Always print output for logging
                echo "$OUTPUT"
              `],
              env: [
                {
                  name: "NTFY_USERNAME",
                  valueFrom: {
                    secretKeyRef: {
                      name: novaSecret.metadata.name,
                      key: "NTFY_USERNAME",
                    },
                  },
                },
                {
                  name: "NTFY_PASSWORD",
                  valueFrom: {
                    secretKeyRef: {
                      name: novaSecret.metadata.name,
                      key: "NTFY_PASSWORD",
                    },
                  },
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
          },
        },
      },
    },
  },
});

export { novaCronJob };

// Usage:
//
// Nova runs every 6 hours and checks all Helm releases for updates.
// If outdated releases are found, a notification is sent to ntfy topic "nova-updates".
//
// Manual run:
//   kubectl create job --from=cronjob/nova nova-manual -n monitoring
//
// View latest results:
//   kubectl logs -n monitoring job/nova-manual
//
// Subscribe to ntfy topic "nova-updates" for notifications.