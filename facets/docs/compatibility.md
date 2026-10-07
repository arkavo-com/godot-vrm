# Compatibility

| Item | Status |
|---|---|
| Godot baseline | **4.6.3-stable** (official build `4.6.3.stable.official.7d41c59c4`). CI downloads `Godot_v4.6.3-stable_linux.x86_64.zip` and verifies its SHA-512. No other Godot version is claimed. |
| Binary invocation verified | `Godot_v4.6.3-stable_linux.x86_64` on Linux x86_64. The brief's `godot` commands work with that binary substituted for `godot`: `--headless --path . --editor --import` (exit 0) and `--headless --path . --script tests/run_tests.gd` (exit 0 on success, 1 on any failure). |
| Language | Typed GDScript only. No engine fork, C++ module or GDExtension. |
| Platforms tested | Linux x86_64 (headless, and the demo under Xvfb with the OpenGL Compatibility renderer on Mesa llvmpipe). **macOS and Windows have not been tested**; desktop export smoke tests on macOS, Windows and Linux are still required before claiming those platforms. |
| Export | Gameplay export with the editor plugin disabled has **not** been verified (no export templates in the build environment). The clean-install check verifies that core runs in a blank project without the plugin. |
| Editor UX | Verified headless (plugin load, enable/disable cycles, undo/redo). Manual inspection at normal and high display scaling has **not** been done. |
| Atomic saves | `FacetsFileStore` writes a temporary file, validates it, keeps `.bak` and renames over the save. Atomic replacement is verified on Linux only; confirm `DirAccess.rename_absolute` semantics on Windows before claiming it there. |
| Determinism | Rules arithmetic, probability and replay are deterministic everywhere (integers only; replay uses recorded ops and dice). Seeded RNG reproducibility is only claimed for the pinned 4.6.3 build. |
| Performance | Measured on the build container (Linux x86_64, Godot 4.6.3 headless): the full suite of 138 tests runs in about 8 seconds. No NPC throughput target is promised. |

Adding another Godot version: run the full CI pipeline against it and record
the result here before claiming it.
