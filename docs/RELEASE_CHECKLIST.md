# Checklist before distributing a LiveContainer IPA

This source repository is a checked-in starting point. Do **not** claim device compatibility before the below is completed on a Mac/iPhone.

- [ ] `swift test` passes.
- [ ] Xcode app target builds without SDK API errors for generic iOS device.
- [ ] App has real code signature or a verified LiveContainer JIT-less signing path.
- [ ] iOS 27.0.1 launch in compatible LiveContainer; check `Spoof SDK Version` and file picker fix if necessary.
- [ ] No JIT/private entitlement needed; verify runtime without network.
- [ ] Save one link with UTM, one note with Cyrillic; verify FTS and duplicate detection.
- [ ] Import screenshot with Cyrillic text from PhotosPicker; test OCR results in search.
- [ ] Import PNG, JPEG/HEIC, PDF with text layer, TXT through Files.
- [ ] Edit title/note/tags/favorite and relaunch; data is preserved.
- [ ] Export JSON with attachments, restore into separate fresh guest container, verify data.
- [ ] Test backup error, invalid JSON, missing attachment, insufficient storage.
- [ ] Run UI with largest Dynamic Type and VoiceOver; test dark/light mode.
- [ ] Test memory and scroll performance for hundreds of records.
- [ ] Upgrade an existing v0.2 database, check inbox, favorites, attachments and archive; keep an exported backup before first launch.
- [ ] LiveContainer 3.8+ Share Extension: share a Safari page and a supported file to ReFind One with the guest stopped and already running.
- [ ] Confirm incoming link, cancel a draft, share a duplicate link, and send another item while a draft is open.
- [ ] Check search while the keyboard is visible, archive/favorite swipes, unsaved edit confirmation, and full attachment previews.
- [ ] Confirm release tag, VERSION, GitHub Release, GHCR package and main all reference the intended version.
- [ ] Warn user: backups unencrypted, LiveContainer guest sandboxes not mutually isolated.
- [ ] Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`; include SHA-256 and release notes.
