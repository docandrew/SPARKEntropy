{
  description = "Reproducible SPARKEntropy build and test environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            packages = with pkgs; [
              alire
              bash
              bzip2
              coreutils
              findutils
              gcc
              gmp
              git
              gnugrep
              gnused
              gnumake
              jsoncpp
              libdivsufsort
              mpfr
              openssl
              pkg-config
              which
            ];

            shellHook = ''
              echo "SPARKEntropy dev shell: use ci/check.sh for the reproducible CI lane."
            '';
          };
        }
      );
    };
}
