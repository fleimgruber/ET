# Building ET on Windows

ET's GUI depends on GtkAda. On Windows, GtkAda is **not** fetched as an
Alire dependency — see the notes below on why. Instead, use AdaCore's old
prebuilt "GtkAda without compiler" binary bundle for the Ada bindings,
MSYS2's actively-maintained GTK3 for the C runtime, and a specific
`gnat_native` version pinned in `alire.toml`.

## 1. Install the GtkAda bundle (Ada bindings)

Download and silently install AdaCore's GtkAda 2021 Windows binary bundle:

```powershell
$url = "https://community.download.adacore.com/v1/e014a610f25fef7a0093c9e9b76bd72c15421094?filename=gtkada-2021-x86_64-windows64-bin.exe&rand=1180"
Invoke-WebRequest -Uri $url -OutFile "$env:TEMP\gtkada-2021-x86_64-windows64-bin.exe"
Start-Process -FilePath "$env:TEMP\gtkada-2021-x86_64-windows64-bin.exe" -ArgumentList "/S", "/D=C:\opt\GtkAda" -Wait
```

This installs a full GTK3 + GtkAda tree under `C:\opt\GtkAda`, independent
of any compiler — but its own bundled GTK3 runtime is from 2021. We only
use this bundle for GtkAda's **Ada source** (`staging/src`); the actual
GTK3 C library comes from MSYS2 instead (next step).

## 2. Install MSYS2's GTK3

Requires an existing MSYS2 install. Run this from an **MSYS2 shell**
(`pacman` isn't on a plain PowerShell `PATH`):

```bash
pacman -S --needed mingw-w64-x86_64-gtk3
```

## 3. Set environment variables before building

(In the same PowerShell session you'll run `alr build` from.)

```powershell
$env:GPR_PROJECT_PATH = "C:\opt\GtkAda\staging\src"
$msys = "C:\msys64\mingw64"   # adjust to your MSYS2 install location
$env:C_INCLUDE_PATH = "$msys\include\gtk-3.0;$msys\include\glib-2.0;$msys\lib\glib-2.0\include;$msys\include\pango-1.0;$msys\include\cairo;$msys\include\gdk-pixbuf-2.0;$msys\include\atk-1.0;$msys\include\harfbuzz"
$env:LIBRARY_PATH = "$msys\lib"
```

Notes:

- Use `GPR_PROJECT_PATH`, not `ADA_PROJECT_PATH`, to locate `gtkada.gpr`.
  The bundle ships a `staging/src/gnat.adc` with
  `pragma Restrictions (No_Implementation_Attributes);` declared as a
  tree-wide `Global_Configuration_Pragmas` in `shared.gpr` (which
  `gtkada.gpr` inherits its `Builder` package from). `et.gpr` overrides
  this back to an empty `gnat.adc` since it's the main project, but
  there's no reason to also invite `ADA_PROJECT_PATH`/`ADA_INCLUDE_PATH`'s
  legacy config-file search semantics.
- Use `LIBRARY_PATH` (an environment variable), **not** a `-L` switch
  added via `et.gpr`'s `Linker` package. This matters a lot — see the
  "Two hard-won lessons" section below.

## 4. Build

```powershell
alr build
```

`alire.toml` pins `gnat_native = "~13.2"`. GNAT 16.1.0 (Alire's current
default) has an Ada front-end regression rejecting a legal accessibility
pattern (implicit conversion of an anonymous access *controlling*
parameter to a named access type) used by both GtkAda's and ET's own
code; 13.x is the newest version confirmed to compile both cleanly.

The resulting executable is at `src/et/bin/et.exe`.

## 5. Bundle the runtime DLLs (needed to double-click `et.exe`)

`et.exe` won't find its DLLs via a plain double-click unless
`C:\msys64\mingw64\bin` happens to be on the system `PATH` *and* nothing
else on `PATH` ships a conflicting same-named DLL (e.g. an older
`libstdc++-6.dll` — Windows resolves DLL names by search order, not by
version, so whichever one it finds first wins, correct or not, and
mismatched C++ runtime DLLs fail with cryptic
"entry point not found" errors at startup). The robust fix is to copy the
DLLs directly next to `et.exe`, since Windows always checks the
executable's own directory before `PATH`:

```powershell
$msys = "C:\msys64\mingw64"   # same path as step 3
Copy-Item "$msys\bin\*.dll" "src\et\bin\"

# et.exe was compiled by gnat_native 13.2.2, not by MSYS2's own GCC —
# its C++ runtime DLLs must come from the same toolchain that produced
# it, not from MSYS2, or you'll hit the same kind of mismatch this step
# is meant to avoid. Overwrite these two specifically:
$gnat = "$env:LOCALAPPDATA\alire\cache\toolchains\gnat_native_13.2.2_*"
Copy-Item "$gnat\bin\libgcc_s_seh-1.dll","$gnat\bin\libstdc++-6.dll" "src\et\bin\" -Force
```

After this, `src\et\bin\et.exe` runs standalone — no `PATH` changes
needed at runtime.

## Two hard-won lessons

**1. Don't "fix" the missing legacy CRT symbols with stub definitions.**

`gnat_native` 13.x-15.x's Windows release ships a `crt2.o` that references
two removed legacy mingw-w64 symbols (`_gnu_exception_handler`,
`__mingw_oldexcpt_handler`). The instinct is to supply empty stub
definitions for them to satisfy the linker — **don't**. They aren't dead
code: providing broken/empty implementations corrupts the process's
exception-handling/CRT startup state, causing the resulting executable to
hang or crash silently and non-deterministically *during Ada package
elaboration*, before any user code (even `Ada.Text_IO.Put_Line`) runs.
This is exactly what an unrelated-looking symptom like "the app never
returns" turns out to be — not a GUI event loop working as designed, and
not a bug in GtkAda or ET, but corrupted CRT init from this stub.

The actual fix: don't add these stubs, and don't add your own `Linker`
package `-L` switch either (see next point) — GNAT 13.2.2's own default
library search order already resolves these symbols correctly on its own,
and adding an explicit `-L` for MSYS2's `lib` directory earlier on
the command line hides that working default before it's ever consulted
(reproducing the exact same missing-symbol link error the stubs were
trying to paper over).

**2. Use the `LIBRARY_PATH` environment variable, not a GPR `Linker`
switch, to add MSYS2's GTK3 import libraries.**

An explicit `-L<path>` added via `et.gpr`'s `Linker` package is placed
early on the link command line and takes priority over the toolchain's
own built-in library search dirs for *every* symbol resolution — not just
the GTK ones you actually want it for. This is what caused the
corrupted-CRT-symbol scenario above. `LIBRARY_PATH` behaves differently
enough in practice to sidestep this: it makes MSYS2's GTK3 libraries
resolvable without preventing the toolchain from finding its own
already-correct C runtime pieces first.

## Switch syntax

ET's own command-line switches use **double dashes**
(`--create-project`, `--open-project`, `--version`, ...) — run
`et.exe --help` to see the full list.
