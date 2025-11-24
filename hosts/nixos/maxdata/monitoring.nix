{
  config,
  lib,
  pkgs,
  ...
}: {
  # ZFS Prometheus Exporter
  services.zfs-prometheus-exporter = {
    enable = true;
    port = 9134;
    openFirewall = true;
    logLevel = "debug";
    logFormat = "json";
  };

  # Promtail - Log shipping to Loki
  services.promtail = {
    enable = true;
    configuration = {
      server = {
        http_listen_port = 3031;
        grpc_listen_port = 0;
      };

      # Send logs to Loki LoadBalancer in Kubernetes cluster
      clients = [
        {
          url = "http://192.168.178.11:3100/loki/api/v1/push";
        }
      ];

      positions = {
        filename = "/var/lib/promtail/positions.yaml";
      };

      scrape_configs = [
        # System journal logs
        {
          job_name = "journal";
          journal = {
            max_age = "12h";
            labels = {
              job = "systemd-journal";
              host = "maxdata";
            };
          };
          relabel_configs = [
            {
              source_labels = ["__journal__systemd_unit"];
              target_label = "unit";
            }
            {
              source_labels = ["__journal__hostname"];
              target_label = "hostname";
            }
            {
              source_labels = ["__journal_priority_keyword"];
              target_label = "level";
            }
          ];
        }

        # Proxmox logs
        {
          job_name = "proxmox";
          static_configs = [
            {
              targets = ["localhost"];
              labels = {
                job = "proxmox";
                host = "maxdata";
                __path__ = "/var/log/pve/**/*.log";
              };
            }
          ];
        }

        # Samba logs
        {
          job_name = "samba";
          static_configs = [
            {
              targets = ["localhost"];
              labels = {
                job = "samba";
                host = "maxdata";
                __path__ = "/var/log/samba/*.log";
              };
            }
          ];
        }
      ];
    };
  };

  # Open firewall for Promtail HTTP (for status/metrics)
  networking.firewall.allowedTCPPorts = [
    3031 # Promtail HTTP
  ];

  # Ensure log directories and promtail state directory exist
  systemd.tmpfiles.rules = [
    "d /var/log/pve 0755 root root -"
    "d /var/lib/promtail 0755 promtail promtail -"
  ];
}
