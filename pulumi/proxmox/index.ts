import * as pulumi from "@pulumi/pulumi";
import { createWindows11VM, defaultConfig, virtioISO } from "./vms/windows11";
import { buildImage, deployTemplate, templateId, templateVersion } from "./vms/k3s-template";
import { createK3sCluster, k3sNodeConfigs } from "./vms/k3s";

// Create Windows 11 VM with default configuration
// You can customize by passing a config object: createWindows11VM({ vmId: 100, ... })
const windows11 = createWindows11VM();

// Build and deploy the k3s template
// Stage 1: Build the NixOS image
const imageBuild = buildImage;
// Stage 2: Deploy template if hash changed
const templateDeploy = deployTemplate;

// Create K3S cluster nodes (they depend on the template being deployed)
const k3sNodes = createK3sCluster();

// Export VM information
export const vmId = windows11.vmId;
export const vmName = windows11.name;
export const macAddress = defaultConfig.macAddress;
export const virtioIsoId = virtioISO.id;

// Export K3S node information
export const k3sCluster = {
    nodes: k3sNodes.map((node, idx) => ({
        vmId: node.vmId,
        name: node.name,
        role: k3sNodeConfigs[idx].role,
    })),
};

export const summary = pulumi.interpolate`
VMs deployed successfully!

Windows 11 VM:
  VM ID: ${windows11.vmId}
  Name: ${windows11.name}
  Memory: ${defaultConfig.memoryMB / 1024}GB
  CPU: ${defaultConfig.cpuCores} vCPUs
  Network MAC: ${defaultConfig.macAddress}
  VirtIO ISO: ${virtioIsoId}

K3S Template: ${templateId}
K3S Cluster (cloned from template ${templateId}):
  Node 1: VM ${k3sNodes[0].vmId} - ${k3sNodes[0].name} (${k3sNodeConfigs[0].cpuCores} vCPUs, ${k3sNodeConfigs[0].memoryMB / 1024}GB RAM, ${k3sNodeConfigs[0].role})
  Node 2: VM ${k3sNodes[1].vmId} - ${k3sNodes[1].name} (${k3sNodeConfigs[1].cpuCores} vCPUs, ${k3sNodeConfigs[1].memoryMB / 1024}GB RAM, ${k3sNodeConfigs[1].role})
  Node 3: VM ${k3sNodes[2].vmId} - ${k3sNodes[2].name} (${k3sNodeConfigs[2].cpuCores} vCPUs, ${k3sNodeConfigs[2].memoryMB / 1024}GB RAM, ${k3sNodeConfigs[2].role})

Proxmox UI: https://192.168.178.2:8006

📖 See README.md for complete setup instructions
`;