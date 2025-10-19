import * as pulumi from "@pulumi/pulumi";
import * as command from "@pulumi/command";
import * as path from "path";
import * as fs from "fs";
import * as crypto from "crypto";
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

// Calculate hash of template configuration to trigger rebuilds on changes
const projectRoot = path.join(__dirname, "../../..");
const templateConfigPath = path.join(projectRoot, "hosts/nixos/k3s-template/default.nix");
const templateConfigHash = crypto
    .createHash("sha256")
    .update(fs.readFileSync(templateConfigPath, "utf8"))
    .digest("hex");

/**
 * Stage 1: Build the NixOS image
 *
 * Triggers rebuild when template configuration changes.
 * Nix caching makes this fast when nothing changed.
 * If config changed, Nix rebuilds (~5-10 minutes).
 * Always outputs the image hash for Stage 2 to check.
 */
export const buildImage = new command.local.Command("build-nixos-image", {
    create: `OUTPUT_DIR=${IMAGE_DIR} ${buildScript}`,
    update: `OUTPUT_DIR=${IMAGE_DIR} ${buildScript}`,

    // Trigger rebuild when template configuration changes
    triggers: [
        templateConfigHash,
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