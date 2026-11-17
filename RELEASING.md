# Releasing Unified Dev

What a release takes, written from what was measured on 11 October 2026 proving the pipeline end
to end against a real Developer ID, rather than from what ought to be true.

A release is a macOS app a stranger downloads and opens. That means four things have to be true
of the bundle: it is signed with a Developer ID, the hardened runtime is on, Apple has notarised
it, and the ticket is stapled to it. Without all four, macOS refuses to open it without the
person going several clicks into System Settings, Privacy and Security. The last three are
checked by `Tools/release/package-app.sh` before it says it is done; the first is checked in full
only by the `spctl` assessment at the end.

There is one copy of that sequence, in `Tools/release/package-app.sh`. `Tools/release.sh` calls
it and so does `.github/workflows/release.yml`, on purpose: a local release and a CI release
signing differently is the kind of difference nobody notices until a user cannot open the app.

## The certificate

A **Developer ID Application** certificate, issued to team `ZF76N8225L`, valid until
**1 February 2027**. It needs a paid Apple Developer membership. Xcode, Settings, Accounts, pick
the team, Manage Certificates, plus, Developer ID Application.

The team and the date are not in this repository, so read them back off the certificate rather
than trusting this file once it is a year old:

```bash
security find-certificate -c 'Developer ID Application' -p | openssl x509 -noout -subject -dates
```

To see what this Mac holds at all:

```bash
security find-identity -v -p codesigning
```

An **Apple Development** certificate is not the one you want. That one signs for the machine it
was made on, and Apple will not notarise anything signed with it. `package-app.sh` refuses it up
front, but only when the identity is given as a name: the test is a prefix match on the string,
so an Apple Development certificate given as a fingerprint gets past it and fails later, at
notarisation or at `spctl`.

### When it expires

Issue another one. **Do not revoke the old one.** Every release already published was signed with
a trusted timestamp, so it keeps opening after the certificate behind it expires; that is what
the `--timestamp` flag in `package-app.sh` buys. Revoking is what breaks apps already in people's
hands, because revocation is not bounded by time the way expiry is. An expired certificate simply
stops signing anything new, which is all you want.

## The signing identity, and why it is a fingerprint

`UD_CODESIGN_IDENTITY` locally and the `APPLE_SIGNING_IDENTITY` secret in CI hold the
certificate's **SHA-1 fingerprint**, not its name. The name works as well, and the head of
`Tools/release/package-app.sh` says so, but the fingerprint is the value that cannot be
misspelt or re-encoded on its way to `codesign`.

A name that carries a character outside ASCII used to reach `codesign` mangled. Measured, with a
real certificate:

```
==> signing with the hardened runtime
    Contents/MacOS/sleep-helper
Developer ID Application: Kidiatoliny Gon√ßalves (ZF76N8225L): no identity found
```

`codesign` decodes its arguments in the encoding `__CF_USER_TEXT_ENCODING` names, and that is Mac
Roman unless it says otherwise, so the UTF-8 bytes of `ç` were read as `√ß`.
`Tools/release/codesign-identity.sh` exports a UTF-8 encoding before anything is signed, and
`Tools/release/tests/codesign-identity.sh` passes an accented name through `codesign` both ways to
prove it. When no identity matches, `package-app.sh` stops before the build and prints what it
searched for and what the keychain holds, each with its bytes, so a mangled name shows as one.

`APPLE_SIGNING_IDENTITY` is **optional**, and that is the trap. When it is unset the workflow
falls back to what `Tools/release/keychain.sh` reports after importing the certificate, which is
the quoted **name**. So an empty secret does not fail the build; it silently puts CI back on the
path that breaks.

Read it from the line `security find-identity` prints: the forty hex characters before the quoted
name.

```bash
security find-identity -v -p codesigning | grep 'Developer ID Application'
```

```
  2) 1234...CDEF "Developer ID Application: Your Name (ZF76N8225L)"
     ^ this
```

## The notarisation credential

`Tools/release/package-app.sh` takes one of three, tried in this order. None of them is ever
printed.

| Shape | Variables | Where it is used |
| --- | --- | --- |
| App Store Connect API key | `UD_NOTARY_KEY` (path to the `.p8`), `UD_NOTARY_KEY_ID`, `UD_NOTARY_ISSUER` | nothing stores it on the machine and it can be revoked on its own |
| Apple ID and app specific password | `UD_NOTARY_APPLE_ID`, `UD_NOTARY_PASSWORD`, `UD_NOTARY_TEAM_ID` | this is what CI uses |
| Stored keychain profile | `UD_NOTARY_PROFILE`, defaulting to `unifieddev` | this is the local shape |

One more variable is read and is easy to miss: `UD_ENTITLEMENTS`, a path to an entitlements
plist, defaulting to `Resources/Unified Dev.entitlements` when that file exists. It does not
exist, so today nothing is signed with entitlements. Adding that file is all it takes to change
that, with no edit to the script.

The notarisation credential is stored once, with an app specific password made at
appleid.apple.com:

```bash
xcrun notarytool store-credentials unifieddev --apple-id you@example.com --team-id ZF76N8225L --password <app-specific>
```

Neither setting up the certificate nor storing the credential can be scripted here, because both
are bound to an Apple ID and both need a person at the keyboard. That is why they are written
down instead.

## What CI needs

| Secret | What it holds | Checked before the build |
| --- | --- | --- |
| `APPLE_CERTIFICATE` | base64 of the exported `.p12` | yes |
| `APPLE_CERTIFICATE_PASSWORD` | the password it was exported with | yes |
| `APPLE_ID` | the Apple ID that notarises | yes |
| `APPLE_PASSWORD` | an app specific password for it | yes |
| `APPLE_TEAM_ID` | `ZF76N8225L` | yes |
| `APPLE_SIGNING_IDENTITY` | the certificate's SHA-1 fingerprint, for the reason above | **no** |

The `Check everything needed is configured` step runs before the toolchain and the build, and
loops over the first five. A missing one of those costs a second rather than a build. The sixth
is not in that loop, for the reason in the previous section.

Two more are optional. `RELEASE_TOKEN` lets the changelog commit push to a protected branch, and
`DISCORD` is the webhook the release is announced on.

`Tools/release/keychain.sh` makes a keychain that exists only for the length of the job, imports
the `.p12` into it with the partition list set so `codesign` is not left waiting for a
confirmation dialog nobody will ever see, and deletes it in a step that runs even when the build
failed. It refuses to run outside CI, because importing a certificate and rearranging the
keychain search list on somebody's own machine is not a thing a release script should do by
accident. `UD_ALLOW_KEYCHAIN_OUTSIDE_CI` opts out of that refusal, and the reason it exists is to
test the script rather than to use it.

## Proving it locally

This is the command that proved the pipeline, and it is the one to run before trusting a change
to any of it. It publishes nothing.

```bash
UD_CODESIGN_IDENTITY=<fingerprint> UD_NOTARY_PROFILE=<profile> ./Tools/release.sh --tag v1.0.0 --no-dmg
```

`--tag` stamps the version and nothing else. The commit is a positional argument, defaulting to
`HEAD`, so the command above builds what is checked out; `./Tools/release.sh v1.0.0 --tag v1.0.0`
builds the tag.

It adds a detached worktree at that commit, so nothing uncommitted and nothing from a concurrent
build can reach something being sent to another person, stamps the version, signs every nested
piece before the bundle itself with the hardened runtime on, verifies, zips with `ditto`, sends
it to Apple, waits, staples the ticket onto the app, zips again and leaves the result in `dist/`.

The line that says it worked is the `spctl` assessment, a few lines before the end:

```
dist/...: accepted
source=Notarized Developer ID
```

`--no-dmg` skips the disk image, which doubles the notarisation wait. Leave it off when the image
itself is what you are checking.

### What it checks that is easy to get wrong

- The notarisation **status**, not the exit code. `notarytool` exits 0 for a submission it
  accepted, waited on, and was told was Invalid, so the JSON decides.
- The ticket is stapled to the app and the app is zipped **again** afterwards. Without that, the
  receiver has to be online the first time they open it.
- The disk image carries a notarisation ticket of its own, and stapling the app inside it does
  not put one there. Gatekeeper assesses the file that was downloaded.
- The image is assessed with `--type open` rather than `--type execute`, because a disk image is
  a document being opened. Assessing the app inside instead passes happily on an image that was
  never notarised.

## The asset name is a contract

The workflow publishes `unified_dev_<version>_aarch64.zip`, and that is exactly the name the
updater in an installed copy looks for. It is built once in `SoftwareUpdate.assetName(for:)` and
once in the `Sign, notarise and staple` step of `.github/workflows/release.yml`.

**If one of the two changes, the other changes in the same pull request.** A release whose zip is
named anything else is a release every installed copy reports as having no download for this Mac,
and it will say so for as long as it stays the latest release.

The disk image, `unified_dev_<version>_aarch64.dmg`, is the artefact a person downloads from the
website, with the artwork and the drag to Applications window. The zip holds the same signed and
stapled bundle, and is what the updater takes.

## Publishing

Pushing a tag is what publishes, and only a tag shaped `v1.2.3` or `v1.2.3-something` starts the
workflow at all. Anything else is pushed and ignored.

The version is not chosen, it is derived, with the same arguments the workflow uses:

```bash
git-cliff --config cliff.toml --use-branch-tags --bumped-version
```

The workflow refuses a stable tag that disagrees with that. One wrinkle: `cliff.toml` skips
`docs`, `style`, `test`, `ci` and `chore`, so a range of nothing else derives the version that is
already released, and the workflow then expects the patch above it instead. Its error message
says which tag it wanted.

A breaking commit, `feat!:` or a `BREAKING CHANGE:` footer, derives the next major, so mark a
commit breaking only when somebody running a published release would feel the break. Undoing work
that no release carried does not count, and neither does a database migrated by a newer release
that an older one then refuses: that is a downgrade warning in the release notes, not a break.
The owner decides when the next major comes.

A commit already on a release branch that was marked breaking by mistake is excused by name in
`commit_preprocessors` in `cliff.toml`, which rewrites that one message before git-cliff reads it,
and it is then listed as what it is. Four are excused so far. `870b8712` (#434) undid #374, which
never shipped. `f1c119b8` and `5f328fed` (#460) removed `CodexAccount.isExpired`, the `now`
parameter of `codexDetails`, `AgentAccountEnvironment.givesADirectory` and an initialiser of
`AgentAccountPanel.Owner`, all of them internal to `Core` with no caller outside this repository,
so nobody running v1.1.3 feels anything: the `!` was the habit of a published library applied to a
target that is not one. `2ef4dd81` (#498) keeps the owner's browser panes out of the agents' tools,
and v1.2.1 shipped it as a fix under a reworded message: an agent losing a pane it was never meant to
reach is the defect being fixed, not a break for anybody running the app, and the commit body says
what agents now have to do instead. `Tools/release/tests/breaking-bump.sh` holds both halves, that each excused
commit derives no major and that any other break after a 1.x tag still derives 2.0.0, and the
`lint` job runs it.

An excuse is for a mistake already merged, not a way to keep marking commits breaking and waving
them through. Removing a symbol nothing outside the repository can import is not a break in the
first place, and the commit should say so before it lands.

A tag carrying a prerelease part, `v1.0.0-rc.1`, skips the version check and publishes as a
GitHub prerelease, which installed copies never offer.

Tags are cut on the release branch `release/X.Y.Z`, on `main`, or on a maintenance line `N.x`.
Never on `develop` or a work branch. What the workflow actually tests is that the tagged commit
is contained in one of those branches, and it only tests it on a tag push, so a rebuild by hand
never applies it.

```bash
git tag v1.0.0 && git push origin v1.0.0
```

Then watch it, with `gh run watch`. The `target` job pins the commit the tag names, and the `tests`
job runs `.github/workflows/test.yml` on that commit. Nothing else starts until its `lint`, `build`
and `test` jobs have all passed there. On a tag push a red answer stops that run before it creates a
draft, so the version number is not spent: fix the branch, then force the unpublished tag onto the
fixed commit and force push it, which starts a new run. A run by hand tests the tag it was given in
the same way, but its draft and changelog commit already exist. The `release` job builds that same
pinned commit, and refuses to attach or publish if the tag has moved since.

The `changelog` job regenerates `CHANGELOG.md` from
`cliff.toml`, commits it back to the line the tag was cut on unless that line already carries a
newer release, and creates the GitHub Release as a draft with that tag's own notes. The `release` job builds on a macOS 26 runner, signs, notarises, staples,
attaches both the zip and the disk image, and only then publishes the draft.

The order is forced. Immutable Releases is on for this repository, so a release is sealed the moment
it is published and an upload to it answers `HTTP 422: Cannot upload assets to an immutable release`.
A run that fails after the `tests` job leaves a draft nobody else can see, though the tag and the
changelog commit are already public.

Do not delete or move a published tag. To finish a tag whose release is still a draft, run the
workflow by hand with `workflow_dispatch` and that tag; it attaches the files and publishes without
touching the changelog. It publishes as not Latest, so set that by hand with
`gh release edit <tag> --latest` when the tag is the newest stable one. A published release cannot
take new files, so a broken one is followed by a new version. `gh run rerun <id> --failed` on a run whose release is
already published skips the upload with a warning and carries on to the announcement. A full rerun
stops at the changelog job, which refuses to replace a published release.

## When it goes wrong

- **`No signing identity matches UD_CODESIGN_IDENTITY`.** Compare the two byte lines it prints,
  or use the fingerprint. See above.
- **Notarisation comes back `Invalid`.** The script prints Apple's submission log, which is the
  only thing that says which file was objected to. Without it the failure is a single word.
- **The build fails before anything is signed.** `Tools/release.sh` captures the compile into
  `/tmp/unifieddev-release-build.log` and prints it, because `swift build` reports errors on
  stdout and the old bare redirect threw away the only account of a failed release build.
- **`spctl` says anything other than accepted.** Do not publish it. Something in the four steps
  did not happen, and the zip reaching people unnotarised is worse than a release that did not
  happen, because the second one is obvious.
