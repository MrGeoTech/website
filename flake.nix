{
  description = "Zig (master) Dev Flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig-overlay.url = "github:mitchellh/zig-overlay";
    zls-overlay.url = "github:zigtools/zls";
  };

  outputs = { self, nixpkgs, flake-utils, zig-overlay, zls-overlay, ... }:
  let
    systems = builtins.attrNames zig-overlay.packages;

    overlays = [
      (final: prev: {
        zig = zig-overlay.packages.${prev.system}."0.15.1";
        zls = zls-overlay.packages.${prev.system}.zls.overrideAttrs (old: {
          nativeBuildInputs = [ final.zig ];
        });
      })
    ];
  in
    flake-utils.lib.eachSystem systems (system:
      let
        pkgs = import nixpkgs {
          inherit system overlays;
        };
      in rec {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            zig
            zls
            # Test coverage
            kcov
            # Performance testing
            linuxKernel.packages.linux_zen.perf
          ];
        };

        # For compatibility with older versions of the `nix` binary
        devShell = self.devShells.${system}.default;
      }
    );
}
