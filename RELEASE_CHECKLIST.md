# Release Checklist

Use this checklist before creating or updating the public GitHub repository.

## Source release

- [x] Use a public repository for the open-source project.
- [x] Publish Research Atlas source code under Apache-2.0, independently of third-party notices.
- [ ] Run `Scripts/verify-public-repository.sh`.
- [ ] Run `swift run ResearchAtlasChecks` with the compatible SDK described in `TESTING.md`.
- [ ] Build the complete Swift package on a clean checkout.
- [ ] Review `git status --ignored` and confirm `Backups/`, `Exports/`, `sources/`, `Build/`, `.build/`, private tutorial originals, model weights, credentials, and local benchmark captures remain ignored.
- [ ] Inspect every public screenshot for private paths, unpublished research, notifications, or surrounding desktop content.
- [ ] Confirm the baseline benchmark report contains only the deterministic synthetic corpus and machine characteristics you are willing to publish.
- [ ] Review the initial commit before adding a remote.
- [ ] Push, then confirm the GitHub Actions workflow passes without repository secrets.
- [ ] Enable private vulnerability reporting and reference `SECURITY.md`.

## Binary release

The source repository can be published without attaching application binaries. Before publishing installers for macOS, Windows, or Linux:

- [ ] Run `npm ci`, `npm run check`, and `npm test` in `Desktop/` using Node.js 24.15 or newer.
- [ ] Confirm the universal-desktop workflow passes on macOS, Windows, and Linux.
- [ ] Install each generated package on a clean target-system account: DMG on macOS, Squirrel Setup.exe on Windows, DEB on Ubuntu/Debian, and RPM on Fedora/RHEL.
- [ ] Verify first launch, folder indexing, PDF rendering, search, record editing, backup/export, local AI, a hosted test request using a dedicated non-production key, and credential removal on every platform.
- [ ] Sign the Windows installer and executables with the release code-signing certificate. Verify the Authenticode chain and SmartScreen-facing publisher name.
- [ ] Sign the macOS app with Developer ID, enable hardened runtime, notarize the DMG, and staple the ticket.
- [ ] Confirm Linux persistent credential storage with GNOME Keyring and KWallet; confirm Research Atlas refuses Electron's `basic_text` fallback and offers session-only storage.
- [ ] Generate and ship the complete third-party licence inventory from the exact `package-lock.json` used for the release.
- [ ] Confirm `Desktop/out/make/SHA256SUMS.txt` contains every installer and portable archive, then publish it unchanged with the release.
- [ ] Confirm the in-app and `INSTALL.md` instructions match the filenames and system requirements in the release.

Before publishing the separate native Swift `.app`:

- [ ] Build from a clean tagged commit with a known Ollama version from a supported installation. Reject a runtime resolved from the Trash or an unverified local copy.
- [ ] Archive the exact Ollama and llama.cpp/ggml notices, including all version-specific vendored-component notices.
- [ ] Use a Developer ID signing identity and review the hardened-runtime and entitlement configuration.
- [ ] With production signing available, reassess the current application-only legacy Keychain ACL and migrate to the modern data-protection Keychain/access-group design if the signing entitlements support it.
- [ ] Notarize and staple the application.
- [ ] Verify the final signature, notarization ticket, bundle identifier, version, and included resources.
- [ ] Test first launch, folder selection, backup/restore, Keychain behaviour, and local-AI startup in a clean macOS account.
- [ ] Confirm no model weight, database, export, credential, personal path, or private screenshot is present in the distributable.
- [ ] Publish checksums for the final archive.
