{
  nixConfig.allow-import-from-derivation = false;

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.treefmt-nix.url = "github:numtide/treefmt-nix";

  outputs =
    { self, ... }@inputs:
    let
      lib = inputs.nixpkgs.lib;

      collectInputs =
        is:
        pkgs.linkFarm "inputs" (
          builtins.mapAttrs (
            name: i:
            pkgs.linkFarm name {
              self = i.outPath;
              deps = collectInputs (lib.attrByPath [ "inputs" ] { } i);
            }
          ) is
        );

      overlay = (
        final: prev:
        let
          generated = import ./generated {
            pkgs = final;
            system = "x86_64-linux";
            nodejs = final.nodejs;
          };
        in
        {
          tailwindcss = final.writeShellApplication {
            name = "tailwindcss";
            runtimeEnv.NODE_PATH = "${generated.nodeDependencies}/lib/node_modules";
            text = ''
              LD_LIBRARY_PATH=''${LD_LIBRARY_PATH:-}
              LD_LIBRARY_PATH=${final.stdenv.cc.cc.lib}:$LD_LIBRARY_PATH
              export LD_LIBRARY_PATH
              exec ${generated.nodeDependencies}/bin/tailwindcss "$@"
            '';
          };
          tailwindcss-language-server = final.writeShellApplication {
            name = "tailwindcss-language-server";
            runtimeEnv.NODE_PATH = "${generated.nodeDependencies}/lib/node_modules";
            text = "exec ${generated.nodeDependencies}/bin/tailwindcss-language-server \"$@\"";
          };
        }
      );

      pkgs = import inputs.nixpkgs {
        system = "x86_64-linux";
        overlays = [ overlay ];
      };

      treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.nixfmt.enable = true;
        programs.prettier.enable = true;
        programs.shfmt.enable = true;
        programs.shellcheck.enable = true;
        settings.formatter.shellcheck.options = [
          "-s"
          "sh"
        ];
        settings.global.excludes = [
          "LICENSE"
          "*.txt"
          "generated/**"
        ];
      };

      formatter = treefmtEval.config.build.wrapper;

      inputCss = pkgs.writeText "input.css" ''
        @import 'tailwindcss';
        @plugin 'daisyui';
      '';

      test = pkgs.runCommandLocal "test" { } ''
        cp -L "${inputCss}" ./input.css
        ${pkgs.tailwindcss}/bin/tailwindcss --input ./input.css --output ./output.css
        mkdir -p "$out"
        cp ./output.css "$out"
      '';

      updateDependencies = pkgs.writeShellApplication {
        name = "update-dependencies";
        text = ''
          trap 'cd $(pwd)' EXIT
          root=$(git rev-parse --show-toplevel)
          cd "$root" || exit
          git add -A
          trap 'git reset >/dev/null' EXIT

          ${pkgs.nodejs}/bin/npm update
          ${pkgs.nodejs}/bin/npm install --lockfile-version 2 --package-lock-only

          rm -rf node_modules
          cd generated
          ${pkgs.node2nix}/bin/node2nix -- --input ../package.json --lock ../package-lock.json
        '';
      };

      devShells.default = pkgs.mkShellNoCC {
        buildInputs = [ pkgs.nixd ];
      };

      packages = devShells // {
        updateDependencies = updateDependencies;
        formatting = treefmtEval.config.build.check self;
        formatter = formatter;
        allInputs = collectInputs inputs;
        tailwindcss = pkgs.tailwindcss;
        default = pkgs.tailwindcss;
        test = test;
      };

    in
    {

      packages.x86_64-linux = packages // {
        gcroot = pkgs.linkFarm "gcroot" packages;
      };

      checks.x86_64-linux = packages;
      formatter.x86_64-linux = formatter;
      overlays.default = overlay;
      devShells.x86_64-linux = devShells;

    };
}
