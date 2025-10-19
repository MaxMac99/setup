import * as pulumi from "@pulumi/pulumi";
import * as proxmox from "@muhlba91/pulumi-proxmoxve";
import * as command from "@pulumi/command";
import { deployTemplate, templateVersion } from "./k3s-template";
import { NetworkConfig, ProxmoxConfig } from "../config";

/**
 * K3S Node VM Configuration
 *
 * Creates NixOS-based K3S cluster nodes by cloning a template
 *
 * Prerequisites:
 * 1. Build the template image on Proxmox host:
 *    cd /path/to/setup && ./scripts/build-k3s-image.sh
 * 2. This builds from hosts/nixos/k3s-template and creates template ID 9000
 * 3. Pulumi clones this template for each node
 *
 * Configuration:
 * - CPU: 2 vCPUs per node
 * - Memory: 6GB per node
 * - Disk: 32GB on fast NVMe storage
 * - Network: VirtIO-Net with DHCP
 */

export interface K3sNodeConfig {
    vmId: number;
    vmName: string;
    cpuCores: number;
    memoryMB: number;
    diskSizeGB: number;
    role: "server" | "agent";
    sshKeys: string[];
    k3sToken: pulumi.Output<string>;
    serverAddr?: string; // For nodes joining the cluster
    clusterInit?: boolean; // Only true for first node
    ipAddress?: string; // Static IP with CIDR (e.g., "192.168.178.101/24")
    gateway?: string; // Gateway IP (e.g., "192.168.178.1")
}

// K3S cluster shared configuration from Pulumi config
const config = new pulumi.Config();
const K3S_TOKEN = config.requireSecret("k3sToken");
const SSH_KEYS = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMEZtPDynBeLhBBVpFugAD14CHoHJicGJXVKzm+mu3Kc max@maxdata",
];

export const k3sNodeConfigs: K3sNodeConfig[] = [
    {
        vmId: 201,
        vmName: "k3s-node1",
        cpuCores: 2,
        memoryMB: 6144,
        diskSizeGB: 32,
        role: "server",
        sshKeys: SSH_KEYS,
        k3sToken: K3S_TOKEN.apply(t => t),
        clusterInit: true, // First node initializes cluster
        ipAddress: `${NetworkConfig.staticIPs["k3s-node1"]}/24`,
        gateway: NetworkConfig.gateway,
    },
    {
        vmId: 202,
        vmName: "k3s-node2",
        cpuCores: 2,
        memoryMB: 6144,
        diskSizeGB: 32,
        role: "server",
        sshKeys: SSH_KEYS,
        k3sToken: K3S_TOKEN.apply(t => t),
        serverAddr: `https://${NetworkConfig.staticIPs["k3s-node1"]}:6443`, // Join existing cluster via static IP
        ipAddress: `${NetworkConfig.staticIPs["k3s-node2"]}/24`,
        gateway: NetworkConfig.gateway,
    },
    {
        vmId: 203,
        vmName: "k3s-node3",
        cpuCores: 2,
        memoryMB: 6144,
        diskSizeGB: 32,
        role: "server",
        sshKeys: SSH_KEYS,
        k3sToken: K3S_TOKEN.apply(t => t),
        serverAddr: `https://${NetworkConfig.staticIPs["k3s-node1"]}:6443`, // Join existing cluster via static IP
        ipAddress: `${NetworkConfig.staticIPs["k3s-node3"]}/24`,
        gateway: NetworkConfig.gateway,
    },
];

const TEMPLATE_ID = 9000; // ID of the NixOS template created by build-k3s-image.sh

export function createK3sNode(config: K3sNodeConfig) {
    // Generate cloud-init user data for k3s configuration
    const cloudInitUserData = pulumi.interpolate`#cloud-config
hostname: ${config.vmName}
fqdn: ${config.vmName}.local
manage_etc_hosts: true

users:
  - name: max
    groups: wheel
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
${config.sshKeys.map(key => `      - ${key}`).join('\n')}

write_files:
  - path: /etc/rancher/k3s/config.yaml
    content: |
      token: ${config.k3sToken}
${config.serverAddr ? `      server: ${config.serverAddr}` : ''}
${config.clusterInit ? '      cluster-init: true' : ''}
    permissions: '0600'

runcmd:
  - systemctl start k3s
`;

    // Create cloud-init snippet file using local command
    // Avoids the sudo/tee quoting issues in proxmox.storage.File
    const snippetPath = `/var/lib/vz/snippets/cloud-init-${config.vmName}.yaml`;
    const cloudInitSnippet = new command.local.Command(`cloud-init-${config.vmName}`, {
        create: cloudInitUserData.apply(data =>
            `cat > ${snippetPath} << 'CLOUDINIT_EOF'\n${data}\nCLOUDINIT_EOF`
        ),
        delete: `rm -f ${snippetPath}`,
        triggers: [cloudInitUserData],
    });

    return new proxmox.vm.VirtualMachine(`k3s-${config.vmName}`, {
        nodeName: ProxmoxConfig.nodeName,
        name: config.vmName,
        vmId: config.vmId,

        // Clone from template
        clone: {
            vmId: TEMPLATE_ID,
            full: true, // Full clone, not linked
        },

        // Include template version in description
        // This causes VM to be replaced when template changes
        description: pulumi.interpolate`K3S node cloned from template ${TEMPLATE_ID}. Template version: ${templateVersion}. Init: ${cloudInitUserData}`,

        // CPU configuration
        cpu: {
            cores: config.cpuCores,
            sockets: 1,
            type: "host",
        },

        // Memory configuration
        memory: {
            dedicated: config.memoryMB,
        },

        // Disk resize (template has default size, expand if needed)
        disks: [
            {
                interface: "scsi0",
                datastoreId: ProxmoxConfig.datastoreId, // Use fast NVMe storage
                size: config.diskSizeGB,
                fileFormat: "raw",
                cache: "writeback",
                discard: "on",
                iothread: true,
            },
        ],

        // Cloud-init configuration
        initialization: {
            type: "nocloud",
            datastoreId: ProxmoxConfig.datastoreId,
            dns: {
                servers: NetworkConfig.dns.servers,
            },
            ipConfigs: [
                {
                    ipv4: {
                        address: config.ipAddress || "dhcp",
                        gateway: config.gateway,
                    },
                },
            ],
            userAccount: {
                username: "max",
                keys: config.sshKeys,
            },
            userDataFileId: `local:snippets/cloud-init-${config.vmName}.yaml`,
        },

        // Start on boot
        onBoot: true,
        started: true,

        // Agent
        agent: {
            enabled: true,
            trim: true,
            type: "virtio",
        },
    }, {
        // Ensure template is deployed and snippet file created before creating VMs
        dependsOn: [deployTemplate, cloudInitSnippet],
        // Recreate VMs when description changes (which includes template version)
        replaceOnChanges: ["description"],
        deleteBeforeReplace: true,
    });
}

export function createK3sCluster() {
    return k3sNodeConfigs.map(config => createK3sNode(config));
}