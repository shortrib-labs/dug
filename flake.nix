{
  description = "dug - macOS-native DNS lookup utility using the system resolver";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [ "aarch64-darwin" "x86_64-darwin" ] (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        dug = pkgs.callPackage ./nix/package.nix { src = self; };
      in
      {
        packages.default = dug;

        checks = {
          # Check 1: Package builds successfully
          build = dug;

          # Check 2: Binary runs and prints version.
          # Requires __noChroot because the installed binary links against
          # system dylibs at /usr/lib/swift/ (rewritten from Nix store paths
          # in installPhase), which are not available inside the Nix sandbox.
          version = pkgs.runCommand "dug-version-check" {
            __noChroot = true;
          } ''
            ${dug}/bin/dug --version > $out
          '';

          # Check 3: Man page is installed (installManPage gzips it)
          man-page = pkgs.runCommand "dug-man-page-check" {} ''
            test -f ${dug}/share/man/man1/dug.1.gz
            touch $out
          '';

          # Check 4: Shell completions are installed
          completions = pkgs.runCommand "dug-completions-check" {} ''
            test -f ${dug}/share/zsh/site-functions/_dug
            test -f ${dug}/share/bash-completion/completions/dug.bash
            test -f ${dug}/share/fish/vendor_completions.d/dug.fish
            touch $out
          '';
        };

        devShells.default = pkgs.mkShell {
          inputsFrom = [ dug ];
        };
      }
    ) // {
      overlays.default = final: prev: prev.lib.optionalAttrs prev.stdenv.isDarwin {
        dug = self.packages.${prev.stdenv.hostPlatform.system}.default;
      };
    };
}
