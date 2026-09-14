# Updates and release quality

Codex Meter uses Sparkle 2.10.0 to discover, download, authenticate and install
updates. The app checks the stable GitHub release feed every four hours while it is
running. Automatic checks can be disabled in Settings; manual checks remain available.

## What the user sees

A new version adds a reminder to the menu bar and the app panel. If macOS permits
notifications, the app posts a notification once per build. Clicking it opens Sparkle's
release window. The user chooses installation; Sparkle downloads and verifies the
archive, replaces the app and relaunches it. Tasks and payments remain in Application
Support. Updating Meter does not stop a Codex task running in another process.

System notification delivery depends on macOS permissions and Focus settings. The
in-app reminder is also available. Offline machines discover updates on a later
successful check; this is polling, not an instantaneous broadcast to all users.

Versions through 1.3.2 cannot discover updates. Those users must manually install an
updater-enabled version once. Current releases are not Apple-notarized: first launch
may require per-app approval by macOS. Sparkle's Ed25519 signatures authenticate
updates but are not a replacement for Apple Developer ID.

## Authentication and failure behavior

- The updater uses HTTPS and a public key embedded in the installed app.
- Both `appcast.xml` and ZIP archives are signed with Ed25519. Verification of the
  feed never expires; archives are verified before extraction.
- The feed points to a version-specific GitHub Release asset, never a mutable ZIP URL.
- A corrupt archive, forged feed or failed download does not replace the installed app.
- Sparkle compares increasing build numbers and rejects the same or older build.
- Automatic installation and system profiling are disabled.
- Signing keys are stored outside the repository. The developer key is held in macOS
  Keychain; CI reads `SPARKLE_PRIVATE_KEY` from the `release` GitHub environment.

Keep an offline backup of the signing key in a password manager or secure backup.
Losing it is serious: without Developer ID, unattended key rotation cannot be assumed.
Never replace the public key casually; existing clients trust the key they installed.

## Required quality pipeline

`Quality` runs on pushes to main and on pull requests. `Release` runs the same quality
workflow again for its exact commit before publishing. Both Apple Silicon (`macos-15`)
and Intel (`macos-15-intel`) runners build a universal app and execute:

| Gate | Failure it detects |
| --- | --- |
| Core checks | Accounting, partial coverage, time overlap, imports, task lifecycle and forecasts. |
| RPC checks | Transient failure, retry limit, authentication failure and broken connection. |
| Schema-v1 upgrade fixture | Existing tasks, payments, bindings and token totals remain readable; editing a task preserves unrelated rows. |
| Native UI checks | Selection, sorting, filtering, window navigation, layout and editing regressions. |
| Release tests | Wrong application identity or origin, missing signature requirements, inconsistent versions, mutable download URLs and invalid metadata. |
| Real Sparkle installation | Download, archive verification, actual app replacement, relaunch and preserved synthetic database rows. |
| Adversarial update scenarios | Corrupt archive, forged feed, unavailable feed, interrupted download, wrong signing key, unsupported macOS, same version and downgrade. |
| Bundle and source checks | Invalid code signatures and accidental publication of private/generated material. |

Native UI and installer tests require a graphical macOS session. Their failure blocks
a release; the workflow does not replace them with a passing placeholder. Logs and
synthetic screenshots are retained as Actions artifacts for 14 days. Tests exercise
specific scenarios, not a guarantee that every possible regression is impossible.

The installation harness uses a small isolated app linked to the same pinned Sparkle
and MeterCore, with temporary keys and data. It verifies every stored row before and
after relaunch. This does not simulate Gatekeeper approval on a new user's computer.

## Publish a release

1. Merge a reviewed change with passing checks into `main`.
2. Increase `CFBundleShortVersionString` and the integer `CFBundleVersion` in `Info.plist`.
   Add meaningful notes in `releases/vX.Y.Z.md`; merge these changes as well.
3. Push a matching version tag, or run **Actions → Release → Run workflow** on main.
   For example, after updating the source to the next version:

   ```sh
   git tag v1.4.1
   git push origin v1.4.1
   ```

4. Wait for both quality jobs and the publish job to succeed. A tag alone is not proof
   of a published update. The release job checks that the commit belongs to main,
   verifies the bundle matches the source and requires increasing version/build values.
5. Check the published release and its `appcast.xml`, ZIP, `SHA256SUMS` and `release.json`.
   The manifest records the exact source commit, architectures and archive checksum.

The publish job downloads the bundle produced by the quality job; it does not rebuild
it. It signs the ZIP and feed using a key supplied over stdin, creates a draft release,
uploads all assets, then publishes it as latest. Until that final step, existing users
continue to see the previous release. Concurrent stable releases are serialized.

The first setup requires the maintainer to create the `release` environment and its
`SPARKLE_PRIVATE_KEY` secret. Do not expose the key to pull request jobs. Pin Actions and
Sparkle artifacts; review dependency upgrades before changing their checksums.

## Recovery

If checks fail, repair the change and rerun them; do not weaken the gate. If upload
fails, inspect the retained draft. A retry must not overwrite an existing published
version; use a new version/build or remove only the incomplete draft after investigation.

If a published update has a functional regression, remove it from discovery by marking
the previous verified release as latest, then ship a fix with a higher build number.
Already-updated clients will not automatically downgrade. Database format changes must
remain backward compatible with supported versions or include a separately tested
migration and backup plan. Do not restore an older database over newer user work.

Future Apple Developer ID signing/notarization can be added to the packaging stage,
but it must happen before the bundle is tested and signed for release. The current
pipeline does not claim notarization or upload to Apple.
