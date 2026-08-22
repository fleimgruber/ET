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
        # Alire toolchain
        pkgs.alire

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
          # The packaged GtkAda ALI files are built with Nix's GNAT 15,
          # while this crate intentionally selects native GNAT 13. Rebuild
          # GtkAda into the writable workspace so its ALIs match the crate.
          GTKADA_LOCAL="$PWD/build/gtkada"
          mkdir -p "$GTKADA_LOCAL"
          sed \
            -e "s#../../include/gtkada/gtkada.relocatable/gtkada/#${ada.gtkada}/include/gtkada/gtkada.relocatable/gtkada/#" \
            -e "s#../../lib/gtkada/gtkada.relocatable/gtkada/#$GTKADA_LOCAL/lib/#" \
            -e 's/for Externally_Built use "True"/for Externally_Built use "False"/' \
            "$GTKADA_GPR/gtkada.gpr" > "$GTKADA_LOCAL/gtkada.gpr"
          export GPR_PROJECT_PATH="$GTKADA_LOCAL:$GTKADA_GPR:$GPR_PROJECT_PATH"
          echo "GPR_PROJECT_PATH set to: $GPR_PROJECT_PATH"
        else
          echo "WARNING: gtkada.gpr not found in ${ada.gtkada}"
        fi

        # Alire's GNAT invokes its own GCC directly, bypassing the Nix GCC
        # wrapper's usual libc search flags.  Make the startup objects and
        # libgcc visible so `alr build` can link on NixOS.
        export LIBRARY_PATH="$(dirname "$(gcc -print-file-name=Scrt1.o)"):$(dirname "$(gcc -print-file-name=libgcc_s.so)"):$(dirname "$(gcc -print-file-name=libgcc.a)"):''${LIBRARY_PATH:-}"
        # GtkAda's generated C units are rebuilt in the workspace below;
        # expose both the Nix GCC headers and GTK3's pkg-config include dirs.
        export C_INCLUDE_PATH="$(gcc -print-file-name=include):$(pkg-config --cflags-only-I gtk+-3.0 | sed 's/-I//g; s/ /:/g')''${C_INCLUDE_PATH:+:$C_INCLUDE_PATH}"
        echo "LIBRARY_PATH and C_INCLUDE_PATH set for Alire's linker"

        # The manifest keeps gnat_native for reproducible native/Windows
        # builds.  On Nix, use the external GNAT supplied by this shell.
        # Do not run `alr toolchain --select` here: tool detection happens
        # before the shell hook has established the final Nix PATH.
        export GTKADA_BUILD=relocatable
      '';
    };
  };
}
