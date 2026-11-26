# The release script and its runbook: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One command, `scripts/release.sh <version>`, turns a clean `main` into a copy of MacMosh that a stranger can download and open without a warning: built and signed by `scripts/build-app.sh`, checked, notarized by Apple, stapled, checked by Gatekeeper, zipped, checked again from the zip, with a checksum. It publishes nothing; it prints the commands the owner may approve. `docs/releasing.md` is the owner's runbook.

**Architecture:** `release.sh` is bash. It refuses early (wrong version, no signing identity, no notary profile, not a clean `main` equal to `origin/main`, tag already there), then calls `scripts/build-app.sh --into dist/release/<version>`, a new option that builds into that folder instead of `dist/MacMosh.app`. It checks the signed app, makes the upload zip with `ditto`, sends it with `xcrun notarytool submit --wait`, keeps Apple's log, staples, asks `spctl`, makes `MacMosh-<version>.zip` from the stapled app, unpacks it into a `mktemp` folder, checks that copy, and writes the `.sha256`. `--rehearsal` does everything up to the upload zip, on any branch, and sends nothing. Tests run a copy of the script in a throwaway repository with stand-in tools first on `PATH`. The script itself has no test-only branch.

**Tech Stack:** bash 3.2 (`/bin/bash`), git, Apple's `codesign`, `lipo`, `ditto`, `plutil`, `spctl`, `shasum`, and `xcrun notarytool` and `xcrun stapler` from Xcode. Swift Testing for the tests.

**Spec:** issue #36 (Task 33 of `docs/superpowers/plans/2026-11-19-macmosh-v1.md`); design `docs/superpowers/specs/2026-11-18-macmosh-v1-design.md` section 11 and its source 24; the coordinator's decisions of 2026-11-26 (the brief for this plan).

## Global Constraints

- **Branch:** `release/36-release-script`, never `main`. Tests first, one commit per task, a change after review is a new commit (no amend, no rebase).
- **Only these paths change:** `scripts/release.sh` (new, mode 100755), `scripts/build-app.sh`, `scripts/check.sh`, `Tests/MacMoshHostTests/Support/ReleaseHarness.swift` (new), `Tests/MacMoshHostTests/ReleaseScriptTests.swift` (new), `Tests/MacMoshKitTests/AppBundleTests.swift`, `docs/releasing.md` (new). Not `docs/build-log.md`, the README, any workflow, or anything under `Sources/`.
- **Shell:** `#!/bin/bash` with `set -euo pipefail`. `/bin/bash` is 3.2: no empty arrays under `set -u`, no `mapfile`, no `${var,,}`.
- **Tools by bare name:** `release.sh` calls `codesign`, `lipo`, `ditto`, `plutil`, `spctl`, `shasum`, `git` and `xcrun` by name, never by `/usr/bin/...`, and runs `scripts/build-app.sh` relative to the repository root it `cd`s to (`cd "$(dirname "$0")/.."`). `PATH` alone decides which tool runs.
- **Exit codes:** 0 for a finished release or rehearsal; 1 for every refusal and every failed check; 2 for a usage error.
- **Message prefixes:** `release.sh: refused: ` before anything is built; `release.sh: stopped: ` after. Each is one sentence on stderr. Progress lines go to stdout and start `release.sh: `.
- **The version** is read with build-app.sh's own line: `sed -n 's/^ *public static let version = "\([0-9][0-9.]*\)".*/\1/p' Sources/MacMoshKit/MacMoshKit.swift` (0.1.0 today). The tag is `v<version>`.
- **Output:** `dist/release/<version>/`, or `dist/rehearsal/<version>/` for a rehearsal. Never `/Applications`, never `dist/MacMosh.app`. Outside the checkout only one `mktemp -d -t macmosh-release` folder, which the script moves to `"$HOME/.Trash/"` itself on exit. No `rm` in `release.sh`.
- **Secrets:** the value of `MACMOSH_SIGN_IDENTITY` is never printed. `codesign --display` and `spctl` output (it names the certificate's owner) goes to files in the output folder only; the terminal gets the verdict and the `source=` line. The phrase "Developer ID" followed by "Application:" and a space appears in no tracked file (`theSigningIdentityIsNeverInTheRepo`).
- **Never run by the script:** `git tag`, `git push`, `gh`, `notarytool store-credentials`, `notarytool history`, `security`, `codesign --sign`, `defaults write` (`theDarkIconStyleIsTriedOnlyOnTheRunner` scans every file under `scripts/` for the last).
- **Notary wait:** `--wait --timeout 30m` (Apple: most within 5 minutes, 98 percent within 15).
- **Tests never reach out:** `PATH` is `<harness>/stubs:/usr/bin:/bin:/usr/sbin:/sbin`; `HOME` and `TMPDIR` are inside the harness folder; `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`; `MACMOSH_SIGN_IDENTITY="Stand-in Signer (TEAM000000)"` and `MACMOSH_NOTARY_PROFILE=stand-in-profile` override the person's own values. Every tool that could sign, reach Apple, read the keychain or publish is a stand-in.
- **On this Mac** the builder runs `scripts/build-app.sh` only with `--adhoc` (Task 1, once), never `release.sh` outside the tests, and never with a signing identity.
- **Placeholders only:** alex, Workhorse, Attic; the sample home is `/Users/sample`.
- **Gate:** `scripts/check.sh` gains two lines, `echo "check.sh: shellcheck scripts/release.sh"` and `shellcheck scripts/release.sh` (Task 2). It runs no rehearsal, and no workflow job is added.

## Review Focus

Five conditions no listed test exercises, most likely first.

1. **Today's release binaries contain "/Users/".** A read of the current signed `dist/MacMosh.app` on this Mac found over a hundred such strings in `Contents/MacOS/MacMosh` (build and source folders under the builder's home, from `.build/out/Intermediates.noindex` and `Sources/`) and some in `Contents/Helpers/macmosh` (swift-argument-parser's checkout). So the first real rehearsal will stop at that check. The stop and its words are pinned by Task 3 `aFailedCheckStopsBeforeAnythingIsSent` (`home-path`). The fix is a separate issue (open point 1).
2. **notarytool's real output is not Apple's example.** The script reads the first ` id: ` line and the last ` status: ` line of the normal output. Apple shows those lines, but nothing shows them with `--no-progress` or after `--timeout`. A different shape gives an empty status, which stops the script safely but wrongly. Task 4 `aNotaryProblemBeforeAnAnswerStops` (`notary-unfinished`) pins the empty-status path; the first real run settles the rest.
3. **A keychain prompt waits for a click nobody sees,** for the signing key (inside `build-app.sh`) or for the notary profile (at `submit`). `--timeout` covers only the wait after the upload. Task 5's runbook says the owner is at the Mac for every real run, and `theRunbookKeepsTheSecretOffEveryCommandLine` checks that the runbook says so.
4. **A browser download carries the quarantine flag, and a `ditto -x` copy does not.** The script's last checks run on a copy that never saw a browser. Only issue #36's done-when test, a download on a Mac with no MacMosh, shows the first-open dialog a stranger gets. Task 4 `theDownloadedCopyIsCheckedToo` covers the `ditto` copy only.
5. **`--into` on a real build.** Tests read `build-app.sh` and run its refusals. They never run its build. A slip in `app="$into/MacMosh.app"` or a stray `dist/MacMosh.app` would show first in a real rehearsal. Task 1 `theBuildScriptBuildsIntoAFolderUnderDist`, and Task 1 Step 4's one `--adhoc --into` build, which checks that `dist/MacMosh.app` keeps its time.

## Decisions on the plan's open points

The coordinator fills this in.

## What the reading settled (this Mac, macOS 27.3, 2026-11-26, read only)

- The signed `dist/MacMosh.app`, read with `codesign --display --verbose=2` (only these lines kept): both the app and `Contents/Helpers/macmosh` have a line `CodeDirectory v=20500 … flags=0x10000(runtime) …` and a line starting `Timestamp=`; `Format=app bundle with Mach-O thin (arm64)`; `lipo -archs` prints `arm64` for both.
- `codesign --display --entitlements - --xml` on the app and on the command each gives a plist with only `com.apple.security.automation.apple-events`. Passed through `plutil -convert xml1 -o -`, it is byte for byte `App/MacMosh.entitlements` passed through the same command. That is the comparison Task 3 uses.
- `spctl --assess --type execute -vv` says `rejected` and `source=Unnotarized Developer ID` for that app, and `accepted` and `source=Notarized Developer ID` for a third-party notarized app in `/Applications`.
- `plutil -extract issues raw -o - <log.json>` prints the number of issues in a notary-style log, and `issues.0.message` one of them, even with a JSON `null` elsewhere in the file. If it fails, the script counts no issues. A commit made with `user.email=alex` works, so the harness needs no address.

## Sources (read 2026-11-26; quote again, read on the day, in the pull request)

| Fact | Quote | Where |
|---|---|---|
| Upload zip | `/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"` | https://developer.apple.com/documentation/security/customizing-the-notarization-workflow |
| Submit | `xcrun notarytool submit OvernightTextEditor_11.6.8.zip --keychain-profile "notarytool-password" --wait`; "--timeout <duration> Optional time limit for 'wait'. notarytool will exit after polling for <duration>. The Notary service will continue processing even if the timeout is reached."; "Examples: '3600', '60m', '1h'"; "--progress/--no-progress" | same page; `xcrun notarytool submit --help` (notarytool 1.1.4) |
| Its answer | "id: 2efe2717-…", then after waiting "status: Accepted" | same page |
| The log | `xcrun notarytool log 2efe2717-… --keychain-profile "notarytool-password" developer_log.json`; `"issues": [ { "message": …, "path": …, "severity": "error" } ]`; "Always check the log file, even if notarization succeeds" | same page; `notarytool log --help`: "USAGE: notarytool log [<options>] <submission-id> <output-path>" |
| Staple, and why a new zip | `xcrun stapler staple "Overnight TextEditor.app"`; "While you can notarize a ZIP archive, you can't staple to it directly. Instead, run stapler against each item that you added to the archive. Then create a new ZIP file containing the stapled items for distribution." | same page |
| Validate | "stapler validate [-q] [-v] path"; "stapler returns 0 on successful stapling or validation." | `man stapler` |
| How long | "Notarization completes for most software within 5 minutes, and for 98 percent of software within 15 minutes."; "Limit notarizations to 75 per day." | same page |
| What notarization needs | "Enable the Hardened Runtime capability for your app and command line targets"; "Include a secure timestamp with your code-signing signature."; "Don't include the com.apple.security.get-task-allow entitlement" | https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution |
| Reading the timestamp | `codesign -dvv /path/to/binary/or/bundle`; "the output of this command includes a Timestamp value with a corresponding date. Alternatively, the presence of Signed Time in the output indicates the binary doesn't have a secure timestamp." | https://developer.apple.com/documentation/security/resolving-common-notarization-issues |
| Verify, entitlements | "When verifying a bundle, this option specifies that any nested code content will be recursively verified"; `codesign --display --entitlements - --xml +1337` | `man codesign` |
| Gatekeeper | "-t, --type … execute to assess code execution"; "If an assessment operation results in denial but no other problem has occurred, the exit code is three." | `man spctl` |
| Architectures | "-archs Display only the architecture names present in a single input file." | `man lipo` |
| Unpack | "ditto -x [-z \| -j \| -k] … src_archive ... dst_directory"; "-k Create or extract from a PKZip archive" | `man ditto` |
| Checksum | "SHA-256 checksum of the file downloaded from url as calculated by the command shasum -a 256 <file>" | https://docs.brew.sh/Cask-Cookbook; `shasum --help`: "-a, --algorithm 1 (default), 224, 256, …" |
| Storing the credential | "Leave credential options not specified for interactive prompts."; "You will be given a secure prompt on the command line if Apple ID and Team ID are provided and '--password' option is not specified."; "--validate/--no-validate … (default: true)"; "--sync Make the new profile synchronize … with iCloud Keychain" | `xcrun notarytool store-credentials --help` |
| Two kinds of credential | "To generate and use app-specific passwords, your Apple Account must be protected with two-factor authentication"; "Any time you change or reset your primary Apple Account password, all of your app-specific passwords are revoked automatically"; "Individual keys aren't able to use … notaryTool"; "To generate team keys, you must have an Admin account in App Store Connect."; "The private key is available for download a single time" | https://support.apple.com/en-us/102654 ; https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api |
| Printed draft command | "-d, --draft … Save the release as a draft instead of publishing it"; "--verify-tag … Abort in case the git tag doesn't already exist in the remote repository"; "--generate-notes" | `gh release create --help` (gh 2.105.0) |
| Cask lines | `depends_on arch: :arm64`; `depends_on formula: "unar"`; `depends_on macos: :monterey` ("The symbol form is used for readability"); `binary "#{appdir}/Atom.app/Contents/Resources/app/apm/bin/apm"`; desc: "what is it? Answer as a neutral third party would" | https://docs.brew.sh/Cask-Cookbook ; https://docs.brew.sh/Description-Guidelines ; `sequoia: "15"` in Homebrew 7.0.16's `Library/Homebrew/macos_version.rb` |
| Tag on origin | "--exit-code Exit with status "2" when no matching refs are found in the remote repository." | `git help ls-remote` (git 2.54.0) |

Not found: the keys of notarytool's `json` and `plist` output (so the script reads the documented normal output); notarytool's exit code for an `Invalid` answer or a timeout (so the script reads the status line and ignores the code); the versioned download address of a release asset (`…/releases/download/v<version>/<asset>`), which the printed cask uses and issue #37 checks against the draft release's real link; where Apple's pages show the Team ID (https://developer.apple.com/help/account/manage-your-team/locate-your-team-id/ renders only in a browser: the builder reads it there and quotes it in the runbook, or writes "not found").

---

### Task 1: build-app.sh builds into a folder under dist/

**Files:**
- Modify: `scripts/build-app.sh`: the header comment (lines 4-9), the argument parsing (lines 21-34), and line 39's `app=`
- Test: `Tests/MacMoshKitTests/AppBundleTests.swift`

**Interfaces** (produces, for Task 3):
- `scripts/build-app.sh [--adhoc | --debug] [--into <folder under dist/>]`. With `--into F` the app is `F/MacMosh.app`, a release build signed as today (with `MACMOSH_SIGN_IDENTITY`, or ad hoc with `--adhoc` or an empty variable). Nothing else in the script changes: `rm -rf "$app"`, the icon blocks, the sample check, the signing order and the one `codesign --verify --deep --strict` stay as they are, so `theBuildScriptCopiesTheIconBeforeItSigns` stays green unchanged.
- Parsing is a `while [ "$#" -gt 0 ]` loop, before anything else runs. Usage error, exit 2, the line `usage: scripts/build-app.sh [--adhoc | --debug] [--into <folder under dist/>]`: an unknown word, `--into` with no folder after it, or `--debug` together with `--into`. A folder that does not start with `dist/`, or has a `..` part: exit 2 with `build-app.sh: FAILED: --into takes a folder under dist/, such as dist/release/0.1.0`.

- [ ] **Step 1: Write the failing tests** (a private `runBuildScript(_:)` in the file runs `scripts/build-app.sh` with `Process`, pipes for both outputs, and waits):
```swift
/// The release script builds into dist/release/<version>, never over dist/MacMosh.app (issue #36).
@Test func theBuildScriptBuildsIntoAFolderUnderDist() throws {
    let script = try String(contentsOf: repoRoot().appendingPathComponent("scripts/build-app.sh"), encoding: .utf8)
    for part in ["usage: scripts/build-app.sh [--adhoc | --debug] [--into <folder under dist/>]", "app=\"$into/MacMosh.app\"",
                 "--into takes a folder under dist/, such as dist/release/0.1.0", "while [ \"$#\" -gt 0 ]"] {
        #expect(script.contains(part), "\(part)") }
    let parse = try #require(script.range(of: "while [ \"$#\" -gt 0 ]"))
    let version = try #require(script.range(of: "version=$(sed -n"))
    #expect(parse.lowerBound < version.lowerBound) }
/// Each refusal comes before the version read, so it builds nothing and writes nothing.
@Test func theBuildScriptRefusesABadInto() throws {
    for (arguments, line) in [(["--into", "/tmp/elsewhere"], "build-app.sh: FAILED: --into takes a folder under dist/, such as dist/release/0.1.0"),
                              (["--into", "dist/../elsewhere"], "build-app.sh: FAILED: --into takes a folder under dist/, such as dist/release/0.1.0"),
                              (["--into"], "usage: scripts/build-app.sh [--adhoc | --debug] [--into <folder under dist/>]"),
                              (["--debug", "--into", "dist/x"], "usage: scripts/build-app.sh [--adhoc | --debug] [--into <folder under dist/>]")] {
        let out = try runBuildScript(arguments)
        #expect(out.exitCode == 2 && out.stderr == line + "\n" && out.stdout.isEmpty, "\(arguments)") } }
```
- [ ] **Step 2: Run** `swift test --filter AppBundleTests` · Expected: FAIL on both new tests.
- [ ] **Step 3: Implement** the loop, the check and `app="$into/MacMosh.app"` when `--into` is given (the `--debug` line stays). Add one header line: `scripts/build-app.sh --into dist/release/0.1.0` builds and signs as the first line does, into that folder; `scripts/release.sh` uses it.
- [ ] **Step 4: Run** `swift test --filter AppBundleTests` · Expected: PASS. Then once on this Mac: note `ls -l dist/MacMosh.app/Contents/MacOS/MacMosh` (if there is one), run `scripts/build-app.sh --adhoc --into dist/into-try`, see it end `built dist/into-try/MacMosh.app (ad hoc)`, and see the first `ls -l` unchanged. Move `dist/into-try` to `~/.Trash`.
- [ ] **Step 5: Commit.** `git add scripts/build-app.sh Tests/MacMoshKitTests/AppBundleTests.swift && git commit -m "build-app.sh --into: build into a folder under dist/, for the release script"`

### Task 2: The harness, the refusals and the script's own rules

**Files:**
- Create: `scripts/release.sh` (mode 100755), `Tests/MacMoshHostTests/Support/ReleaseHarness.swift`, `Tests/MacMoshHostTests/ReleaseScriptTests.swift`
- Modify: `scripts/check.sh`: after `shellcheck scripts/build-app.sh` (line 40), add `echo "check.sh: shellcheck scripts/release.sh"` and `shellcheck scripts/release.sh`

**Interfaces.** `scripts/release.sh [--rehearsal] <version>`. Any other shape: exit 2 with `usage: scripts/release.sh [--rehearsal] <version>`. Then these checks in this order, each a `release.sh: refused: ` line and exit 1. The ones marked R are skipped in a rehearsal:

| # | Check (command) | Sentence after `release.sh: refused: ` |
|---|---|---|
| 1 | version read (the sed line) is empty | `could not read the app's version from Sources/MacMoshKit/MacMoshKit.swift.` |
| 2 | argument ≠ that version | `<arg> is not the app's version; Sources/MacMoshKit/MacMoshKit.swift says <version>.` |
| 3 | `MACMOSH_SIGN_IDENTITY` unset or empty | `MACMOSH_SIGN_IDENTITY is empty, and a release is never signed ad hoc.` |
| 4 R | `MACMOSH_NOTARY_PROFILE` unset or empty | `MACMOSH_NOTARY_PROFILE is empty; set it to the profile name you saved with notarytool store-credentials.` |
| 5 | `git status --porcelain` prints anything | `the checkout has changes that are not committed.` |
| 6 R | `git symbolic-ref --quiet --short HEAD` ≠ `main` | `the checkout is on <branch>, not main.` (`a detached HEAD` when it fails) |
| 7 R | `git fetch --quiet --no-tags origin` fails | `could not fetch origin to compare main with it.` |
| 8 R | `git rev-parse HEAD` ≠ `git rev-parse refs/remotes/origin/main` | `main here is not the same commit as origin/main.` |
| 9 R | `git rev-parse --quiet --verify refs/tags/v<version>` succeeds | `the tag v<version> already exists here.` |
| 10 R | `git ls-remote --exit-code --tags origin refs/tags/v<version>`: 0 | `the tag v<version> already exists on origin.` (any code but 0 or 2: `could not ask origin whether the tag v<version> exists.`) |
| 11 R | `dist/release/<version>` exists | `dist/release/<version> already exists; move it to the Trash to build this version again.` |

`--no-tags` keeps origin's tags out of the local check, so rows 9 and 10 each say where the tag is. In a rehearsal, an existing `dist/rehearsal/<version>` is moved to `"$HOME/.Trash/rehearsal-<version>-$(date +%Y%m%d-%H%M%S)"` (Task 3). Task 2 ends after row 11 with `exit 0` and a `# Task 3:` comment; Tasks 3 and 4 replace that comment.

**`ReleaseHarness`** (the pattern of `HostHarness`: a temporary folder, stand-ins first on `PATH`, output to files, a 60-second limit):
```swift
final class ReleaseHarness {
    let root: URL                    // <temporaryDirectory>/macmosh-release-test-<8 hex>
    var repo: URL { get }            // root/repo, the throwaway checkout; release.sh runs here
    var home: URL { get }            // root/home = HOME, so the Trash is root/home/.Trash
    var calls: [String] { get }      // root/calls.log: one line per stand-in call, "<tool> <arguments>"
    init() throws
    func run(_ arguments: [String], fault: String? = nil, environment: [String: String?] = [:])
        -> (exitCode: Int32, stdout: String, stderr: String)   // nil unsets a variable
    func git(_ arguments: [String], in folder: URL? = nil) -> (exitCode: Int32, stdout: String)
    func cleanUp()
}
```
`init` makes `root/origin.git` (`git init --bare -q -b main`) and `root/repo` (`git init -q -b main`), and writes into `repo`: a copy of the real `scripts/release.sh` (mode kept); a stand-in `scripts/build-app.sh`; `Sources/MacMoshKit/MacMoshKit.swift` holding the one line `    public static let version = "0.1.0"`; a copy of `App/MacMosh.entitlements`; and `.gitignore` holding `dist/`. It commits as alex (`GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME` and `GIT_COMMITTER_EMAIL` all `alex`), adds `origin`, and pushes `main`. The environment is the person's, minus `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE` and every `MACMOSH_*`, plus the values in Global Constraints, `HOME=root/home`, `TMPDIR=root/tmp` (no trailing slash, so `mktemp` paths read `root/tmp/macmosh-release.XXXXXXXX`), `STANDIN_LOG=root/calls.log`, and `STANDIN_FAULT` when `fault` is given. `init` creates `root/stubs`, `root/home` and `root/tmp`. Only stand-ins read `STANDIN_*`.

The stand-ins, each a `#!/bin/bash` file that first appends `"<name> $*"` to `$STANDIN_LOG` (a "copy" path is one that does not start with `dist/`, which is the `mktemp` folder):

| Stand-in | Does | Faults |
|---|---|---|
| `scripts/build-app.sh` | needs `--into F`; makes `F/MacMosh.app` with `Contents/MacOS/MacMosh` ("stand-in app"), `Contents/Helpers/macmosh` ("stand-in command"), and `Contents/Info.plist` with `CFBundleShortVersionString` 0.1.0 | `home-path` adds `/Users/sample/x` to the command; `sample-menu` adds `MACMOSH_SAMPLE_MENU` to the app; `wrong-version` writes 0.0.9 |
| `codesign` | `--verify …` exit 0. `--display --entitlements - --xml P`: prints `App/MacMosh.entitlements`. `--display --verbose=2 P`: to stderr `Executable=P`, `Authority=$MACMOSH_SIGN_IDENTITY`, `CodeDirectory v=20500 size=100 flags=0x10000(runtime) hashes=1+7 location=embedded`, `Timestamp=Nov 26, 2026 at 09:00:00`. Any `--sign` or `-s`: exit 97 | `verify-fails`; `extra-entitlement` (adds `com.apple.security.get-task-allow` true, for the bundle); `no-runtime` (`flags=0x0(none)`); `no-timestamp` (`Signed Time=…` instead); `helper-no-timestamp` (the same, for `…/Helpers/macmosh` only) |
| `lipo` | `-archs P`: `arm64` | `intel`: `x86_64 arm64` for the app |
| `ditto` | `exec /usr/bin/ditto "$@"` | |
| `xcrun` | `notarytool submit`: Apple's example, ` id: 2efe2717-0000-4000-8000-000000000036` after "Successfully uploaded file.", then `status: Accepted`. `notarytool log ID --keychain-profile P OUT`: writes to OUT `{"status":"Accepted","issues":[{"severity":"warning","path":"MacMosh.app/Contents/Helpers/macmosh","message":"stand-in warning"}]}`. `stapler staple A`: creates `A/Contents/stand-in-ticket`. `stapler validate A`: 0 when that file is there, else 65. Anything else: 97 | `notary-invalid` (status `Invalid`; log status Invalid, one `error` issue, path `MacMosh.app/Contents/MacOS/MacMosh`, message "The signature does not include a secure timestamp."); `notary-unfinished` (the upload lines only, no status); `notary-upload-fails` (`Error: stand-in upload failure`, exit 1, no id); `staple-fails` (65) |
| `spctl` | `--assess …`: stderr `P: accepted` and `source=Notarized Developer ID`, exit 0 | `gatekeeper-rejects` (`P: rejected`, `source=Unnotarized Developer ID`, exit 3); `copy-gatekeeper-rejects` (the same, copy paths only) |
| `git` | `exec /usr/bin/git "$@"` | |
| `gh`, `security` | exit 97 | |

- [ ] **Step 1: Write the failing tests** (`ReleaseScriptTests.swift`, inside `extension HostScriptTests { @Suite struct ReleaseScriptTests { … } }`, so it runs one at a time like the host tests):
```swift
private func expectRefusal(_ h: ReleaseHarness, _ arguments: [String], _ sentence: String,
                           environment: [String: String?] = [:]) {
    let out = h.run(arguments, environment: environment)
    #expect(out.exitCode == 1)
    #expect(out.stderr == "release.sh: refused: " + sentence + "\n")
    #expect(h.calls.allSatisfy { $0.hasPrefix("git ") }, "\(h.calls)") }   // nothing built, signed or sent
@Test func refusesAWrongShape() throws {
    let h = try ReleaseHarness(); defer { h.cleanUp() }
    for arguments in [[], ["0.1.0", "0.1.0"], ["--rehearse", "0.1.0"], ["--rehearsal"]] {
        let out = h.run(arguments)
        #expect(out.exitCode == 2 && out.stderr == "usage: scripts/release.sh [--rehearsal] <version>\n", "\(arguments)") } }
@Test func refusesAVersionThatIsNotTheApps() throws { let h = try ReleaseHarness(); defer { h.cleanUp() }
    expectRefusal(h, ["0.2.0"], "0.2.0 is not the app's version; Sources/MacMoshKit/MacMoshKit.swift says 0.1.0.") }
@Test func refusesWithoutASigningIdentity() throws { let h = try ReleaseHarness(); defer { h.cleanUp() }
    for value in [nil, ""] as [String?] {
        expectRefusal(h, ["0.1.0"], "MACMOSH_SIGN_IDENTITY is empty, and a release is never signed ad hoc.",
                      environment: ["MACMOSH_SIGN_IDENTITY": value])
        expectRefusal(h, ["--rehearsal", "0.1.0"], "MACMOSH_SIGN_IDENTITY is empty, and a release is never signed ad hoc.",
                      environment: ["MACMOSH_SIGN_IDENTITY": value]) } }
@Test func refusesWithoutANotaryProfile() throws { let h = try ReleaseHarness(); defer { h.cleanUp() }
    expectRefusal(h, ["0.1.0"], "MACMOSH_NOTARY_PROFILE is empty; set it to the profile name you saved with notarytool store-credentials.",
                  environment: ["MACMOSH_NOTARY_PROFILE": ""]) }
@Test func refusesUncommittedChanges() throws { let h = try ReleaseHarness(); defer { h.cleanUp() }
    try "x\n".write(to: h.repo.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
    expectRefusal(h, ["0.1.0"], "the checkout has changes that are not committed.")
    expectRefusal(h, ["--rehearsal", "0.1.0"], "the checkout has changes that are not committed.") }
/// Rows 6 to 10: a release refuses them, and a rehearsal goes on.
@Test(arguments: [
    ([["checkout", "-q", "-b", "try"]], "the checkout is on try, not main."),
    ([["commit", "-q", "--allow-empty", "-m", "not pushed"]], "main here is not the same commit as origin/main."),
    ([["tag", "v0.1.0"]], "the tag v0.1.0 already exists here."),
    ([["tag", "v0.1.0"], ["push", "-q", "origin", "v0.1.0"], ["tag", "-d", "v0.1.0"]], "the tag v0.1.0 already exists on origin.")])
func refusesWhatOnlyAReleaseNeeds(git commands: [[String]], sentence: String) throws {
    let h = try ReleaseHarness(); defer { h.cleanUp() }
    for command in commands { #expect(h.git(command).exitCode == 0, "\(command)") }
    expectRefusal(h, ["0.1.0"], sentence)
    #expect(h.run(["--rehearsal", "0.1.0"]).exitCode == 0) }
@Test func refusesAReleaseFolderThatIsThere() throws { let h = try ReleaseHarness(); defer { h.cleanUp() }
    try FileManager.default.createDirectory(at: h.repo.appendingPathComponent("dist/release/0.1.0"), withIntermediateDirectories: true)
    expectRefusal(h, ["0.1.0"], "dist/release/0.1.0 already exists; move it to the Trash to build this version again.") }
@Test func theHarnessStandsInForEveryToolThatReachesOut() throws { let h = try ReleaseHarness(); defer { h.cleanUp() }
    for tool in ["codesign", "xcrun", "spctl", "gh", "security", "lipo", "ditto", "git"] {   // a forgotten one would be real
        #expect(FileManager.default.isExecutableFile(atPath: h.root.appendingPathComponent("stubs/\(tool)").path), "\(tool)") } }
@Test func theScriptKeepsItsOwnRules() throws {
    let url = HostHarness.repoRoot().appendingPathComponent("scripts/release.sh")
    let script = try String(contentsOf: url, encoding: .utf8)
    #expect(FileManager.default.isExecutableFile(atPath: url.path) && script.hasPrefix("#!/bin/bash\n"))
    for banned in ["/usr/bin/", "STANDIN", "defaults write", "--sign", "store-credentials \"", "notarytool history"] {
        #expect(!script.contains(banned), "\(banned)") }
    #expect(script.range(of: #"(^|[\s;|&(])rm\s"#, options: .regularExpression) == nil)
    for line in script.split(separator: "\n") {
        let code = line.trimmingCharacters(in: .whitespaces)
        if code.hasPrefix("#") || code.hasPrefix("echo ") || code.hasPrefix("printf ") { continue }
        #expect(!code.hasPrefix("git tag") && !code.hasPrefix("git push") && !code.hasPrefix("gh "), "\(line)") }
    let check = try String(contentsOf: HostHarness.repoRoot().appendingPathComponent("scripts/check.sh"), encoding: .utf8)
    #expect(check.contains("\nshellcheck scripts/release.sh\n")) }
```
In Task 2 a rehearsal ends after row 11 with exit 0, so the last line of `refusesWhatOnlyAReleaseNeeds` holds from the start and keeps holding as Task 3 adds the build.
- [ ] **Step 2: Run** `swift test --filter ReleaseScriptTests` · Expected: FAIL (no `scripts/release.sh`).
- [ ] **Step 3: Implement** the harness, the stand-ins, `release.sh` up to row 11, and the `check.sh` lines. Header comment of `release.sh`: what it does, both forms, that it publishes nothing, that it reads `MACMOSH_SIGN_IDENTITY` and `MACMOSH_NOTARY_PROFILE` and never prints the first, and `docs/releasing.md`.
- [ ] **Step 4: Run** `swift test --filter ReleaseScriptTests` and `shellcheck scripts/release.sh` · Expected: PASS, no findings.
- [ ] **Step 5: Commit.** `git add scripts/release.sh scripts/check.sh Tests/MacMoshHostTests/Support/ReleaseHarness.swift Tests/MacMoshHostTests/ReleaseScriptTests.swift && git commit -m "release.sh: refuses a wrong version, missing settings, a dirty or unpushed main and an existing tag"`

### Task 3: The build, the checks before sending, and the rehearsal

**Files:** Modify `scripts/release.sh`; Test `Tests/MacMoshHostTests/ReleaseScriptTests.swift`.

**Interfaces.** `out=dist/release/<version>` (or `dist/rehearsal/<version>`), `app=$out/MacMosh.app`. In this order, each failure a `release.sh: stopped: ` sentence and exit 1:
1. Rehearsal only, when `$out` exists: `mkdir -p "$HOME/.Trash"` and `mv "$out" "$HOME/.Trash/rehearsal-<version>-$(date +%Y%m%d-%H%M%S)"`. Then `scripts/build-app.sh --into "$out"`. A non-zero exit: `scripts/build-app.sh failed; its own message is above.`
2. `codesign --verify --deep --strict --verbose=2 "$app"`: `the signature of <app> did not verify (codesign --verify --deep --strict).`
3. For `MacMosh.app` (path `$app`), then `Contents/Helpers/macmosh`: `codesign --display --entitlements - --xml <path> > $out/entitlements-<app|command>.plist`, then `plutil -convert xml1 -o - <that file>` must equal (`cmp -s` on two files) `plutil -convert xml1 -o - App/MacMosh.entitlements`: `the entitlements on <name> are not exactly those of App/MacMosh.entitlements.` Then `codesign --display --verbose=2 <path> > $out/signature-<app|command>.txt 2>&1`, never printed. Without a line matching `^CodeDirectory .*flags=0x[0-9a-f]*([^)]*runtime`: `<name> does not have the hardened runtime switched on.` Without a line starting `Timestamp=`: `<name> has no secure timestamp.`
4. For `Contents/MacOS/MacMosh`, then `Contents/Helpers/macmosh`: `lipo -archs` must print exactly `arm64`: `<name> is built for <what lipo printed>; the first release is for Apple silicon (arm64) only.` `LC_ALL=C grep -qaF /Users/` (the match is never printed): `<name> contains a folder path from the Mac that built it (the text /Users/).` `grep -qaF MACMOSH_SAMPLE_MENU`: `<name> contains MACMOSH_SAMPLE_MENU, so it is not a release build.`
5. `plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist"` must be the version: `MacMosh.app says version <found>, not <version>.`
6. Print `release.sh: checks passed: signature, entitlements, hardened runtime, timestamp, arm64 only, no /Users/, no sample menu, version <version>`.
7. `ditto -c -k --keepParent "$app" "$out/for-notary.zip"`.
8. Rehearsal only: write `$out/REHEARSAL.txt` with the sentence below, print it, exit 0: `release.sh: rehearsal finished. Nothing was sent to Apple, and nothing in dist/rehearsal/<version> is a release.`

- [ ] **Step 1: Write the failing tests:**
```swift
private let checks = ["build-app.sh --into dist/X/0.1.0",
    "codesign --verify --deep --strict --verbose=2 dist/X/0.1.0/MacMosh.app",
    "codesign --display --entitlements - --xml dist/X/0.1.0/MacMosh.app",
    "codesign --display --verbose=2 dist/X/0.1.0/MacMosh.app",
    "codesign --display --entitlements - --xml dist/X/0.1.0/MacMosh.app/Contents/Helpers/macmosh",
    "codesign --display --verbose=2 dist/X/0.1.0/MacMosh.app/Contents/Helpers/macmosh",
    "lipo -archs dist/X/0.1.0/MacMosh.app/Contents/MacOS/MacMosh",
    "lipo -archs dist/X/0.1.0/MacMosh.app/Contents/Helpers/macmosh",
    "ditto -c -k --keepParent dist/X/0.1.0/MacMosh.app dist/X/0.1.0/for-notary.zip"]
private func steps(_ h: ReleaseHarness) -> [String] { h.calls.filter { !$0.hasPrefix("git ") } }
@Test func aRehearsalSendsNothing() throws { let h = try ReleaseHarness(); defer { h.cleanUp() }
    _ = h.git(["checkout", "-q", "-b", "try"]); _ = h.git(["tag", "v0.1.0"])
    let out = h.run(["--rehearsal", "0.1.0"], environment: ["MACMOSH_NOTARY_PROFILE": nil])
    #expect(out.exitCode == 0, "\(out.stderr)")
    #expect(out.stdout.hasSuffix("release.sh: rehearsal finished. Nothing was sent to Apple, and nothing in dist/rehearsal/0.1.0 is a release.\n"))
    #expect(steps(h) == checks.map { $0.replacingOccurrences(of: "dist/X/", with: "dist/rehearsal/") })
    let folder = h.repo.appendingPathComponent("dist/rehearsal/0.1.0")
    let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    for name in ["MacMosh.app", "for-notary.zip", "REHEARSAL.txt", "signature-app.txt", "signature-command.txt"] {
        #expect(names.contains(name), "\(name)") }
    #expect(!names.contains { $0.hasPrefix("MacMosh-") || $0.hasSuffix(".sha256") })
    #expect(!FileManager.default.fileExists(atPath: h.repo.appendingPathComponent("dist/release").path)) }
@Test func aRehearsalPutsTheLastOneInTheTrash() throws { let h = try ReleaseHarness(); defer { h.cleanUp() }
    #expect(h.run(["--rehearsal", "0.1.0"]).exitCode == 0)
    #expect(h.run(["--rehearsal", "0.1.0"]).exitCode == 0)
    let trash = try FileManager.default.contentsOfDirectory(atPath: h.home.appendingPathComponent(".Trash").path)
    #expect(trash.filter { $0.hasPrefix("rehearsal-0.1.0-") }.count == 1) }
@Test(arguments: [
    ("verify-fails", "the signature of dist/release/0.1.0/MacMosh.app did not verify (codesign --verify --deep --strict)."),
    ("extra-entitlement", "the entitlements on MacMosh.app are not exactly those of App/MacMosh.entitlements."),
    ("no-runtime", "MacMosh.app does not have the hardened runtime switched on."),
    ("no-timestamp", "MacMosh.app has no secure timestamp."),
    ("helper-no-timestamp", "Contents/Helpers/macmosh has no secure timestamp."),
    ("intel", "Contents/MacOS/MacMosh is built for x86_64 arm64; the first release is for Apple silicon (arm64) only."),
    ("home-path", "Contents/Helpers/macmosh contains a folder path from the Mac that built it (the text /Users/)."),
    ("sample-menu", "Contents/MacOS/MacMosh contains MACMOSH_SAMPLE_MENU, so it is not a release build."),
    ("wrong-version", "MacMosh.app says version 0.0.9, not 0.1.0.")])
func aFailedCheckStopsBeforeAnythingIsSent(fault: String, sentence: String) throws {
    let h = try ReleaseHarness(); defer { h.cleanUp() }
    let out = h.run(["0.1.0"], fault: fault)
    #expect(out.exitCode == 1)
    #expect(out.stderr.split(separator: "\n").last.map(String.init) == "release.sh: stopped: " + sentence)
    #expect(!steps(h).contains { $0.hasPrefix("xcrun ") || $0.hasPrefix("spctl ") || $0.hasPrefix("ditto ") }) }
/// Decision 7: what names the certificate's owner stays in dist/, which git ignores.
@Test func theSigningNameStaysInDist() throws { let h = try ReleaseHarness(); defer { h.cleanUp() }
    let out = h.run(["0.1.0"])
    #expect(out.exitCode == 0, "\(out.stderr)")
    #expect(!(out.stdout + out.stderr).contains("Stand-in Signer"))
    let signature = try String(contentsOf: h.repo.appendingPathComponent("dist/release/0.1.0/signature-app.txt"), encoding: .utf8)
    #expect(signature.contains("Authority=Stand-in Signer (TEAM000000)")) }
```
`theSigningNameStaysInDist` passes only after Task 4. Until then it fails at the exit code, which is expected in this task's run.
- [ ] **Step 2: Run** `swift test --filter ReleaseScriptTests` · Expected: FAIL on the new tests.
- [ ] **Step 3: Implement** steps 1 to 8. The `mktemp` folder and its `trap … EXIT` come in Task 4.
- [ ] **Step 4: Run** `swift test --filter ReleaseScriptTests` · Expected: PASS except `theSigningNameStaysInDist`; `shellcheck scripts/release.sh` clean.
- [ ] **Step 5: Commit.** `git add scripts/release.sh Tests/MacMoshHostTests/ReleaseScriptTests.swift && git commit -m "release.sh: checks the signed app before anything is sent, and a rehearsal stops there"`

### Task 4: Sending, stapling, Gatekeeper, the zip people download, and the printout

**Files:** Modify `scripts/release.sh`; Test `Tests/MacMoshHostTests/ReleaseScriptTests.swift` (adds `import CryptoKit` for the checksum).

**Interfaces**, after Task 3's step 7, in this order:
9. `xcrun notarytool submit "$out/for-notary.zip" --keychain-profile "$MACMOSH_NOTARY_PROFILE" --wait --timeout 30m --no-progress > "$out/notary-submit.txt" 2>&1 || true`. `id` is the field after the first `^ *id: ` line, `status` the rest of the last `^ *status: ` line (`awk`). No id: stop with `notarytool could not send for-notary.zip to Apple; what it said is in <out>/notary-submit.txt.` and print that file first. An id and no status, or `In Progress`: stop with `Apple had not finished after 30 minutes; submission <id> goes on without this script. Ask later with: xcrun notarytool info <id> --keychain-profile "$MACMOSH_NOTARY_PROFILE"`. The variable is printed as written, not its value.
10. Any other status: `xcrun notarytool log "$id" --keychain-profile "$MACMOSH_NOTARY_PROFILE" "$out/notary-log.json"`. Failure: `could not download Apple's notary log for submission <id>, so nothing was stapled.` Then print `release.sh: Apple's notary log lists <n> issue(s):`, or `release.sh: Apple's notary log lists no issues.`, with one line per issue, `  <severity>: <path>: <message>`. Here n is `plutil -extract issues raw -o -` (0 when that fails), and the issue fields come from `plutil -extract issues.<i>.<key> raw -o -`. If the status is not `Accepted`: `Apple's answer is <status>, not Accepted, so nothing was stapled; the whole log is in <out>/notary-log.json.`
11. `xcrun stapler staple "$app"`: `xcrun stapler could not staple the ticket to <app>.` Then `xcrun stapler validate "$app"`: `the ticket stapled to <app> did not validate.`
12. `spctl --assess --type execute -vv "$app" > "$out/gatekeeper.txt" 2>&1`, exit 0 needed: `Gatekeeper did not accept <app> (<its source= line>); its whole answer is in <out>/gatekeeper.txt.` On success print `release.sh: Gatekeeper: accepted (<source= line>)`.
13. `ditto -c -k --keepParent "$app" "$out/MacMosh-<version>.zip"`.
14. `check=$(mktemp -d -t macmosh-release)`. A `trap` on EXIT moves it to `"$HOME/.Trash/"` (after `mkdir -p "$HOME/.Trash"`). `ditto -x -k "$out/MacMosh-<version>.zip" "$check"`, then on `$check/MacMosh.app`: `codesign --verify --deep --strict --verbose=2`, `xcrun stapler validate`, and `spctl --assess --type execute -vv > "$out/gatekeeper-download.txt" 2>&1`. A failure renames the zip `NOT-FOR-RELEASE-MacMosh-<version>.zip` and stops with `the copy unpacked from MacMosh-<version>.zip <did not verify | has no valid ticket | was not accepted by Gatekeeper (<source= line>)>, so the zip is renamed NOT-FOR-RELEASE-MacMosh-<version>.zip and has no checksum.`
15. `(cd "$out" && shasum -a 256 "MacMosh-<version>.zip") > "$out/MacMosh-<version>.zip.sha256"`.
16. Print, never run (`cat <<EOF`), with `<sha>` from the file and `<commit>` from `git rev-parse HEAD`:
```text
release.sh: done. MacMosh <version> is notarized, stapled and checked.
  zip:      dist/release/<version>/MacMosh-<version>.zip
  checksum: dist/release/<version>/MacMosh-<version>.zip.sha256 (SHA-256 <sha>)
release.sh: nothing was tagged, pushed or published. After the owner says yes, these make the tag and a draft release:
  git tag -a v<version> -m "MacMosh <version>" <commit>
  git push origin v<version>
  gh release create v<version> dist/release/<version>/MacMosh-<version>.zip dist/release/<version>/MacMosh-<version>.zip.sha256 --draft --verify-tag --title "MacMosh <version>" --generate-notes
release.sh: the cask for the tap (Casks/macmosh.rb, issue #37):
cask "macmosh" do
  version "<version>"
  sha256 "<sha>"
  url "https://github.com/shariqh/macmosh/releases/download/v#{version}/MacMosh-#{version}.zip"
  name "MacMosh"
  desc "Menu bar app for mosh and tmux sessions on another Mac"
  homepage "https://github.com/shariqh/macmosh"
  depends_on arch: :arm64
  depends_on macos: :sequoia
  depends_on formula: "mosh"
  app "MacMosh.app"
  binary "#{appdir}/MacMosh.app/Contents/Helpers/macmosh"
end
```

- [ ] **Step 1: Write the failing tests:**
```swift
private let id = "2efe2717-0000-4000-8000-000000000036"
@Test func aReleaseRunsEveryStepInOrder() throws { let h = try ReleaseHarness(); defer { h.cleanUp() }
    let out = h.run(["0.1.0"])
    #expect(out.exitCode == 0, "\(out.stderr)")
    // Decision 5: the log is kept and its issues shown even when Apple accepts.
    #expect(out.stdout.contains("release.sh: Apple's notary log lists 1 issue(s):\n  warning: MacMosh.app/Contents/Helpers/macmosh: stand-in warning\n"))
    #expect(FileManager.default.fileExists(atPath: h.repo.appendingPathComponent("dist/release/0.1.0/notary-log.json").path))
    let o = "dist/release/0.1.0"
    let expected = checks.map { $0.replacingOccurrences(of: "dist/X/", with: "dist/release/") } + [
        "xcrun notarytool submit \(o)/for-notary.zip --keychain-profile stand-in-profile --wait --timeout 30m --no-progress",
        "xcrun notarytool log \(id) --keychain-profile stand-in-profile \(o)/notary-log.json",
        "xcrun stapler staple \(o)/MacMosh.app", "xcrun stapler validate \(o)/MacMosh.app",
        "spctl --assess --type execute -vv \(o)/MacMosh.app",
        "ditto -c -k --keepParent \(o)/MacMosh.app \(o)/MacMosh-0.1.0.zip",
        "ditto -x -k \(o)/MacMosh-0.1.0.zip \(h.root.path)/tmp/macmosh-release.",
        "codesign --verify --deep --strict --verbose=2 \(h.root.path)/tmp/macmosh-release.",
        "xcrun stapler validate \(h.root.path)/tmp/macmosh-release.",
        "spctl --assess --type execute -vv \(h.root.path)/tmp/macmosh-release."]
    #expect(steps(h).count == expected.count && zip(steps(h), expected).allSatisfy { $0.hasPrefix($1) }, "\(steps(h))")
    let tmp = try FileManager.default.contentsOfDirectory(atPath: h.root.appendingPathComponent("tmp").path)
    #expect(!tmp.contains { $0.hasPrefix("macmosh-release.") })
    let trash = try FileManager.default.contentsOfDirectory(atPath: h.home.appendingPathComponent(".Trash").path)
    #expect(trash.contains { $0.hasPrefix("macmosh-release.") }) }
@Test func aNotaryAnswerOtherThanAcceptedStopsBeforeStapling() throws { let h = try ReleaseHarness(); defer { h.cleanUp() }
    let out = h.run(["0.1.0"], fault: "notary-invalid")
    #expect(out.exitCode == 1)
    #expect(out.stderr.hasSuffix("release.sh: stopped: Apple's answer is Invalid, not Accepted, so nothing was stapled; the whole log is in dist/release/0.1.0/notary-log.json.\n"))
    #expect(out.stdout.contains("  error: MacMosh.app/Contents/MacOS/MacMosh: The signature does not include a secure timestamp."))
    #expect(!steps(h).contains { $0.hasPrefix("xcrun stapler") || $0.hasPrefix("spctl") })
    #expect(!FileManager.default.fileExists(atPath: h.repo.appendingPathComponent("dist/release/0.1.0/MacMosh-0.1.0.zip").path)) }
@Test(arguments: [
    ("notary-unfinished", "Apple had not finished after 30 minutes; submission 2efe2717-0000-4000-8000-000000000036 goes on without this script. Ask later with: xcrun notarytool info 2efe2717-0000-4000-8000-000000000036 --keychain-profile \"$MACMOSH_NOTARY_PROFILE\""),
    ("notary-upload-fails", "notarytool could not send for-notary.zip to Apple; what it said is in dist/release/0.1.0/notary-submit.txt.")])
func aNotaryProblemBeforeAnAnswerStops(fault: String, sentence: String) throws {
    let h = try ReleaseHarness(); defer { h.cleanUp() }
    let out = h.run(["0.1.0"], fault: fault)
    #expect(out.exitCode == 1 && out.stderr.hasSuffix("release.sh: stopped: " + sentence + "\n"))
    #expect(!steps(h).contains { $0.hasPrefix("xcrun notarytool log") || $0.hasPrefix("xcrun stapler") }) }
@Test(arguments: [
    ("staple-fails", "xcrun stapler could not staple the ticket to dist/release/0.1.0/MacMosh.app."),
    ("gatekeeper-rejects", "Gatekeeper did not accept dist/release/0.1.0/MacMosh.app (source=Unnotarized Developer ID); its whole answer is in dist/release/0.1.0/gatekeeper.txt.")])
func aFailedStapleOrGatekeeperStopsBeforeTheZip(fault: String, sentence: String) throws {
    let h = try ReleaseHarness(); defer { h.cleanUp() }
    let out = h.run(["0.1.0"], fault: fault)
    #expect(out.exitCode == 1 && out.stderr.hasSuffix("release.sh: stopped: " + sentence + "\n"))
    #expect(!steps(h).contains { $0.contains("MacMosh-0.1.0.zip") }) }
@Test func theDownloadZipIsMadeFromTheStapledApp() throws { let h = try ReleaseHarness(); defer { h.cleanUp() }
    #expect(h.run(["0.1.0"]).exitCode == 0)
    let o = h.repo.appendingPathComponent("dist/release/0.1.0")
    func unpacked(_ zip: String) throws -> URL {
        let into = h.root.appendingPathComponent("look-\(zip)")
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", o.appendingPathComponent(zip).path, into.path]; try p.run(); p.waitUntilExit()
        return into.appendingPathComponent("MacMosh.app/Contents/stand-in-ticket") }
    #expect(FileManager.default.fileExists(atPath: try unpacked("MacMosh-0.1.0.zip").path))
    #expect(!FileManager.default.fileExists(atPath: try unpacked("for-notary.zip").path))
    let digest = SHA256.hash(data: try Data(contentsOf: o.appendingPathComponent("MacMosh-0.1.0.zip")))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    #expect(try String(contentsOf: o.appendingPathComponent("MacMosh-0.1.0.zip.sha256"), encoding: .utf8) == "\(hex)  MacMosh-0.1.0.zip\n") }
@Test func theDownloadedCopyIsCheckedToo() throws { let h = try ReleaseHarness(); defer { h.cleanUp() }
    let out = h.run(["0.1.0"], fault: "copy-gatekeeper-rejects")
    #expect(out.exitCode == 1)
    #expect(out.stderr.hasSuffix("release.sh: stopped: the copy unpacked from MacMosh-0.1.0.zip was not accepted by Gatekeeper (source=Unnotarized Developer ID), so the zip is renamed NOT-FOR-RELEASE-MacMosh-0.1.0.zip and has no checksum.\n"))
    let names = try FileManager.default.contentsOfDirectory(atPath: h.repo.appendingPathComponent("dist/release/0.1.0").path)
    #expect(names.contains("NOT-FOR-RELEASE-MacMosh-0.1.0.zip") && !names.contains("MacMosh-0.1.0.zip") && !names.contains { $0.hasSuffix(".sha256") })
    let trash = try FileManager.default.contentsOfDirectory(atPath: h.home.appendingPathComponent(".Trash").path)
    #expect(trash.contains { $0.hasPrefix("macmosh-release.") }) }
@Test func thePrintedCommandsAreNeverRun() throws { let h = try ReleaseHarness(); defer { h.cleanUp() }
    let out = h.run(["0.1.0"])
    let head = h.git(["rev-parse", "HEAD"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    let sha = try String(contentsOf: h.repo.appendingPathComponent("dist/release/0.1.0/MacMosh-0.1.0.zip.sha256"), encoding: .utf8).prefix(64)
    for line in ["  git tag -a v0.1.0 -m \"MacMosh 0.1.0\" \(head)", "  git push origin v0.1.0",
                 "  gh release create v0.1.0 dist/release/0.1.0/MacMosh-0.1.0.zip dist/release/0.1.0/MacMosh-0.1.0.zip.sha256 --draft --verify-tag --title \"MacMosh 0.1.0\" --generate-notes",
                 "  version \"0.1.0\"", "  sha256 \"\(sha)\"", "  depends_on arch: :arm64"] {
        #expect(out.stdout.contains(line + "\n"), "\(line)") }
    #expect(!h.calls.contains { $0.hasPrefix("gh ") || $0.hasPrefix("security ") || $0.hasPrefix("git tag") || $0.hasPrefix("git push") })
    #expect(h.git(["tag", "-l"]).stdout.isEmpty)
    #expect(h.git(["ls-remote", "--tags", "origin"]).stdout.isEmpty) }
```
- [ ] **Step 2: Run** `swift test --filter ReleaseScriptTests` · Expected: FAIL on the new tests and on `theSigningNameStaysInDist`.
- [ ] **Step 3: Implement** steps 9 to 16.
- [ ] **Step 4: Run** `swift test --filter ReleaseScriptTests` · Expected: PASS, all of them. `shellcheck scripts/release.sh` clean.
- [ ] **Step 5: Commit.** `git add scripts/release.sh Tests/MacMoshHostTests/ReleaseScriptTests.swift && git commit -m "release.sh: notarizes, staples, asks Gatekeeper, checks the zip people download, and prints what to publish"`

### Task 5: The runbook, docs/releasing.md

**Files:** Create `docs/releasing.md`; Test `Tests/MacMoshHostTests/ReleaseScriptTests.swift`.

**What it holds,** for the owner, in plain short sentences (through the unslop pass, compared with the draft):
1. **What a release is,** each word explained the first time it is used. *Notarization:* Apple's automatic check of the signed app for malware; it is not App Review. *Ticket and stapling:* Apple's record that the check passed, attached to the app so a Mac can see it offline. *Keychain profile:* a named entry in the Mac's keychain that holds the notary login; scripts pass only its name. *Gatekeeper:* the macOS check that runs when a downloaded app first opens. Plus what `release.sh` does, and that it publishes nothing.
2. **Once only, yours alone.** A "Which one do I use?" table: an app-specific password (needs two-factor on the Apple Account; made at account.apple.com, Sign-In and Security, App-Specific Passwords; revoked when the account password changes) against an App Store Connect team key (needs an Admin account; a team key, because individual keys cannot use notarytool; the `.p8` file downloads once and is kept outside the repository). The recommendation is the app-specific password, unless the owner's Apple Account is not on the team that owns the signing certificate. Then the numbered steps. In his own Terminal, never through an agent, he runs `xcrun notarytool store-credentials "macmosh-notary" --apple-id "<your Apple Account email>" --team-id "<your Team ID>"`, or for a key `xcrun notarytool store-credentials "macmosh-notary" --key "<path to the .p8 file>" --key-id "<key ID>" --issuer "<issuer ID>"`. He types the password at its prompt. He never adds `--password`, and never `--sync` (that copies it to iCloud Keychain). What to expect: notarytool checks the login with Apple before saving (`--validate` is on by default). Then `export MACMOSH_NOTARY_PROFILE=macmosh-notary` in the Terminal where he releases. Where the Team ID is shown: the builder's quote from Apple's page, or "not found".
3. **Each release,** numbered, with what to expect after each: the agent runs `scripts/release.sh --rehearsal <version>` on the owner's Mac, where both variables are set; the owner sits at the Mac on a clean, pushed `main` with both variables set and runs `scripts/release.sh <version>`; a keychain prompt may appear for the signing key or the profile (its wording is unproven); Apple usually answers within 5 to 15 minutes; he reads the end summary; he says yes or no to the printed tag and draft-release commands, which the coordinator runs only after that yes. Publishing the draft and the tap are separate yeses.
4. **Who does what,** a table: the agent (rehearsal, reading the output, the download test on a Mac with no MacMosh over ssh) and the owner at the Mac (the credential, the real run and any keychain prompt, every yes).
5. **If something's off,** one line per `refused:` and `stopped:` sentence of Tasks 2 to 4, saying what to do. For `/Users/`, the line says it is a known gap and names its issue.

- [ ] **Step 1: Write the failing test:**
```swift
@Test func theRunbookKeepsTheSecretOffEveryCommandLine() throws {
    let text = try String(contentsOf: HostHarness.repoRoot().appendingPathComponent("docs/releasing.md"), encoding: .utf8)
    for part in ["xcrun notarytool store-credentials \"macmosh-notary\"", "MACMOSH_NOTARY_PROFILE", "MACMOSH_SIGN_IDENTITY",
                 "scripts/release.sh --rehearsal", "Which one do I use?", "If something's off", "at the Mac"] {
        #expect(text.contains(part), "\(part)") }
    for line in text.split(separator: "\n") where line.contains("store-credentials") {
        #expect(!line.contains("--password") && !line.contains("--sync"), "\(line)") } }
```
- [ ] **Step 2: Run** `swift test --filter ReleaseScriptTests` · Expected: FAIL (no file).
- [ ] **Step 3: Write** `docs/releasing.md` as above.
- [ ] **Step 4: Run** `swift test --filter ReleaseScriptTests` and `swift test --filter AppBundleTests` · Expected: PASS (`theSigningIdentityIsNeverInTheRepo` covers the new file).
- [ ] **Step 5: Commit.** `git add docs/releasing.md Tests/MacMoshHostTests/ReleaseScriptTests.swift && git commit -m "docs/releasing.md: the owner's runbook for a release"`

### Task 6: The pull request, ready and unmerged

- [ ] **Step 1:** `scripts/check.sh` once · Expected: it prints `check.sh: shellcheck scripts/release.sh` and ends with "check.sh: all checks passed". `git diff main... --stat` lists only the seven paths of Global Constraints.
- [ ] **Step 2:** `git diff main... | ask.sh review`; answer each finding (fix it in a new commit, or say why not).
- [ ] **Step 3:** `git push -u origin release/36-release-script` and `gh pr create` with the title "Release script and runbook (issue 36)". The description (unslop pass, compared with the draft, ending with the attribution lines) says:
  - "Part of #36". Not "Closes": the issue closes after the first real run and the download test.
  - What changed, as behaviour: `--into`, `release.sh` and its two forms, the runbook. That it publishes nothing and was never run with a real identity.
  - The tests and what each proves, and how they stand in for every outside tool.
  - The Sources table, each quote copied again from the page or help read on the day.
  - Review Focus item 1 (the `/Users/` strings, with counts only, never the path) and the section below.
- [ ] **Step 4:** `gh pr checks --watch` · Expected: CI passes. Leave it unmerged for the coordinator.

## The first real run

Run by the owner at his Mac, after this pull request merges and after the `/Users/` fix. It settles:
- the exact words `spctl` prints for notarized MacMosh (a third-party notarized app gave `source=Notarized Developer ID` today);
- whether the keychain asks permission the first time `codesign` uses the signing key or `notarytool` reads the profile, and its wording, for the runbook;
- how long Apple takes, and what the notary log says about MacMosh;
- notarytool's real output with `--wait --timeout 30m --no-progress`: the ` id: ` and ` status: ` lines, and its exit code;
- whether the owner's Apple Account is on the certificate's team (the credential works) and what `store-credentials` prints;
- that the versioned asset address in the printed cask matches the draft release's link (issue #37);
- issue #36's done-when: the zip, downloaded in a browser on a Mac with no MacMosh, opens without a warning.
