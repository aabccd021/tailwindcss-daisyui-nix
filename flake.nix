{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    build-node-modules.url = "github:aabccd021/build-node-modules";
  };

  outputs = { self, nixpkgs, treefmt-nix, build-node-modules }:
    let

      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      treefmtEval = treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.nixpkgs-fmt.enable = true;
        programs.prettier.enable = true;
        programs.shfmt.enable = true;
        programs.shellcheck.enable = true;
        settings.formatter.shellcheck.options = [ "-s" "sh" ];
        settings.global.excludes = [ "LICENSE" "*.txt" ];
      };

      nodeModules = build-node-modules.lib.buildNodeModules pkgs ./package.json ./package-lock.json;

      src = pkgs.runCommandLocal "src" { } ''
        mkdir -p "$out/node_modules"
        cp -Lr ${nodeModules}/* "$out/node_modules"
        cp -L ${./package.json} "$out"
      '';

      tailwindcss = pkgs.writeShellApplication {
        name = "tailwindcss";
        text = ''
          export NODE_PATH=${src}/node_modules
          exec ${pkgs.nodejs}/bin/node ${src}/node_modules/@tailwindcss/cli/dist/index.mjs "$@"
        '';
      };

      packages = {
        formatting = treefmtEval.config.build.check self;
        tailwindcss = tailwindcss;
        default = tailwindcss;
      };

    in
    {
      packages.x86_64-linux = packages;
      checks.x86_64-linux = packages;
      formatter.x86_64-linux = treefmtEval.config.build.wrapper;
    };
}
