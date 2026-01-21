{pkgs,uvPackage, ...}:
let

  runtimePackages = with pkgs; [
    stdenv.cc.cc
    gcc-unwrapped
    glibc
    ffmpeg-headless.bin
    tesseract
    uvPackage
    libglvnd 
    glib
    zlib
    gnumake
    cudaPackages.cudatoolkit
  ];


in runtimePackages