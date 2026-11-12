# In-app updates

PloegShot uses Sparkle 2.10.1. The menu has **Check for Updates…**, and Settings →
About shows the installed version, a manual check button, and update preferences.
Automatic checks default to daily. Automatic download and installation are opt-in.
Sparkle persists preferences and handles download progress, errors, signature
validation, installation, and relaunch.

Both the feed and update archive are signed with Ed25519. The app verifies the
archive before extraction. The public key is in `Info.plist`; the private key is in
this Mac's login Keychain under account `nl.ploegshot.PloegShot`. No private key is
committed. Keep a secure backup of that Keychain item before moving to another Mac.
Do not generate a different key for an existing app, as installed copies would
reject updates signed with it.

Command-line SwiftPM builds cannot update themselves. The updater starts only in
a configured `.app` bundle, after the design-preview launch path has returned.
Preview mode does not start update checks or write update preferences.

## Implementation plan and status

- [x] Add a pinned Sparkle dependency to SwiftPM and the Xcode app target.
- [x] Start one updater on normal app launch, with HTTPS and signature validation.
- [x] Add menu and Settings controls, with availability driven by Sparkle.
- [x] Make version and build numbers configurable during packaging.
- [x] Add local release preparation, signed feed generation, archive verification,
  and manual-install DMG packaging.
- [x] Add tests for invalid feeds, public keys, and build numbers.
- [ ] Publish the first release containing this updater and its `appcast.xml`.
- [ ] Install that release manually once on existing installations.

The implementation passes 22 unit tests and builds successfully with the Xcode
Release target. A local app copy also passes deep code-signature verification.
Release preparation reached archive signing, but macOS Keychain denied the
release tool access to the private key. Release signing was deferred at the
owner's request. Signed archive/feed verification and a full install-and-relaunch
smoke test have therefore not been completed. No release was published.

## Prepare a release

Keep `PloegKit` next to this repository, as described in the README. Run tests:

```sh
swift test
```

Choose a three-part display version and an increasing numeric build. Sparkle
compares the build, so every published update must have a higher build number,
even when the display version is the same. The default build in the project is
`2026102601`. For example, the next build could be `2026102602`.

For a Developer ID signed and notarized release, install a Developer ID Application
certificate, configure a `notarytool` Keychain profile, then run:

```sh
DEVELOPMENT_TEAM=YOUR_TEAM_ID NOTARY_PROFILE=PloegShot \
  ./scripts/prepare-release.sh 2026.10.26 2026102601
```

For local testing when no Apple signing certificate is available:

```sh
./scripts/prepare-release.sh 2026.10.26 2026102601 --ad-hoc
```

The ad-hoc app still has signed Sparkle updates, but is not Apple signed or
notarized. Its local-only entitlement permits loading Sparkle under the hardened
runtime. Developer ID builds do not get this entitlement. macOS may block a
downloaded ad-hoc app, so use Developer ID signing for public distribution.

The script reads the existing signing key, checks it against the public key in
`Info.plist`, builds the app, checks bundled helpers and code signatures, creates
the ZIP, generates and signs `appcast.xml`, verifies the feed signature, and
independently verifies the ZIP against the public key embedded in the app.
It also checks version, architecture, minimum macOS, archive size and download URL.
For Developer ID releases it notarizes and staples the app and DMG.

Output goes to `.build/releases/vVERSION-BUILD/`. An existing output directory is
never overwritten. The app sits next to an `assets` folder containing the ZIP,
DMG, feed, and `SHA256SUMS`. Nothing is uploaded by the preparation script.
Set `RELEASE_NOTES_FILE` to a Markdown file to supply release-specific notes.
Otherwise the script writes notes for the initial updater release.

## Publish

The permanent feed URL is:

```text
https://github.com/teunvanderploeg/PloegShot/releases/latest/download/appcast.xml
```

The feed references a version-specific ZIP URL, so an existing feed cannot
accidentally download a different archive after the latest release changes.
All stable releases must include `appcast.xml` with exactly that filename.
Do not edit the generated feed or ZIP after signing.

From a reviewed, committed source revision, create a draft containing all assets:

```sh
gh release create v2026.10.26-2026102601 \
  .build/releases/v2026.10.26-2026102601/assets/* \
  --target "$(git rev-parse HEAD)" --draft \
  --title 'PloegShot 2026.10.26' \
  --notes-file .build/releases/v2026.10.26-2026102601/release-notes.md
```

Review the release and publish it as **Latest**. With the CLI:

```sh
gh release edit v2026.10.26-2026102601 --draft=false --latest
```

Publishing a later stable release without an appcast will break the latest feed
URL. Prereleases are not served by this stable-only feed. The first public release
with the updater requires one manual installation; older apps have no updater.
The feed returns a GitHub error until the first updater release is published.

## Release smoke test

Before publishing publicly, use disposable app copies and a test HTTPS feed, with
an older build and a newer signed ZIP. Override the feed only in the test bundle,
then sign the bundle again. Never modify an installed user's app for this test.

1. Launch the older app. Check that the menu item and About controls are enabled.
2. Check manually and confirm it offers the newer build. Install and relaunch,
   then verify the displayed build and that the bundle identifier is unchanged.
3. Check again and confirm the app reports it is up to date.
4. Disable automatic checks, quit, reopen, and confirm that preference persists.
5. Test an unreachable feed and a damaged archive. The manual check should show
   an error; an invalid archive must never replace the working app.
6. Verify the final public latest feed URL and archive URL after publication.

Copy or save any captures before restarting. Capture history is held only in the
current app session, as with an ordinary quit. The updater preserves preferences
and the existing bundle identifier. Screen Recording permission retention also
depends on consistent Apple signing across releases.

See [Sparkle setup](https://sparkle-project.org/documentation/) and
[publishing updates](https://sparkle-project.org/documentation/publishing/).
