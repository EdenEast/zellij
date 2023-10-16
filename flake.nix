{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay }:
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          overlays = [ (import rust-overlay) ];
          pkgs = import nixpkgs { inherit system overlays; };
          manifest = builtins.fromTOML (builtins.readFile ./Cargo.toml);
          version = manifest.package.version;
          rustToolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;

          inherit (pkgs) lib;
          # craneLib = crane.lib.${system};

          zellij = pkgs.rustPlatform.buildRustPackage {
            inherit version;
            name = "zellij";
            src = pkgs.lib.cleanSourceWith { src = self; };
            cargoLock.lockFile = ./Cargo.lock;

            nativeBuildInputs = with pkgs; [
              mandown
              installShellFiles
              pkg-config
            ];
            buildInputs = with pkgs; [
              openssl
            ]
            ++ (
              with darwin.apple_sdk.frameworks;
              lib.optionals
                stdenv.isDarwin [
                libiconv
                DiskArbitration
                Foundation
              ]
            );

            postInstall = ''
              mandown docs/MANPAGE.md > zellij.1
              installManPage zellij.1

              installShellCompletion --cmd $pname \
                --bash <($out/bin/zellij setup --generate-completion bash) \
                --fish <($out/bin/zellij setup --generate-completion fish) \
                --zsh <($out/bin/zellij setup --generate-completion zsh)
            '';
          };
        in
        rec
        {
          apps = {
            zellij = flake-utils.lib.mkApp { drv = zellij; };
            default = apps.zellij;
          };

          packages = {
            zellij = zellij;
            default = packages.zellij;
          };

          devShells.default = pkgs.mkShell {
            buildInputs = with pkgs; [
              pkg-config
              openssl
              protobuf
              (rustToolchain.override {
                extensions = [ "rust-src" "clippy" "rustfmt" ];
              })
            ] ++ (
              with darwin.apple_sdk.frameworks;
              lib.optionals
                stdenv.isDarwin [
                libiconv
                DiskArbitration
                Foundation
              ]
            );
          };
        }) // {
      overlays.default = final: prev: {
        inherit (self.packages.${final.system}) zellij;
      };
    };
}
