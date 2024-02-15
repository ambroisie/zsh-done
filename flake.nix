{
  description = "A zsh plug-in to receive notifications when long processes finish";

  inputs = {
    futils = {
      type = "github";
      owner = "numtide";
      repo = "flake-utils";
      ref = "main";
    };

    nixpkgs = {
      type = "github";
      owner = "NixOS";
      repo = "nixpkgs";
      ref = "nixpkgs-unstable";
    };

    pre-commit-hooks = {
      type = "github";
      owner = "cachix";
      repo = "pre-commit-hooks.nix";
      ref = "master";
      inputs = {
        flake-utils.follows = "futils";
        nixpkgs.follows = "nixpkgs";
        nixpkgs-stable.follows = "nixpkgs";
      };
    };
  };

  outputs = { self, futils, nixpkgs, pre-commit-hooks } @ inputs:
    futils.lib.eachDefaultSystem (system:
      let
        inherit (nixpkgs) lib;
        pkgs = nixpkgs.legacyPackages.${system};
      in
      rec {
        checks = {
          pre-commit = pre-commit-hooks.lib.${system}.run {
            src = ./.;

            hooks = {
              nixpkgs-fmt = {
                enable = true;
              };

              shellcheck = {
                enable = true;
              };
            };
          };
        };

        devShells = {
          default = pkgs.mkShell {
            name = "zsh-done";

            inputsFrom = with self.packages.${system}; [
              zsh-done
            ];

            inherit (self.checks.${system}.pre-commit) shellHook;
          };
        };

        packages = {
          default = packages.zsh-done;

          zsh-done = pkgs.stdenvNoCC.mkDerivation rec {
            pname = "zsh-done";
            version = "0.1.1";

            src = ./done.plugin.zsh;

            dontUnpack = true;

            dontConfigure = true;

            dontBuild = true;

            installPhase = ''
              plugindir="$out/share/zsh/site-functions"

              mkdir -p $plugindir
              cp $src $plugindir/done.plugin.zsh
            '';

            meta = with pkgs.lib; {
              description = ''
                A zsh plug-in to receive notifications when long processes finish
              '';
              homepage = "https://gitea.belanyi.fr/ambroisie/zsh-done";
              license = licenses.mit;
              platforms = platforms.unix;
              maintainers = with maintainers; [ ambroisie ];
            };
          };
        };
      }
    );
}
