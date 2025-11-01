// Main entry point for K8s resources on the K3S cluster
// This file imports all resource definitions

// Infrastructure
import "./metallb";           // LoadBalancer implementation
import "./traefik";           // Internal Traefik configuration
import "./traefik-external";  // External Traefik on ionos node
import "./cert-manager";      // TLS certificate management with Let's Encrypt
import "./reflector"

// Databases
import "./postgresql";        // Shared PostgreSQL with CloudNativePG (operator only)
import "./redis";             // Shared Redis for caching and sessions

// Applications
import "./authentik";          // Identity Provider and SSO
import "./authentik-outpost";  // Authentik Forward Auth Outpost

// Backup services
import "./timemachine";  // Time Machine backup service for macOS
