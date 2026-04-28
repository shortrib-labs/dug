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

        swift-argument-parser-src = pkgs.fetchFromGitHub {
          owner = "apple";
          repo = "swift-argument-parser";
          rev = "626b5b7b2f45e1b0b1c6f4a309296d1d21d7311b";
          hash = "sha256-90ECc3iEmxvOUk9iLKbQdQEz88dOisPqWsJLOFcKUV8=";
        };

        yams-src = pkgs.fetchFromGitHub {
          owner = "jpsim";
          repo = "Yams";
          rev = "3d6871d5b4a5cd519adf233fbb576e0a2af71c17";
          hash = "sha256-5uxD2eAJpMVHMStfWUzHcgjlp0d/EYcr1l+Qq2xlMxU=";
        };

        workspaceState = builtins.toFile "workspace-state.json" (builtins.toJSON {
          version = 5;
          object = {
            artifacts = [];
            dependencies = [
              {
                basedOn = null;
                packageRef = {
                  identity = "swift-argument-parser";
                  kind = "remoteSourceControl";
                  location = "https://github.com/apple/swift-argument-parser";
                  name = "swift-argument-parser";
                };
                state = {
                  checkoutState = {
                    revision = "626b5b7b2f45e1b0b1c6f4a309296d1d21d7311b";
                    version = "1.7.1";
                  };
                  name = "checkout";
                };
                subpath = "swift-argument-parser";
              }
              {
                basedOn = null;
                packageRef = {
                  identity = "yams";
                  kind = "remoteSourceControl";
                  location = "https://github.com/jpsim/Yams";
                  name = "Yams";
                };
                state = {
                  checkoutState = {
                    revision = "3d6871d5b4a5cd519adf233fbb576e0a2af71c17";
                    version = "5.4.0";
                  };
                  name = "checkout";
                };
                subpath = "Yams";
              }
            ];
          };
        });

        dug = pkgs.stdenv.mkDerivation {
          pname = "dug";
          version = "0.2.1";

          src = self;

          nativeBuildInputs = with pkgs; [
            swift
            swiftpm
            installShellFiles
          ];

          # Catch dylib rewriting failures at build time — the installed binary
          # must not reference the Nix Swift runtime (it uses system dylibs).
          disallowedReferences = [ pkgs.swift ];

          configurePhase = ''
            mkdir -p .build/checkouts
            install -m 0600 ${workspaceState} .build/workspace-state.json
            ln -s ${swift-argument-parser-src} .build/checkouts/swift-argument-parser
            ln -s ${yams-src} .build/checkouts/Yams
          '';

          buildPhase = ''
            swift build --disable-sandbox -c release
          '';

          installPhase = ''
            binPath="$(swiftpmBinPath)"
            mkdir -p $out/bin
            cp $binPath/dug $out/bin/

            # Rewrite Nix store dylib paths to system equivalents.
            # The Nix-provided Swift runtime and libresolv dylibs cause SIGKILL
            # on macOS due to version/signing mismatches with the build target.
            for lib in $(otool -L $out/bin/dug | grep /nix/store | awk '{print $1}'); do
              name=$(basename "$lib")
              if [[ "$name" == libswift* ]]; then
                /usr/bin/install_name_tool -change "$lib" "/usr/lib/swift/$name" $out/bin/dug
              elif [[ "$name" == libresolv* ]]; then
                /usr/bin/install_name_tool -change "$lib" "/usr/lib/$name" $out/bin/dug
              fi
            done
            /usr/bin/codesign --force --sign - $out/bin/dug

            installManPage dug.1

            installShellCompletion --cmd dug \
              --bash share/completions/dug.bash \
              --zsh share/completions/_dug \
              --fish share/completions/dug.fish
          '';

          meta = with pkgs.lib; {
            description = "macOS-native DNS lookup utility using the system resolver";
            homepage = "https://github.com/shortrib-labs/dug";
            license = licenses.gpl3Only;
            platforms = platforms.darwin;
            mainProgram = "dug";
          };
        };
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
