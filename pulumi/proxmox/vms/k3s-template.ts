import * as pulumi from "@pulumi/pulumi";
import * as command from "@pulumi/command";
import * as path from "path";
import { fileURLToPath } from "url";

/**
 * K3S Template Builder and Deployer
 *
 * Two-stage process:
 * 1. Build NixOS image with nixos-generators (always runs, creates hash)
 * 2. Deploy to Proxmox if hash changed (conditional)
 *
 * This ensures we only redeploy when the image actually changes.
 * Run this from the Proxmox host.
 */

const TEMPLATE_ID = 9000;
const STORAGE = "fast";
const IMAGE_DIR = "/tmp/nixos-k3s-template";

// Get script paths (ES module compatible)
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const buildScript = path.join(__dirname, "../scripts/build-nixos-image.sh");
const deployScript = path.join(__dirname, "../scripts/deploy-template.sh");

/**
 * Stage 1: Build the NixOS image
 *
 * Runs on every `pulumi up` (via timestamp trigger).
 * Nix caching makes this fast when nothing changed (~seconds).
 * If config changed anywhere, Nix rebuilds (~5-10 minutes).
 * Outputs image hash for Stage 2 to detect actual changes.
 */
export const buildImage = new command.local.Command("build-nixos-image", {
    create: `OUTPUT_DIR=${IMAGE_DIR} ${buildScript}`,
    update: `OUTPUT_DIR=${IMAGE_DIR} ${buildScript}`,

    // Always run by using timestamp as trigger
    // Nix handles caching internally, so this is fast when nothing changed
    triggers: [
        Date.now().toString(),
    ],
}, {
    deleteBeforeReplace: false,
});

/**
 * Stage 2: Deploy template to Proxmox
 *
 * Only runs when the image hash changes.
 * Reads stdout from the deploy script which outputs the hash.
 */
export const deployTemplate = new command.local.Command("deploy-k3s-template", {
    create: pulumi.interpolate`TEMPLATE_ID=${TEMPLATE_ID} STORAGE=${STORAGE} IMAGE_DIR=${IMAGE_DIR} ${deployScript}`,

    update: pulumi.interpolate`TEMPLATE_ID=${TEMPLATE_ID} STORAGE=${STORAGE} IMAGE_DIR=${IMAGE_DIR} ${deployScript}`,

    // Trigger deployment when image hash changes
    triggers: [
        buildImage.stdout, // Contains the build completion status
    ],
}, {
    dependsOn: [buildImage],
    deleteBeforeReplace: true,
});

// Export template ID and version (hash) for VMs to depend on
export const templateId = TEMPLATE_ID;
export const templateVersion = deployTemplate.stdout; // This is the image hash