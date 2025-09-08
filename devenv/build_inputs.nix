{pkgs, ...}:
let
  buildInputs = with pkgs; [
    python312
    stdenv.cc.cc
    gcc-unwrapped
    glibc
    tesseract
    glib
    openssh
    cmake
    gcc
    pkg-config
    protobuf
    libglvnd
    zlib
    cudaPackages.cudatoolkit

  ];
  

in buildInputs