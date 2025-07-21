{
  stdenv,
  fetchurl,
  unzip,
}: let
  version = "1.11.5";
  src =
    if stdenv.isDarwin && stdenv.isAarch64
    then
      fetchurl {
        url = "https://github.com/vadimcn/codelldb/releases/download/v${version}/codelldb-darwin-arm64.vsix";
        sha256 = "sha256-TbbaTov2xX1cNuWrOl9q5hZkEgaMFO0WZheoX54O1/0=";
      }
    else if stdenv.isDarwin
    then
      fetchurl {
        url = "https://github.com/vadimcn/codelldb/releases/download/v${version}/codelldb-darwin-x64.vsix";
        sha256 = "";
      }
    else if stdenv.isAarch64
    then
      fetchurl {
        url = "https://github.com/vadimcn/codelldb/releases/download/v${version}/codelldb-linux-arm64.vsix";
        sha256 = "";
      }
    else
      fetchurl {
        url = "https://github.com/vadimcn/codelldb/releases/download/v${version}/codelldb-linux-x64.vsix";
        sha256 = "";
      };
in
  stdenv.mkDerivation {
    name = "codelldb-${version}";
    src = src;
    buildInputs = [unzip];
    unpackPhase = ''
      unzip $src -d .
    '';
    installPhase = ''
      mkdir -p $out
      cp -r ./* $out/
    '';
  }
