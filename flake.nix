{
  description = "Ada + GtkAda development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nix-ada.url = "github:andrewathalye/nix-ada";
  };

  outputs = { self, nixpkgs, nix-ada }:
  let
    system = "x86_64-linux";
    # nixpkgs without the ada overlay — for non-Ada deps
    pkgs = import nixpkgs { inherit system; };
    # nix-ada's package set (has .pkgs with gnat/gprbuild from overlay, plus .gtkada)
    ada = nix-ada.packages.${system};
  in
  {
    devShells.${system}.default = pkgs.mkShell {
      buildInputs = [
        # GNAT + GPRBuild come from nix-ada's overlay, accessed via .pkgs
        ada.pkgs.gnat
        ada.pkgs.gprbuild

        # GtkAda is a direct package in nix-ada's default.nix (Tier A)
        ada.gtkada

        # Non-Ada deps from your own nixpkgs
        pkgs.pkg-config
        pkgs.gtk3
      ];

      shellHook = ''
        echo "Ada dev shell — GNAT + GtkAda"
        gprbuild --version
        # Find and set GPR_PROJECT_PATH for GtkAda
        GTKADA_GPR=$(find ${ada.gtkada} -name "gtkada.gpr" -printf "%h\n" -quit 2>/dev/null)
        if [ -n "$GTKADA_GPR" ]; then
          export GPR_PROJECT_PATH="$GTKADA_GPR:$GPR_PROJECT_PATH"
          echo "GPR_PROJECT_PATH set to: $GPR_PROJECT_PATH"
        else
          echo "WARNING: gtkada.gpr not found in ${ada.gtkada}"
        fi
      '';
    };
  };
}
