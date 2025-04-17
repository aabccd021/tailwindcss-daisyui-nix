{
  nixConfig.allow-import-from-derivation = false;

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs = { self, nixpkgs, treefmt-nix }:
    let

      overlay = (final: prev:
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
            text = "exec ${generated.nodeDependencies}/bin/tailwindcss \"$@\"";
          };
        });

      pkgs = import nixpkgs {
        system = "x86_64-linux";
        overlays = [ overlay ];
      };

      lib = pkgs.lib;

      treefmtEval = treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.nixpkgs-fmt.enable = true;
        programs.prettier.enable = true;
        programs.shfmt.enable = true;
        programs.shellcheck.enable = true;
        settings.formatter.shellcheck.options = [ "-s" "sh" ];
        settings.global.excludes = [ "LICENSE" "*.txt" "generated/**" ];
      };

      test = pkgs.runCommandLocal "test" { } ''
        echo "@import 'tailwindcss';" > ./input.css
        echo "@plugin 'daisyui';" >> ./input.css
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

          ${pkgs.nodejs}/bin/npm install --lockfile-version 2 --package-lock-only

          rm -rf node_modules
          cd generated
          ${pkgs.node2nix}/bin/node2nix -- --input ../package.json --lock ../package-lock.json
        '';
      };

      packages = {
        formatting = treefmtEval.config.build.check self;
        tailwindcss = pkgs.tailwindcss;
        default = pkgs.tailwindcss;
        test = test;
      };

      gcroot = packages // {
        gcroot = pkgs.linkFarm "gcroot" packages;
      };

    in
    {
      packages.x86_64-linux = gcroot;
      checks.x86_64-linux = gcroot;
      formatter.x86_64-linux = treefmtEval.config.build.wrapper;
      overlays.default = overlay;

      apps.x86_64-linux.fix = {
        type = "app";
        program = "${lib.getExe updateDependencies}";
      };

      apps.x86_64-linux.default = {
        type = "app";
        program = "${lib.getExe pkgs.tailwindcss}";
      };

    };
}
