{
  nixConfig.allow-import-from-derivation = false;

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs = { self, nixpkgs, treefmt-nix }:
    let

      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      treefmtEval = treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.nixpkgs-fmt.enable = true;
        programs.prettier.enable = true;
        programs.shfmt.enable = true;
        programs.shellcheck.enable = true;
        settings.formatter.shellcheck.options = [ "-s" "sh" ];
        settings.global.excludes = [ "LICENSE" "*.txt" "node-env.nix" "default.nix" "node-packages.nix" ];
      };

      dependencies = import ./default.nix {
        pkgs = pkgs;
        system = "x86_64-linux";
        nodejs = pkgs.nodejs;
      };

      src = pkgs.runCommandLocal "src" { } ''
        mkdir -p "$out/node_modules"
        cp -Lr ${dependencies.nodeDependencies}/lib/node_modules/* "$out/node_modules"
        cp -L ${./package.json} "$out"
      '';

      tailwindcss = pkgs.writeShellApplication {
        name = "tailwindcss";
        text = ''
          export NODE_PATH=${src}/node_modules
          exec ${pkgs.nodejs}/bin/node ${src}/node_modules/@tailwindcss/cli/dist/index.mjs "$@"
        '';
      };

      updateDependencies = pkgs.writeShellApplication {
        name = "update-dependencies";
        text = ''
          trap 'cd $(pwd)' EXIT
          root=$(git rev-parse --show-toplevel)
          cd "$root" || exit
          git add -A
          trap 'git reset >/dev/null' EXIT

          ${pkgs.nodejs}/bin/npm install --lockfile-version 2 --package-lock-only
          ${pkgs.node2nix}/bin/node2nix -- --lock package-lock.json --nodejs-18
        '';
      };

      packages = {
        formatting = treefmtEval.config.build.check self;
        tailwindcss = tailwindcss;
        default = tailwindcss;
      };

      gcroot = packages // {
        gcroot-all = pkgs.linkFarm "gcroot-all" packages;
      };

    in
    {
      packages.x86_64-linux = gcroot;
      checks.x86_64-linux = gcroot;
      formatter.x86_64-linux = treefmtEval.config.build.wrapper;

      apps.x86_64-linux.update-dependencies = {
        type = "app";
        program = "${updateDependencies}/bin/update-dependencies";
      };

    };
}
