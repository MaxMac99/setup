import * as pulumi from "@pulumi/pulumi";
import { createWindows11VM, defaultConfig, virtioISO } from "./vms/windows11";

// Create Windows 11 VM with default configuration
// You can customize by passing a config object: createWindows11VM({ vmId: 100, ... })
const windows11 = createWindows11VM();

// Export VM information
export const vmId = windows11.vmId;
export const vmName = windows11.name;
export const macAddress = defaultConfig.macAddress;
export const virtioIsoId = virtioISO.id;
export const summary = pulumi.interpolate`
Windows 11 VM deployed successfully!

VM Configuration:
  VM ID: ${windows11.vmId}
  Name: ${windows11.name}
  Memory: ${defaultConfig.memoryMB / 1024}GB
  CPU: ${defaultConfig.cpuCores} vCPUs
  Network MAC: ${defaultConfig.macAddress}
  VirtIO ISO: ${virtioIsoId}

Proxmox UI: https://192.168.178.2:8006

📖 See README.md for complete setup instructions including:
   - Importing your Unraid disk
   - Network configuration
   - VirtIO driver installation
   - Performance optimization
`;