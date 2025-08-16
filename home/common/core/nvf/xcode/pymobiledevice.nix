{pkgs, ...}: let
  python = pkgs.python313;
  gpxpyOld = python.pkgs.buildPythonPackage rec {
    pname = "gpxpy";
    version = "1.5.0";
    pyproject = true;
    nativeBuildInputs = with python.pkgs; [
      setuptools
    ];
    src = pkgs.fetchPypi {
      inherit pname version;
      sha256 = "sha256-5pk6iUXq4HqDPNMEuIu8bDwTLWOyv0qbCl2Ql2Frhwg=";
    };
  };
  pykdebugparser = python.pkgs.buildPythonPackage rec {
    pname = "pykdebugparser";
    version = "1.2.7";
    pyproject = true;
    src = pkgs.fetchPypi {
      inherit pname version;
      hash = "sha256-vfEKGluGFyZTATWRYseYpy2xFAP6z9E+InF81zPiHFQ=";
    };
    nativeBuildInputs = with python.pkgs; [
      pip
      setuptools
      wheel
    ];
    propagatedBuildInputs = with python.pkgs; [
      construct
      pygments
      click
      termcolor
    ];
    pythonImportsCheck = ["pykdebugparser"];
    doCheck = false;
  };
  parameter_decorators = python.pkgs.buildPythonPackage rec {
    pname = "parameter_decorators";
    version = "0.0.2";
    pyproject = true;
    src = pkgs.fetchPypi {
      inherit pname version;
      sha256 = "sha256-SZ7JbnE5RwW+nj7rKFQqq0h1aUBCUWwxBR1dywSIAo4=";
    };
    nativeBuildInputs = with python.pkgs; [
      setuptools
      wheel
    ];
  };
  pygnuutils = python.pkgs.buildPythonPackage rec {
    pname = "pygnuutils";
    version = "0.1.1";
    pyproject = true;
    src = pkgs.fetchPypi {
      inherit pname version;
      sha256 = "sha256-UatPJ961kQK3oEGS91hf8rOp3gNzmYLwsZ081NFr6nY=";
    };
    nativeBuildInputs = with python.pkgs; [
      setuptools
      wheel
    ];
    propagatedBuildInputs = with python.pkgs; [
      click
    ];
  };
  la_panic = python.pkgs.buildPythonPackage rec {
    pname = "la-panic";
    version = "0.5.0";
    pyproject = true;
    src = pkgs.fetchPypi {
      inherit pname version;
      sha256 = "sha256-UjkCXR6Wqu0fvRxKXTVXL9cM9C3daIOf8eTx0h4+J5s=";
    };
    nativeBuildInputs = with python.pkgs; [
      setuptools
      wheel
    ];
    propagatedBuildInputs = with python.pkgs; [
      click
      cached-property
      coloredlogs
    ];
  };
  pycrashreport = python.pkgs.buildPythonPackage rec {
    pname = "pycrashreport";
    version = "1.2.6";
    pyproject = true;
    src = pkgs.fetchPypi {
      inherit pname version;
      sha256 = "sha256-fUqlI8NMYzV9zzUgROV8g/ZBfXFrxSEsxK+HE1c6SlU=";
    };
    nativeBuildInputs = with python.pkgs; [
      setuptools
      setuptools-scm
      wheel
    ];
    propagatedBuildInputs = with python.pkgs; [
      click
      cached-property
      la_panic
    ];
  };
  inquirer3 = python.pkgs.buildPythonPackage rec {
    pname = "inquirer3";
    version = "0.6.1";
    pyproject = true;
    src = pkgs.fetchPypi {
      inherit pname version;
      sha256 = "sha256-rKDiaSLgujjIO85lpUs+0cX5HEyftyBoyWqIXidJurw=";
    };
    nativeBuildInputs = with python.pkgs; [
      poetry-core
    ];
    propagatedBuildInputs = with python.pkgs; [
      blessed
      editor
      readchar
    ];
  };
  pylzssOld = python.pkgs.buildPythonPackage rec {
    pname = "pylzss";
    version = "0.3.4";
    pyproject = true;
    src = pkgs.fetchPypi {
      inherit pname version;
      sha256 = "sha256-FoGGMXQkiOU6NP2g1ALYDtsrgS4Rh3gB4hqeXOm52xw=";
    };
    nativeBuildInputs = with python.pkgs; [
      setuptools
    ];
  };
  enumCompat = python.pkgs.buildPythonPackage rec {
    pname = "enum-compat";
    version = "0.0.3";
    src = pkgs.fetchPypi {
      inherit pname version;
      sha256 = "sha256-Nnfaq+1WpvckRR1YVmIlPY+05VaYRar6i7DaNrGodR4=";
    };
    pyproject = true;
    nativeBuildInputs = with python.pkgs; [
      setuptools
    ];
  };
  asn1Old = python.pkgs.buildPythonPackage rec {
    pname = "asn1";
    version = "2.8.0";
    src = pkgs.fetchPypi {
      inherit pname version;
      sha256 = "sha256-rfd93CcHz0IMDq47me4w6ROvzwk2Rn1CZpggzmt9FQo=";
    };
    pyproject = true;
    nativeBuildInputs = with python.pkgs; [
      setuptools
    ];
    propagatedBuildInputs = [
      enumCompat
    ];
  };
  apple-compress = python.pkgs.buildPythonPackage rec {
    pname = "apple_compress";
    version = "0.2.3";
    pyproject = true;
    src = pkgs.fetchPypi {
      inherit pname version;
      sha256 = "sha256-ochVzsi9cyEK6VIsU6hBylFd7S8MnVtOco0Nk/7kaik=";
    };
    nativeBuildInputs = with python.pkgs; [
      poetry-core
    ];
    propagatedBuildInputs = with python.pkgs; [
      click
      loguru
    ];
  };
  pyimg4 = python.pkgs.buildPythonPackage rec {
    pname = "pyimg4";
    version = "0.8.8";
    pyproject = true;
    src = pkgs.fetchPypi {
      inherit pname version;
      sha256 = "sha256-qv67K8eSL2z1UbG56YLS2gOcvrCPCi4gSKGBjVHHbaE=";
    };
    nativeBuildInputs = with python.pkgs; [
      hatchling
      uv-dynamic-versioning
    ];
    propagatedBuildInputs = with python.pkgs; [
      apple-compress
      asn1Old
      click
      pycryptodome
      pylzssOld
    ];
  };
  remotezip2 = python.pkgs.buildPythonPackage rec {
    pname = "remotezip2";
    version = "0.0.2";
    pyproject = true;
    src = pkgs.fetchPypi {
      inherit pname version;
      sha256 = "sha256-2zj7FNDCl69tqHVoCLsl+dOywjx2OaFPenR5Sy/JomE=";
    };
    nativeBuildInputs = with python.pkgs; [
      setuptools
      setuptools-scm
      wheel
    ];
  };
  ipsw-parser = python.pkgs.buildPythonPackage rec {
    pname = "ipsw_parser";
    version = "1.4.4";
    pyproject = true;
    src = pkgs.fetchPypi {
      inherit pname version;
      sha256 = "sha256-JuDBh/Jb/rRgwOTBaHjlgybWHdvdhWTfRTHPWCQPuVE=";
    };
    nativeBuildInputs = with python.pkgs; [
      setuptools
      setuptools-scm
      wheel
    ];
    propagatedBuildInputs = with python.pkgs; [
      construct
      click
      coloredlogs
      cached-property
      plumbum
      pyimg4
      requests
      remotezip2
    ];
  };
  qh3 = python.pkgs.buildPythonPackage rec {
    pname = "qh3";
    version = "1.5.3";
    format = "pyproject";
    src = pkgs.fetchFromGitHub {
      owner = "jawah";
      repo = "qh3";
      rev = "v${version}";
      sha256 = "sha256-4sgXvS/anKIHDJrYZhwcrmtzVU7XXAwAIpmiR2WHvuo=";
    };
    cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
      inherit pname version src;
      hash = "sha256-k4IG2kITRFNAXdPrsCr6VMAQxwb4NPmBXUz7jSvS/O4=";
    };
    nativeBuildInputs = with pkgs; [
      rustPlatform.cargoSetupHook
      rustPlatform.maturinBuildHook
      rustc
      cargo
      cmake
    ];
    dontUseCmakeConfigure = true;
    propagatedBuildInputs = [];
    pythonImportsCheck = ["qh3"];
  };
  developer-disk-image = python.pkgs.buildPythonPackage rec {
    pname = "developer_disk_image";
    version = "0.2.0";
    pyproject = true;
    src = pkgs.fetchPypi {
      inherit pname version;
      sha256 = "sha256-21aLIuwznYtWsprptCAjDq4yL+ab50zZn9Dv+w7y4o8=";
    };
    nativeBuildInputs = with python.pkgs; [
      setuptools
      setuptools-scm
      wheel
    ];
    propagatedBuildInputs = with python.pkgs; [
      requests
    ];
  };
  opack2 = python.pkgs.buildPythonPackage rec {
    pname = "opack2";
    version = "0.0.1";
    pyproject = true;
    src = pkgs.fetchPypi {
      inherit pname version;
      sha256 = "sha256-DesLXXCUJT9jHbIB80kwlKWCFAT3NqsCNLqAXuk9V7I=";
    };
    nativeBuildInputs = with python.pkgs; [
      setuptools
      wheel
    ];
    propagatedBuildInputs = with python.pkgs; [
      arrow
      construct
    ];
  };
  pytun-pmd3 = python.pkgs.buildPythonPackage rec {
    pname = "pytun_pmd3";
    version = "2.2.2";
    pyproject = true;
    src = pkgs.fetchPypi {
      inherit pname version;
      sha256 = "sha256-NE/YOCGbbjP/rXgQkPEp1OOrOd6ThbXgSCc/F2lvIVo=";
    };
    nativeBuildInputs = with python.pkgs; [
      setuptools
      setuptools-scm
      wheel
    ];
  };
  python-pcapng = python.pkgs.buildPythonPackage rec {
    pname = "python-pcapng";
    version = "2.1.1";
    pyproject = true;
    src = pkgs.fetchPypi {
      inherit pname version;
      sha256 = "sha256-ZHfnJRMWWVTlbVg2671DrH+NKMRkD3jWPWUG0Wkt3HQ=";
    };
    nativeBuildInputs = with python.pkgs; [
      setuptools
      setuptools-scm
      wheel
    ];
  };
  pymobiledevice3 = python.pkgs.buildPythonApplication rec {
    pname = "pymobiledevice3";
    version = "4.22.1";

    src = pkgs.fetchFromGitHub {
      owner = "doronz88";
      repo = "pymobiledevice3";
      rev = "972c29f9f7d9ed9f7675d59235e556b68fbfafdc";
      sha256 = "sha256-eMZhWoLn0Z/meNpSGCP+ZNH5dh4Z9W20TO7NrdCOmMU=";
    };
    format = "pyproject";

    nativeBuildInputs = with python.pkgs; [
      pip
      setuptools
      setuptools-scm
      wheel
    ];

    propagatedBuildInputs = [
      python.pkgs.construct
      asn1Old
      python.pkgs.click
      python.pkgs.coloredlogs
      python.pkgs.ipython
      python.pkgs.bpylist2
      python.pkgs.pygments
      python.pkgs.hexdump
      python.pkgs.arrow
      python.pkgs.daemonize
      gpxpyOld
      pykdebugparser
      python.pkgs.pyusb
      python.pkgs.tqdm
      python.pkgs.requests
      python.pkgs.xonsh
      parameter_decorators
      python.pkgs.packaging
      pygnuutils
      python.pkgs.cryptography
      pycrashreport
      python.pkgs.fastapi
      python.pkgs.uvicorn
      python.pkgs.starlette
      python.pkgs.wsproto
      python.pkgs.nest-asyncio
      python.pkgs.pillow
      inquirer3
      ipsw-parser
      remotezip2
      python.pkgs.zeroconf
      python.pkgs.ifaddr
      python.pkgs.hyperframe
      python.pkgs.srptools
      qh3
      developer-disk-image
      opack2
      python.pkgs.psutil
      pytun-pmd3
      python.pkgs.aiofiles
      python.pkgs.prompt-toolkit
      python-pcapng
      python.pkgs.plumbum
      pyimg4
    ];

    doCheck = false; # disable tests for now
  };
in {
  home.packages = with pkgs; [
    pymobiledevice3
  ];
}
