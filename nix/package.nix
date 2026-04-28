{
  lib,
  stdenv,
  swift,
  swiftpm,
  installShellFiles,
  fetchFromGitHub,
  src,
}:

let
  swift-argument-parser-src = fetchFromGitHub {
    owner = "apple";
    repo = "swift-argument-parser";
    rev = "626b5b7b2f45e1b0b1c6f4a309296d1d21d7311b";
    hash = "sha256-90ECc3iEmxvOUk9iLKbQdQEz88dOisPqWsJLOFcKUV8=";
  };

  yams-src = fetchFromGitHub {
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
in
stdenv.mkDerivation {
  pname = "dug";
  version = "0.2.1";

  inherit src;

  nativeBuildInputs = [
    swift
    swiftpm
    installShellFiles
  ];

  # Catch dylib rewriting failures at build time — the installed binary
  # must not reference the Nix Swift runtime (it uses system dylibs).
  disallowedReferences = [ swift ];

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
    for lib in $(otool -L "$out/bin/dug" | grep /nix/store | awk '{print $1}'); do
      name=$(basename "$lib")
      if [[ "$name" == libswift* ]]; then
        /usr/bin/install_name_tool -change "$lib" "/usr/lib/swift/$name" "$out/bin/dug"
      elif [[ "$name" == libresolv* ]]; then
        /usr/bin/install_name_tool -change "$lib" "/usr/lib/$name" "$out/bin/dug"
      fi
    done
    /usr/bin/codesign --force --sign - "$out/bin/dug"

    installManPage dug.1

    installShellCompletion --cmd dug \
      --bash share/completions/dug.bash \
      --zsh share/completions/_dug \
      --fish share/completions/dug.fish
  '';

  meta = with lib; {
    description = "macOS-native DNS lookup utility using the system resolver";
    homepage = "https://github.com/shortrib-labs/dug";
    license = licenses.gpl3Only;
    platforms = platforms.darwin;
    mainProgram = "dug";
  };
}
