# Compatibility

| Item | Status |
|---|---|
| Godot baseline | **4.7.2-stable** (official build `4.7.2.stable.official.ed1daf0bf`, the latest stable release on 2026-10-07). CI downloads `Godot_v4.7.2-stable_linux.x86_64.zip` and verifies its SHA-512. `project.godot` declares the `4.7` feature. |
| Additional tested version | **4.6.3-stable** (official build `4.6.3.stable.official.7d41c59c4`), the 4.6 baseline the brief originally chose. The same import, parse check, 138 tests, editor self-test and clean-install check pass (`verification/godot-4.6.3.txt`). CI runs the full Godot pipeline on both versions; 4.6.3 is claimed only while that job passes. The 4.6 editor may warn that the project was saved with a newer version. Other 4.x versions are not claimed. |
| Binary invocation verified | `Godot_v4.7.2-stable_linux.x86_64` and `Godot_v4.6.3-stable_linux.x86_64` on Linux x86_64. The brief's `godot` commands work with that binary substituted for `godot`: `--headless --path . --editor --import` (exit 0) and `--headless --path . --script tests/run_tests.gd` (exit 0 on success, 1 on any failure). |
| Language | Typed GDScript only. No engine fork, C++ module or GDExtension. |
| Platforms tested | Linux x86_64 (headless, and the demo under Xvfb with the OpenGL Compatibility renderer on Mesa llvmpipe). **macOS and Windows have not been tested**; desktop export smoke tests on macOS, Windows and Linux are still required before claiming those platforms. |
| Export | Gameplay export with the editor plugin disabled has **not** been verified (no export templates in the build environment). The clean-install check verifies that core runs in a blank project without the plugin. |
| Editor UX | Verified headless (plugin load, enable/disable cycles, undo/redo). Manual inspection at normal and high display scaling has **not** been done. |
| Atomic saves | `FacetsFileStore` writes a temporary file, validates it, keeps `.bak` and renames over the save. Atomic replacement is verified on Linux only; confirm `DirAccess.rename_absolute` semantics on Windows before claiming it there. |
| Determinism | Rules arithmetic, probability and replay are deterministic everywhere (integers only; replay uses recorded ops and dice). Seeded RNG reproducibility is only claimed for the pinned 4.7.2 build. |
| Performance | Measured on the build container (Linux x86_64, Godot 4.7.2 headless): the full suite of 138 tests runs in about 8 seconds. No NPC throughput target is promised. |

Adding another Godot version: add it to the CI matrix with its official
SHA-512, run the full pipeline, and record the result here before claiming
it. Moving the baseline means changing D-001, `project.godot`'s
`config/features`, the core pack's compatibility note and the matrix's
`baseline` flag.
