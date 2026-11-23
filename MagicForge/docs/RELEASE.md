# Releasing MagicForge

Two kinds of build exist:

| | Ad-hoc build | Developer ID release |
|---|---|---|
| Produced by | `Scripts/build_app.sh`, `Scripts/build_xcode.sh`, CI | `Scripts/notarize.sh` on a maintainer's Mac |
| Signature | Ad-hoc (`-`) | `Developer ID Application: …` + secure timestamp |
| Notarized | No | Yes, ticket stapled to the DMG |
| First launch | Blocked by Gatekeeper until overridden | Opens normally |
| Permissions after update | Must be re-granted | Kept (stable code identity) |
| Needs | Nothing | Paid Apple Developer Program membership |

The Developer ID path below is implemented in `Scripts/notarize.sh` but has not been run
against Apple's notary service for this app; record the first real run in
[PROGRESS.md](PROGRESS.md).

## Versioning

- The version lives in one place: `Resources/Version.xcconfig`.
  - `MARKETING_VERSION`: user-visible version (`CFBundleShortVersionString`), semantic
    versioning `MAJOR.MINOR.PATCH`.
  - `CURRENT_PROJECT_VERSION`: build number (`CFBundleVersion`), an integer that increases
    with every released build.
- The Xcode target uses the file as its base configuration; the scripts read it directly.
  `MF_VERSION` and `MF_BUILD_NUMBER` override it for one invocation.
- The configuration file format has its own schema version, independent of the app version
  ([PROFILES.md](PROFILES.md)).
- Tag releases `vMAJOR.MINOR.PATCH` on the commit that changed the version file.

## One-time setup for Developer ID releases

1. Join the Apple Developer Program and create a **Developer ID Application** certificate
   (Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates, or the developer website). Confirm it
   is in your login keychain:

   ```sh
   security find-identity -v -p codesigning
   ```

2. Create an app-specific password for your Apple ID (account.apple.com ▸ Sign-In and
   Security) and store notarization credentials in the keychain:

   ```sh
   xcrun notarytool store-credentials "magicforge-notary" \
     --apple-id "you@example.com" --team-id "TEAMID" --password "<app-specific password>"
   ```

   An App Store Connect API key works too (`--key`, `--key-id`, `--issuer`). Nothing is
   stored in the repository.

## Release procedure

1. Update `Resources/Version.xcconfig`; commit.
2. Make sure CI is green for that commit and the manual checklist in
   [TESTING.md](TESTING.md) has been run for the release.
3. Build, sign, notarize and staple:

   ```sh
   export DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)"
   export NOTARY_PROFILE="magicforge-notary"
   Scripts/notarize.sh
   ```

   The script refuses to run unless both variables are set and the identity is a Developer
   ID Application identity. It then:

   1. builds the app signed with that identity, hardened runtime and a secure timestamp
      (`BUILD_WITH=xcode`, the default, gives a universal build with compiled assets;
      `BUILD_WITH=spm` uses `UNIVERSAL=1 Scripts/build_app.sh`);
   2. checks the signature: Developer ID authority, `runtime` flag, timestamp;
   3. creates `dist/MagicForge-<version>.dmg` (`Scripts/make_dmg.sh`) and signs the DMG;
   4. submits it with `xcrun notarytool submit --keychain-profile … --wait`;
   5. staples the ticket (`xcrun stapler staple`) and validates it;
   6. runs a Gatekeeper assessment (`spctl --assess`).

   `SKIP_BUILD=1` notarizes an existing, already Developer ID signed `dist/MagicForge.app`.

4. Verify on a different Mac (or a fresh user account) by downloading the DMG, so it carries
   the quarantine flag: it must open without a Gatekeeper override.

   ```sh
   spctl --assess --type execute --verbose=4 /Applications/MagicForge.app
   codesign -dvv --entitlements - /Applications/MagicForge.app
   xcrun stapler validate MagicForge-<version>.dmg
   ```

5. Tag the commit and publish the DMG with its SHA-256 (`shasum -a 256 dist/*.dmg`).

### If notarization fails

```sh
xcrun notarytool history --keychain-profile "magicforge-notary"
xcrun notarytool log <submission-id> --keychain-profile "magicforge-notary"
```

The log lists each rejected file and the reason. The usual causes are a missing hardened
runtime, a missing secure timestamp, or a non-Developer-ID signature; the script checks all
three before submitting. Notarization scans for malware and checks signing requirements; it
is not App Review. Whether the notary service objects to this particular app is not known
until a submission has been made.

## Switching the project to Developer ID signing

The committed project is ad-hoc (`CODE_SIGN_STYLE = Manual`, `CODE_SIGN_IDENTITY = -`,
empty `DEVELOPMENT_TEAM`) so it builds without an account. For a release, do not edit the
project; pass the identity on the command line, which is what the scripts do:

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" DEVELOPMENT_TEAM=TEAMID \
  Scripts/build_xcode.sh
```

This overrides `CODE_SIGN_IDENTITY` and `DEVELOPMENT_TEAM` and adds
`OTHER_CODE_SIGN_FLAGS=--timestamp`. To make another identity the default instead, change
`TARGET_SETTINGS` in `Scripts/lib/project_spec.rb` and regenerate the project
([BUILD.md](BUILD.md)).

## Entitlements and hardened runtime

Releases keep the hardened runtime with exactly one entitlement,
`com.apple.security.automation.apple-events`. No runtime exceptions (JIT, unsigned
executable memory, disabled library validation) are requested: the private framework is a
system library signed by Apple, which library validation allows. If a future change seems
to need an exception, treat that as a design problem first.

## CI artifacts are not releases

CI uploads ad-hoc signed DMGs and zipped app bundles for testing. They are not notarized
and must not be published as releases.
