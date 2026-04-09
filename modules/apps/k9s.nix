{config, pkgs, lib, ...}: let
  kube-metrics = pkgs.buildGoModule rec {
    pname = "kube-metrics";
    version = "0.1.1";
    src = pkgs.fetchFromGitHub {
      owner = "bakito";
      repo = "kube-metrics";
      rev = "v${version}";
      hash = "sha256-bWXLebIK48ktWOS6Bgj29YUbMbH16EV0cFcuITKGbfU=";
    };
    vendorHash = "sha256-GoRfmeZAe0FOJen8dLyBP1YiWewWwgP8QQu0eITABME=";
  };
in {
  home-manager.users.${config.hostSpec.username} = {
    home.packages = [pkgs.jq kube-metrics];
    programs.k9s = {
      enable = true;
      plugins = {
        kube-metrics-pod = {
          shortCut = "m";
          confirm = false;
          description = "Metrics";
          scopes = ["pods" "nodes"];
          command = "sh";
          background = false;
          args = [
            "-c"
            ''
              if [ -n "$NAMESPACE" ]; then
                kube-metrics pod --namespace=$NAMESPACE $NAME
              else
                kube-metrics node $NAME
              fi
            ''
          ];
        };

        # Raw logs in less: follow newest when scrolled to end (Shift-F to resume
        # follow, Ctrl-C to pause and scroll back), lines wrap, colors preserved.
        logs-less-pod = {
          shortCut = "Shift-L";
          description = "logs|less +F";
          scopes = ["po" "deployment" "service"];
          command = "sh";
          background = false;
          args = [
            "-c"
            "kubectl logs -f --tail=-1 $RESOURCE_NAME/$NAME -n $NAMESPACE --context $CONTEXT | less -R +F"
          ];
        };

        logs-less-container = {
          shortCut = "Shift-L";
          description = "logs|less +F";
          scopes = ["containers"];
          command = "sh";
          background = false;
          args = [
            "-c"
            "kubectl logs -f --tail=-1 $POD -c $NAME -n $NAMESPACE --context $CONTEXT | less -R +F"
          ];
        };

        # Same as above but pipes each line through jq (falls back to raw line on
        # parse failure). -C forces colored output, --unbuffered streams each
        # line instead of blocking on jq's default output buffer.
        logs-jq-less-pod = {
          shortCut = "Ctrl-J";
          description = "logs|jq|less +F";
          scopes = ["po" "deployment" "service"];
          command = "sh";
          background = false;
          args = [
            "-c"
            "kubectl logs -f --tail=-1 $RESOURCE_NAME/$NAME -n $NAMESPACE --context $CONTEXT | jq -CSR --unbuffered '. as $line | try (fromjson) catch $line' | less -R +F"
          ];
        };

        logs-jq-less-container = {
          shortCut = "Ctrl-J";
          description = "logs|jq|less +F";
          scopes = ["containers"];
          command = "sh";
          background = false;
          args = [
            "-c"
            "kubectl logs -f --tail=-1 $POD -c $NAME -n $NAMESPACE --context $CONTEXT | jq -CSR --unbuffered '. as $line | try (fromjson) catch $line' | less -R +F"
          ];
        };
      };
    };
  };
}