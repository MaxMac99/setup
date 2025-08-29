{
  lib,
  inputs,
  ...
}: let
  inherit (inputs.nvf.lib.nvim.dag) entryAfter;
  inherit (inputs.nvf.lib.nvim.lua) toLuaObject;
  inherit (lib.attrsets) mapAttrsToList;
  inherit (lib.generators) mkLuaInline;

  whichKeyBinds = mapAttrsToList (n: v:
    lib.lists.optional (v != null) (mkLuaInline (
      if builtins.isAttrs v
      then "'${n}', " + builtins.concatStringsSep ", " (lib.attrsets.mapAttrsToList (key: val: "${key} = '${val}'") v)
      else "'${n}', desc = '${v}'"
    ))) {
    "<leader>s" = {
      group = "[S]earch";
      icon = "";
    };
    "<leader>sb" = {
      desc = "[B]uffers";
      icon = "";
    };
    "<leader>sd" = {
      desc = "[D]iagnostics";
      icon = "";
    };
    "<leader>sf" = {
      desc = "[F]iles";
      icon = "";
    };
    "<leader>sg" = {
      desc = "[G]lobal";
      icon = "";
    };
    "<leader>sh" = {
      desc = "[H]elp";
      icon = "󰋗";
    };
    "<leader>sr" = {
      desc = "[R]esume";
      icon = "󰐊";
    };
    "<leader>st" = {
      desc = "[T]reesitter";
      icon = "";
    };
    "<leader>so" = {
      desc = "[O]pen";
      icon = "";
    };
    "<leader>sl" = {
      group = "[L]sp";
      icon = "";
    };
    "gd" = {
      desc = "[D]efinitions";
      icon = "";
    };
    "<leader>sli" = {
      desc = "[I]mplementations";
      icon = "";
    };
    "gr" = {
      desc = "[R]eferences";
      icon = "";
    };
    "<leader>slt" = {
      desc = "[T]ype Definitions";
      icon = "󰉺";
    };
    "<leader>sls" = {
      group = "[S]ymobls";
      icon = "󰔶";
    };
    "<leader>slsd" = {
      desc = "[D]ocument";
      icon = "";
    };
    "<leader>slsw" = {
      desc = "[W]orkspace";
      icon = "";
    };
    "<leader>sv" = {
      group = "[V]ersion Control";
      icon = "";
    };
    "<leader>svb" = {
      desc = "[B]ranches";
      icon = "";
    };
    "<leader>svs" = {
      desc = "[S]tatus";
      icon = "󰄬";
    };
    "<leader>svx" = {
      desc = "Stash";
      icon = "";
    };
    "<leader>svc" = {
      group = "[C]ommits";
      icon = "";
    };
    "<leader>svcb" = {
      desc = "[B]uffer";
      icon = "";
    };
    "<leader>svcw" = {
      desc = "Commits";
      icon = "";
    };

    "<leader>c" = {
      group = "[C]ode";
      icon = "";
    };
    "<leader>cf" = {
      desc = "[F]ormat";
    };

    "<leader>d" = {
      group = "[D]ebug";
      icon = "";
    };
    "<leader>db" = {
      desc = "[B]reakpoint";
      icon = "";
    };
    "<leader>dc" = {
      desc = "[C]ontinue";
      icon = "";
    };
    "<leader>dh" = {
      desc = "[H]over";
      icon = "";
    };
    "<leader>dq" = {
      desc = "Terminate";
      icon = "󰈆";
    };
    "<leader>dR" = {
      desc = "[R]estart";
      icon = "";
    };

    "<leader>g" = {
      group = "[G]it";
      icon = "";
    };

    "<leader>a" = {
      group = "[A]i";
    };
  };
in {
  programs.nvf.settings.vim = {
    binds = {
      whichKey = {
        enable = true;
        register = {
          "<leader>f" = null;
          "<leader>fl" = null;
          "<leader>fm" = null;
          "<leader>fv" = null;
          "<leader>fvc" = null;
          "<leader>ca" = "[A]ction";
        };
        setupOpts.icons = {
          group = "▸";
        };
      };
    };
    luaConfigRC.whichkeyadds = entryAfter ["whichkey"] ''
      wk.add(${toLuaObject whichKeyBinds})
    '';
  };
}
