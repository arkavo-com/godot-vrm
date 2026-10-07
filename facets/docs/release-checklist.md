# Release checklist (0.1.0)

Status as of this commit. Nothing here authorizes publishing, account setup
or store submission.

| Item | Status |
|---|---|
| README, installation/uninstallation | Done (`../README.md`) |
| Five-minute tutorial | Done (`tutorial.md`, code verified by execution) |
| Public API guide | Done (`api.md`) |
| Extension/operation guide | Done (`extension-guide.md`) |
| Save compatibility policy | Done (`save-compatibility.md`) |
| Original rules | **Missing** — `rules-v0.1.md` is a placeholder until the source draft is copied in |
| Implementation decisions | Done (`decisions.md`; items marked *pending source* need review) |
| Conformance fixtures | Done (`conformance.md`) |
| Changelog | Done (`../CHANGELOG.md`) |
| Demo | Done (`../examples/night_market`) |
| Issue templates | Drafts in `issue-templates/` (move to `.github/ISSUE_TEMPLATE/` of the repository that publishes FACETS) |
| License | **Pending owner approval** (MIT recommended); see `release-notice.txt` |
| Third-party assets | None bundled (UI uses Godot's default theme and font) |
| Addon-only ZIP and example-project ZIP | `python3 tools/build_release.py` → `build/` |
| Blank-project install, plugin disabled | Verified headless (`tools/verify_clean_install.sh`) |
| Gameplay export with plugin disabled | **Not verified** (needs export templates) |
| Desktop export smoke tests (macOS, Windows, Linux) | **Not done** |
| Editor UX at normal and high display scaling | **Not inspected manually** |
| Godot Asset Library submission route and AI-disclosure policy | **Not checked**; verify on official publisher pages before distribution |
