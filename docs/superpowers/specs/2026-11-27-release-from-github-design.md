# Releases made on GitHub: the release workflow, its secrets and its two approvals

Status: proposed, waiting for the owner's approval. Nothing in it is built yet. Written: 2026-11-27, revised the same day after a security reading. Issues: #36 (the release) and #37 (the cask). It changes how `scripts/release.sh` (merged on 2026-11-26, rehearsed on the owner's Mac) is run, and replaces the owner's runbook `docs/releasing.md`. Section 6 names the one sentence of the v1 design (`docs/superpowers/specs/2026-11-18-macmosh-v1-design.md`) it corrects.

## 0. For the owner: what changes, what you approve, what only you can do

### What changes for you

- A release is built, signed and notarized on one of GitHub's Macs, not on yours. You start it with a button on GitHub.
- The certificate and a new Apple notary key live as secrets in a protected GitHub environment, under the names Agent Inbox uses. You put them there once, from your own Terminal.
- GitHub asks you twice per release: once before anything is signed, and once before the tag and the draft release are made.
- The release page stays a draft until you publish it, with a click, when you choose. The tag, and for one day the zip, can be seen by anyone before that. The workflow never publishes.
- Nothing is saved on your Mac: no notary login, no keychain profile. `docs/releasing.md` is rewritten for the new way.

### What you approve by approving this document

1. Approach (b) of section 2: one release workflow that you start by hand on `main`, which runs `scripts/release.sh` and is protected Agent Inbox's way, with the differences listed there.
2. An environment named `macos-release` holding six secrets (section 4), with you as its only required reviewer, set up before the workflow is merged.
3. Two approvals per release, and a draft at the end that only you publish (section 3).
4. The repository changes of section 6, including a written rule that agents never approve, reject or publish; and the trial run of section 7 before any real release.
5. The open points of section 9 as recommended, unless you change one.

**One honest limit.** GitHub checks the account, not the person. Any program signed in to GitHub as you, the agents on your Macs included, could approve a waiting job or publish a draft through GitHub's API. Today only a written rule stops them (section 5); a second GitHub account as the reviewer would make it a real lock (section 9).

### The words, one line each

- **GitHub Actions:** GitHub's service that runs scripts for a repository on GitHub's own computers. One such script is a **workflow**; it is made of **jobs**, and each job of **steps**.
- **Runner:** one of those computers. For a MacMosh release it is a fresh Mac made for one job and thrown away afterwards.
- **Environment:** a named gate in the repository's settings. It holds secrets, and a job that names it waits until a person on its list clicks "Approve and deploy".
- **Secret:** a value GitHub keeps encrypted and hands only to the jobs that ask for it. Once saved, nobody can read it back, you included.
- **Artifact:** a file one job keeps for a later job. In a public repository, anyone signed in to GitHub can download it.
- **Draft release:** a release page that is saved but not published. Only people who can push to the repository can see it.
- **gh** is GitHub's command-line tool, already on your Mac. **base64** turns a file into plain text that fits in a secret.

### What only you can do

Once, before the first release:

1. **Make the environment, before the workflow is merged.** On github.com/shariqh/macmosh open Settings, then Environments, then New environment. Name it `macos-release` and click Configure environment. Select Required reviewers, enter yourself, and leave **Prevent self-review** unticked. Deselect **Allow administrators to bypass configured protection rules**. Under Deployment branches choose Selected branches and tags, click Add deployment branch or tag rule, choose Branch, enter `main`, click Add rule, then Save protection rules. Tell the agent when it is done.
   You should see the environment with one reviewer and one branch rule, `main`. The order matters: a run that names a missing environment creates it with no protection.
2. **Make a new notary key for MacMosh.** It needs an Admin account on the company's App Store Connect team. In App Store Connect select Users and Access, then the Integrations tab, then App Store Connect API, then Team Keys. Click Generate API Key, name it "MacMosh notary", choose the **Developer** role under Access, and click Generate. Download the `.p8` file; Apple offers it once only and keeps no copy. Note the key ID shown with it, and the issuer ID you also used for Agent Inbox.
3. **Have the certificate as a `.p12` file.** Reuse the one you exported for Agent Inbox, with its password. If it is gone: open Keychain Access, select the Developer ID Application certificate together with its private key, choose File, then Export Items, pick the `.p12` file format, click Save and enter a new password. You also need your Team ID.
4. **Put in the secrets**, in your own Terminal, not through an agent. For the two files (put your own path in place of the example):

   ```
   base64 -i ~/path/to/certificate.p12 | gh secret set APPLE_DEVELOPER_ID_P12_BASE64 --env macos-release --repo shariqh/macmosh
   base64 -i ~/path/to/key.p8 | gh secret set APPLE_NOTARY_PRIVATE_KEY_BASE64 --env macos-release --repo shariqh/macmosh
   ```

   For each of the four short values, run its line; gh asks "Paste your secret:", shows nothing as you paste, and you press Return:

   ```
   gh secret set APPLE_DEVELOPER_ID_P12_PASSWORD --env macos-release --repo shariqh/macmosh
   gh secret set APPLE_NOTARY_KEY_ID --env macos-release --repo shariqh/macmosh
   gh secret set APPLE_NOTARY_ISSUER_ID --env macos-release --repo shariqh/macmosh
   gh secret set APPLE_TEAM_ID --env macos-release --repo shariqh/macmosh
   ```

   No value appears on the screen or in your shell's history, and gh encrypts each value on your Mac before sending it. Never use `--body`, which puts the value on the command line. Secrets belong to one repository, so even values you already gave Agent Inbox are entered again here.
   You should see the six names under Environment secrets on the environment's page, with no values.
5. **Approve the trial run** of section 7 when the agent starts it.

Each release:

6. **Start it.** After the version's pull requests are merged and CI is green, open the Actions tab, choose Release on the left, click Run workflow, keep the branch `main`, type the version (for example `0.1.0`), tick "Make the tag and a draft release", and click Run workflow.
   You should see a new run. Its first job, `preflight`, takes about a minute; then the run shows "Waiting" and GitHub sends you a review request.
7. **Read the summary, then approve the build.** The run's page shows `preflight`'s summary: the commit, the version, and every commit since the last release that changed the workflows or the release scripts. If one surprises you, click Reject. Otherwise click Review deployments, tick `macos-release`, and click Approve and deploy.
   You should see `build` run. It waits up to 30 minutes for Apple and ends with `release.sh: done. MacMosh <version> is notarized, stapled and checked.`
8. **Approve the tag and the draft.** A second review request comes for the job `draft`. Approve it the same way.
   You should see the run end green, with a draft release under Releases.
9. **Publish, when you choose.** Before you are asked, the agent rewrites the draft's notes and tests the download on a Mac with no MacMosh on it. Then, on the Releases page, click the pencil next to the draft and click Publish release.

### If something's off

- **No Review deployments button:** the environment's name is not exactly `macos-release`, or you are not its reviewer. Check step 1.
- **GitHub says you cannot approve a run you started:** Prevent self-review is ticked. Untick it (step 1).
- **A run is waiting that you did not start, or its summary surprises you:** click Reject. Nothing is signed.
- **`preflight` fails:** its one line says why: the run is not on `main` or not at its newest commit, CI is not green on that commit, the version is not the app's, or the tag already exists. Fix that and start again; nothing was signed.
- **`build` stops with `release.sh: refused:` or `release.sh: stopped:`:** the same messages as today, listed in `docs/releasing.md`. Nothing was tagged or published.
- **The import step says a secret is empty or the password is wrong:** set that one secret again (step 4). It names the secret, never its value.
- **Apple refuses the notary key's access:** tell the agent what the log says. Only then consider a wider role for the key.
- **The `.p12`, its password or the `.p8` shows in a log:** open the run, choose the menu at the top right, click Delete all logs, then replace it: a new `.p12` export with a new password, or a new team key with the old one revoked in App Store Connect.
- **Your name, the team ID, the key ID or the issuer ID shows in a log:** deleting the logs is optional and nothing needs replacing. The name and team are in every signed app anyway, and the two IDs are useless without the `.p8`. Tell the agent so the next run hides them.
- **`draft` fails:** do not delete or move the tag. Within a day, re-run the failed job (the zip is kept for one day). After a day, bump the version and start a new release.

## 1. Why, and what the owner chose

Asked how releases should be made, the owner wrote: "lets do it just like agent inbox." He chose this over saving a notary login on his Mac.

Agent Inbox's way, from its repository:

- Pushing an annotated `vX.Y.Z` tag starts a build with no secrets and read-only access (`.github/workflows/macos-release.yml:3-9`).
- When it finishes, a second workflow, always read from the default branch, starts and holds the secrets (`.github/workflows/macos-release-protected.yml:3-8`).
- Its first job, `authorize`, checks with no secrets that the build came from the same repository, the expected workflow and the tagged commit on `main`'s first-parent history (`macos-release-protected.yml:24-81`).
- Four jobs name the environment `macos-release`, and the guide has the owner check the run before approving each (`docs/macos-release.md:1088-1090`; `test/macos-release-workflow.test.ts:663`).
- The certificate goes into a throwaway keychain with a random password, and is always removed (`scripts/import-apple-signing.sh:66-148`).
- The notary key is written to a private temporary file inside the notarize step and passed to `notarytool` with `--key`, `--key-id` and `--issuer` (`scripts/notarize-macos.sh:19-49`).
- Only the last job may write to GitHub, with no checkout and one shell step; it makes a draft, uploads, downloads again, compares every byte, then publishes and marks the release latest by itself (`docs/macos-release.md:573-585, 663-668`).

## 2. Approaches considered

**(a) Mirror Agent Inbox's protected pipeline.** A tag push builds an unsigned app; a second workflow on `main` checks the hand-off, then signs, notarizes and publishes in separate jobs. It is the closest copy. But `scripts/build-app.sh` signs as it builds, so the build and the checks of `scripts/release.sh` would be cut into new scripts, and most of yesterday's tested and rehearsed work would be rewritten. A tag that fails can never be used again, so each failure costs a version number. Much of Agent Inbox's length is for Node, Electron, the DMG, Linux packages and update manifests, which MacMosh does not have.

**(b) The smallest workflow that runs `scripts/release.sh` on a runner, protected Agent Inbox's way.** You start one workflow by hand on `main`. A job with no secrets checks the request; a job in the `macos-release` environment imports the certificate and runs `scripts/release.sh`; a last job, the only one that may write, makes the tag and the draft. It keeps the script, its refusals, its checks and its tests. From Agent Inbox it takes the environment, the secret names, the throwaway keychain, the team key passed straight to `notarytool`, read-only defaults, one write job with one shell step, pinned actions and the draft-then-compare ending.

**(c) Keep releasing from his Mac.** Rehearsed and ready, but it needs a notary login saved on his Mac, which he decided against.

**This design takes (b).** It keeps the most of what was built and rehearsed, and it is Agent Inbox's way where the secrets live, who approves, and how the certificate and key are handled. Starting by hand on `main` instead of by a tag push means `scripts/release.sh`'s own checks (clean `main` equal to `origin/main`, no tag yet) run unchanged, and a run that fails before `draft` leaves no tag behind.

**Where it differs from Agent Inbox, on purpose:** started by hand, in one workflow, not by a tag push into two; it ends at a draft, where Agent Inbox's last approval publishes and marks the release latest; two approvals, not one per environment job (four there, if GitHub asks once per job, which its pages imply but do not say); Prevent self-review off; key ID, issuer ID and team ID as secrets, not variables; no certificate name passed in, and signing through the keychain search list rather than `codesign --keychain`; no evidence files or protected hand-off; and `main` is not yet a protected branch, where Agent Inbox's guide asks for "only the protected default branch" (`docs/macos-release.md:672-675`), so `preflight` checks CI instead and a ruleset is the owner's choice (section 9).

## 3. The release, step by step

The workflow is `.github/workflows/release.yml`, named Release. It starts only from Run workflow (`workflow_dispatch`), with two inputs: `version` and `make_draft` (a tick box, off by default). It has no other trigger. One run at a time (`concurrency`).

1. **`preflight`** (ubuntu-latest, no secrets, no environment, `contents: read` and `checks: read`). It refuses unless the run is on `refs/heads/main`, the commit is `main`'s newest, every CI check run on that commit succeeded, `version` has the shape `X.Y.Z` and equals the version in `Sources/MacMoshKit/MacMoshKit.swift` (read with `release.sh`'s own line), and the tag `v<version>` is not on GitHub. It writes the run summary: the commit, `github.workflow_sha`, the version, and the commits since the last `v*` tag (all of them, before the first release) that touched `.github/workflows/`, `scripts/release.sh`, `scripts/build-app.sh`, `scripts/import-signing.sh` or `scripts/with-notary-key.sh`. A wrong request fails here, before you are asked anything.
2. **`build`** (macos-15, environment `macos-release`): **first approval.** Steps, in order: check out the commit; resolve the Swift package and build both products with `swift build -c release`, so third-party code is compiled before any secret exists; import the certificate (section 4); run `scripts/with-notary-key.sh scripts/release.sh <version>`, which decodes the notary key, runs the release (build, sign, check, notarize, staple, Gatekeeper, zip, check the unpacked copy, checksum, print the cask) and removes the key on exit; always remove the keychain, even after a failure. When `make_draft` is ticked, it then keeps `MacMosh-<version>.zip` and its `.sha256`, and nothing else, as a one-day artifact, and reports the commit and the SHA-256 to the next job.
3. **`draft`** (macos-15, whose image ships gh, environment `macos-release`, only when `make_draft` is ticked): **second approval.** It is the only job allowed to write, and like Agent Inbox's it has no checkout, no `uses:` and one shell step, with the token only in that step's `env:`. It refuses unless the commit `build` reports equals `github.sha`; fetches the two files with `gh run download`; refuses unless their SHA-256 is the one `build` reported; makes the annotated tag `v<version>` on that commit through GitHub's REST API (an existing tag is accepted only if it points at that same commit, so a re-run can finish); runs `gh release create v<version> <zip> <sha256> --draft --verify-tag --title "MacMosh <version>, first public preview" --generate-notes`; downloads both files from the draft, compares them byte for byte, and prints the draft's address.
4. **Your click.** Publishing the draft, and adding the cask to the tap (#37), each stay your own yes. The workflow never publishes, never marks a release latest and never touches the tap.

## 4. Secrets and the environment

Six environment secrets in `macos-release`. The first three are named as in Agent Inbox; Agent Inbox keeps the other three as plain variables, and MacMosh keeps them as secrets so that GitHub hides them in logs (section 9, point 2).

| Secret | What it is | Read by |
|---|---|---|
| `APPLE_DEVELOPER_ID_P12_BASE64` | the Developer ID certificate and its private key, as base64 | `build`, import step |
| `APPLE_DEVELOPER_ID_P12_PASSWORD` | the `.p12` file's password | `build`, import step |
| `APPLE_TEAM_ID` | the developer team's ID, to check the certificate | `build`, import step |
| `APPLE_NOTARY_PRIVATE_KEY_BASE64` | MacMosh's own App Store Connect team key (`.p8`), as base64 | `build`, release step |
| `APPLE_NOTARY_KEY_ID` | that key's ID | `build`, release step |
| `APPLE_NOTARY_ISSUER_ID` | the issuer ID | `build`, release step |

Secret values reach only the steps that name them, through that step's `env:`, never the whole job. What they become lasts longer: the unlocked keychain exists from the import step until cleanup, so the release step can sign; that is why third-party code is compiled before the import. `draft` names the environment only for its approval and reads no secret. There are no repository-level secrets.

**The certificate** goes in by a new script, `scripts/import-signing.sh`, written in bash after Agent Inbox's `scripts/import-apple-signing.sh`. With `umask 077`, under `RUNNER_TEMP` (the runner's own temporary folder, outside the checkout), it decodes the `.p12` (accepting a trailing newline), makes a keychain with a random password held only in a shell variable, imports the `.p12` for `codesign`, sets the partition list so no prompt can hang the job, and puts the keychain first on the search list. It requires exactly one valid Developer ID Application identity in that keychain, and that its team is `APPLE_TEAM_ID`, saying only a count or "the team does not match". It deletes the `.p12` file at once. It does not read the identity's name: it registers the identity's 40-character SHA-1 hash with `::add-mask::`, then sets `MACMOSH_SIGN_IDENTITY` to that hash, which `codesign` accepts in place of a name. Its `cleanup`, in an `if: always()` step, restores the search list and deletes the keychain. The `.p12` password reaches `security import` on its command line (`-P`, the only way without a window), as in Agent Inbox; that is visible only inside the throwaway runner.

**The team key** is decoded by `scripts/with-notary-key.sh` inside the release step, as Agent Inbox decodes it inside its notarize step: a private file under `RUNNER_TEMP`, removed by an exit trap. `scripts/release.sh` passes it to `notarytool submit` and `notarytool log` as `--key`, `--key-id` and `--issuer`, in place of `--keychain-profile`. The key is MacMosh's own with the Developer role, so a leak cannot touch Agent Inbox's releases or the team's users (section 9, point 10).

## 5. Safety rules for a public repository

- **Who can start it:** only someone with write access, through Run workflow. There is no tag, push, pull-request, `pull_request_target` or `workflow_run` trigger, so a fork or a pull request cannot start it, and runs from forks get no secrets at all.
- **From which branch and commit:** the environment admits only `main`, and `preflight` refuses anything but `main`'s newest commit with green CI. Its summary shows any change to the release files since the last release, because `main` itself is not protected today.
- **Who approves:** you, in the environment, with the administrator bypass off. GitHub lets any program signed in as you approve too, so the rule for agents (section 6) is written down: they never approve or reject a deployment, never publish a draft, and never change an environment, secret, ruleset or Actions setting. A second account as reviewer is the only technical lock (section 9).
- **Permissions:** the workflow's default is `contents: read`; only `draft` has `contents: write`. Checkouts use `persist-credentials: false`. Inputs reach scripts only through `env:`, never written into a `run:` line.
- **Pinned actions:** only GitHub's own `actions/checkout` and `actions/upload-artifact`, each pinned to a full commit from its own repository with a version comment, as CI does today. No `actions/cache` and no `setup-*` action.
- **Third-party code:** the one Swift package, swift-argument-parser, is pinned in `Package.resolved` and compiled in a step before any secret or keychain exists.
- **Never printed (logs are public):** any secret; the certificate's name, owner or team; `security find-identity` output (kept in a variable). No step uses `set -x`. `scripts/release.sh` already keeps `codesign --display` and `spctl` answers in files; it prints `notary-submit.txt` in full only when Apple returned no submission ID (line 202), which the trial run and a test check.
- **Never uploaded:** everything else under `dist/`: `signature-*.txt`, `gatekeeper*.txt`, `notary-submit.txt`, `notary-log.json`, the entitlements files, `for-notary.zip` and `MacMosh.app`. The upload names its two files exactly, never a folder.
- **Masked:** the six secrets by GitHub; the identity hash by `::add-mask::`. GitHub warns that masking is not guaranteed, so the rule is never to print, and masking is only the second line.

## 6. What changes in the repository

- **`scripts/release.sh`, three places only.** The refusal at lines 73-75 asks for `MACMOSH_NOTARY_KEY` (the key file's path), `MACMOSH_NOTARY_KEY_ID` and `MACMOSH_NOTARY_ISSUER` instead of `MACMOSH_NOTARY_PROFILE`; lines 197 and 210 pass `--key`, `--key-id` and `--issuer`; the hint at line 206 no longer names a profile. The header comment follows. Every other refusal, check, message and the printed commands stay, and it still never runs `git tag`, `git push`, `gh` or `security`.
- **Its tests.** `refusesWithoutANotaryProfile` becomes a refusal without the key settings; `aReleaseRunsEveryStepInOrder` and the notary-unfinished sentence (`ReleaseScriptTests.swift:200`) expect the new `notarytool` arguments; `ReleaseHarness` sets stand-in key values; a new test checks that the key ID, issuer and key path never appear in the output, the no-ID path of line 202 included; `theRunbookKeepsTheSecretOffEveryCommandLine` checks the new runbook's lines.
- **`scripts/import-signing.sh` and `scripts/with-notary-key.sh`** (new), with stand-in tests in the harness's manner: no identity, two identities, a team mismatch, cleanup restoring the search list, and the key file gone after a failure. `scripts/check.sh` runs shellcheck on both.
- **`.github/workflows/release.yml`** (new), with a test that reads it, as `AppBundleTests` reads `icon-pictures.yml`: the only trigger is `workflow_dispatch`; the default is `contents: read`; only `draft` writes, with no `uses:`, no checkout and one step; exactly two jobs name `macos-release`; every `uses:` is pinned to 40 hex characters; no `actions/cache` or `setup-*`; no `${{ secrets.` outside a step's `env:`; no `${{ inputs.` inside a `run:`; the upload keeps one day.
- **`docs/releasing.md`**, rewritten from section 0: words, the one-time setup, each release, who does what, the rule for agents of section 5, a cleanup list for a failed run (a tag with no release, which you may delete before anything is published; the artifact, which expires; the logs, kept 90 days, deleted if they show something), and "If something's off" with today's refused and stopped messages.
- **Issues #36 and #37:** a comment on each. On #36: the release is made by this workflow, and the notary login is a team key in GitHub's secrets, not a password saved on the Mac; its "done when" is unchanged. On #37: the cask text comes from the `build` job's log.
- **The v1 design, line 575**, which says releases are built on the owner's Mac "so the certificate never leaves it", becomes: "**Releases** are built, signed and notarized on GitHub's macOS runners by a workflow the owner starts and approves; the certificate and the notary key are secrets in a protected GitHub environment (`docs/superpowers/specs/2026-11-27-release-from-github-design.md`). CI only builds and runs tests."

## 7. A rehearsal on GitHub

The environment admits only `main`, so the workflow is tried after it is merged, and it is merged only after step 1 of section 0 is done. Merging it publishes nothing: it does nothing until someone clicks Run workflow and you approve.

1. **The trial run.** The agent starts Release on `main` with the current version and `make_draft` unticked. You approve `build` once; the agent never does. It runs the whole of `scripts/release.sh`, Apple's notarization included, and ends there: no artifact, no tag, no draft. Sending a build to Apple's notary service publishes nothing. It also proves that a Developer-role key can notarize.
2. **The agent reads the whole log** for anything that names you, the team or a key, as GitHub advises after a test run, and checks that the second `swift build` compiled nothing. If a credential shows, you delete the run's logs and replace it; if only a name or ID shows, it is hidden in a pull request. Either way the trial is run again.
3. **The first real run** is the same with `make_draft` ticked, and the draft is the test: the agent downloads it, tests it on the Air (#36's "done when"), and you publish only after that. The local `scripts/release.sh --rehearsal` on your Mac stays as it is, for development builds.

## 8. Non-goals, and what stays unproven until the first real run

**Not in this design:** publishing by the workflow; Agent Inbox's tag-push start and two-workflow split; Intel or universal builds; a DMG; update manifests; artifact attestations; the tap or its cask file; a self-hosted runner.

**Unproven until a run shows it:**

- whether `actions/checkout` leaves a local `main` or a detached HEAD, which `release.sh` refuses (if detached, the builder adds a step that makes `main` at the checked-out commit after checking `GITHUB_REF`);
- whether `git fetch --no-tags origin` works in a one-commit clone without stored credentials;
- whether Gatekeeper assessment is on in the macos-15 image; if not, `release.sh` stops at its Gatekeeper check;
- what `notarytool` (submit, log, an error), `stapler` and the notary log print: none is documented to name the team, but none has been seen on a runner;
- whether the Developer role is enough for `notarytool` (Apple's page names no minimum role; its forums report Developer works);
- whether a re-run of `draft` asks for approval again, and whether making the draft fails if `main` has changed `.github/workflows/` since the built commit (GitHub's pages do not say either);
- whether a draft's tag would be created only on publishing (the managing-releases page does not say), which could let `draft` skip making the tag; until then it makes the annotated tag itself;
- whether the second `swift build`, inside the release step, compiles nothing.

## 9. Left to the builder, and open points

**Left to the builder:** pinning Xcode 16.4 for the release (the macos-15 default, as CI uses); the REST calls `draft` uses to make the annotated tag, read from GitHub's REST documentation before they are written; the permissions `gh run download` and the CI check read need, from GitHub's documentation; step names and the summary's wording; job time limits; turning the scripts' failures into one-line messages that name the secret.

**Open points, each with a recommendation.** Lines marked **(owner)** or **(coordinator)** are theirs to decide.

1. **The notary login in `release.sh`.** Recommended: replace the keychain profile with the team key, so there is one way. Otherwise keep both, which keeps more tests but leaves a path nobody uses.
2. **Key ID, issuer ID and team ID as secrets, not variables as in Agent Inbox.** Recommended: secrets, so the logs hide them. The same names keep the two repositories alike; the values are entered again.
3. **The certificate's name.** Recommended: never pass it in; use the hash found in the throwaway keychain. Agent Inbox passes it as a variable, which puts it, with your name, into run scripts and evidence files.
4. **Prevent self-review.** Recommended: off. Agent Inbox's guide turns it on, but GitHub says that the person who starts a run cannot then approve it, and you are the only reviewer.
5. **Two approvals.** Recommended: two (build, then tag and draft). One approval would make the tag without a second look.
6. **The one-day artifact between `build` and `draft`.** Anyone signed in to GitHub could fetch the notarized zip from the run page for up to a day before you publish. Recommended: accept this, to keep the write token out of the job that holds the certificate, as Agent Inbox does. The alternative is one job holding both, with no artifact.
7. **(owner) Immutable releases** (published files and tags can never change, and a tag name is never reused). Recommended: turn it on in Settings, under Releases, before you publish the first draft.
8. **A failed first draft.** Recommended: bump the version and leave the tag, as Agent Inbox never moves a tag. Immutability locks only published releases, so an unpublished draft's tag could still be deleted and its number reused, but only with your yes.
9. **(owner) The company certificate leaves your Mac**, as a secret on GitHub. Recommended: yes, as you already do for Agent Inbox.
10. **(owner) The notary key.** Recommended: a new team key for MacMosh only, with the Developer role. Reusing Agent Inbox's key is one fewer step, but one leak would then stop both apps' releases, and an Admin-role key can add and delete the team's users.
11. **(owner) A ruleset on `main`** that requires a pull request and a green CI, with no required reviews so you can still merge alone; and one that stops anyone moving or deleting `v*` tags, as Agent Inbox's guide asks. Recommended: yes to both, after the builder has read GitHub's ruleset pages, which this design did not.
12. **(owner) Actions settings:** "Require actions to be pinned to a full-length commit SHA", and allowing only GitHub's own actions. Recommended: yes; every workflow already complies.
13. **(owner) A second GitHub account as the only reviewer**, so no agent signed in as you can approve. Recommended: not now; the written rule and the run summary are enough for a one-person project, and this note records the risk.
14. **(coordinator) Where the rule for agents lives.** The repository has no agent-instructions file. Recommended: in `docs/releasing.md` with this change, and in the owner's global agent instructions through a separate pull request in that repository.

## 10. Sources

GitHub, each read on 2026-11-27:

- Environment secrets: "Secrets stored in an environment are only available to workflow jobs that reference the environment. If the environment requires approval, a job cannot access environment secrets until one of the required reviewers approves it." Self-review: "users who initiate a deployment cannot approve the deployment job, even if they are a required reviewer." Plans: "required reviewers are only available for public repositories." Bypass: "By default, administrators can bypass the protection rules." Branch rules are "matched against the `GITHUB_REF` of the workflow run". https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments
- Setup: "Select **Required reviewers**", "Deselect **Allow administrators to bypass configured protection rules**", "click **Add deployment branch or tag rule**"; "Running a workflow that references an environment that does not exist will create an environment with the referenced name. ... the newly created environment will not have any protection rules or secrets configured." https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments
- Approval: "click **Review deployments**", "To approve the job, click **Approve and deploy**." https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/review-deployments ; by API, `POST /repos/{owner}/{repo}/actions/runs/{run_id}/pending_deployments`: "Required reviewers with read access to the repository contents and deployments can use this endpoint." https://docs.github.com/en/rest/actions/workflow-runs
- Manual runs: "Once a workflow has run at least once, you can dispatch it against any branch or tag"; `GITHUB_SHA` is the "Last commit on the `GITHUB_REF` branch or tag". https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows ; "Write access to the repository is required". https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow
- Re-runs: allowed "up to 30 days after its initial run", with "the same `GITHUB_SHA` (commit SHA) and `GITHUB_REF`"; approvals and artifacts are not mentioned. https://docs.github.com/en/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs
- Forks: "secrets are not passed to the runner when a workflow is triggered from a forked repository." Command lines: "Avoid passing secrets between processes from the command line". Base64: "You can use Base64 encoding to store small binary blobs as secrets." https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets
- Masking: "automatic redaction is not guaranteed", "If your secret is transformed in some way (such as Base64 or URL-encoded), be sure to register the new value as a secret too", "View the run logs for your workflow after testing", "If an unredacted secret is sent to a workflow run log, you should delete the log and rotate the secret", "Pin references to actions to a commit SHA", and for inputs in scripts, "set the value of the expression to an intermediate environment variable". https://docs.github.com/en/actions/reference/security/secure-use ; `::add-mask::{value}`: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands
- Permissions: "If you specify the access for any of these permissions, all of those that are not specified are set to `none`", "`contents: write` allows the action to create a release." https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
- Drafts: "Only users with push access will receive listings for draft releases." A release fails if its commit changes `.github/workflows/` and "The GITHUB_TOKEN available to GitHub Actions cannot be authorized for this". https://docs.github.com/en/rest/releases/releases ; publishing: "click **Publish release**". https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository
- Tokens: "events triggered by the `GITHUB_TOKEN` will not create a new workflow run". https://docs.github.com/en/actions/concepts/security/github_token
- Artifacts: "you can use `retention-days` with the `upload-artifact` action". https://docs.github.com/en/actions/tutorials/store-and-share-data ; downloading them needs "Read access to the repository", and "Public repositories are accessible to everyone on the internet". https://docs.github.com/en/actions/how-tos/monitor-workflows/use-workflow-run-logs (which also says "click **Delete all logs**") and https://docs.github.com/en/repositories/creating-and-managing-repositories/about-repositories
- Actions settings: "When you enable Require actions to be pinned to a full-length commit SHA, all actions must be pinned to a full-length commit SHA to be used." https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository
- Immutable releases: "Scroll down to the "Releases" section, then select **Enable release immutability**. Be aware that immutability will only apply to future releases." https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/establish-provenance-and-integrity/prevent-release-changes
- Runner images: "macOS 15 Arm64 | arm64 | `macos-15`". https://github.com/actions/runner-images/blob/main/README.md ; the macos-15 image's default Xcode is 16.4 and it ships gh: https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md
- gh's source (`pkg/cmd/secret/set/set.go` on its main branch): at a terminal it asks `Prompter.Password("Paste your secret:")`; from a pipe it reads standard input and applies `bytes.TrimRight(body, "\r\n")`. https://github.com/cli/cli

Apple, each read on 2026-11-27:

- Team keys: "Team API keys can access all apps, regardless of their role"; "keys with the Admin role have broad permissions and can do things like create new users and delete users"; "To generate team keys, you must have an Admin account in App Store Connect"; "The private key is available for download a single time"; steps from "Select Users and Access, and then select the Integrations tab" to "Under Access, select the role for the key." No minimum role for notarization is named. https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api ; that the Developer role works is reported in Apple's forums, not by Apple (https://developer.apple.com/forums/thread/133063, cited by the security reader, not re-read)
- Keychain Access: "Select the items you want to export", File > Export Items, "click the File Format pop-up menu, then choose a file type", then "Enter a password." https://support.apple.com/guide/keychain-access/import-and-export-keychain-items-kyca35961/mac

Tools and state on this Mac and the repository, 2026-11-27:

- `gh secret set --help` (gh 2.105.0): "-b, --body string   The value for the secret (reads from standard input if not specified)", "-e, --env environment   Set deployment environment secret", "Secret values are locally encrypted before being sent to GitHub." `xcrun notarytool submit --help` (notarytool 1.1.4): "-k, --key <key> App Store Connect API key. File system path to the private key", "-i, --issuer <issuer> App Store Connect API Issuer ID, UUID format. Required for Team API Keys."
- `man codesign`: "If identity consists of exactly forty hexadecimal digits, it is instead interpreted as the SHA-1 hash". `man security`, import: "-P passphrase   Specify the unwrapping passphrase immediately. The default is to obtain a secure passphrase via GUI." macOS `base64` ends its output with a newline.
- Read-only `gh api` calls: `main` is not protected, the repository has no rulesets, and its Actions settings are `allowed_actions: all` and `sha_pinning_required: false`. CI runs on every push to `main` (`.github/workflows/ci.yml:3-6`).

The agent-inbox repository:

- Tag-only, read-only producer: `.github/workflows/macos-release.yml:3-9`. Protected workflow on `workflow_run`: `.github/workflows/macos-release-protected.yml:3-8`; jobs and runners: lines 24, 83, 204-210, 276-283, 451-457, 510-520, 655-665; `authorize`'s checks: lines 24-81 and `scripts/macos-release-gates.mjs:164-197`.
- Approval at each protected stage: `docs/macos-release.md:1088-1090`; four environment jobs: `test/macos-release-workflow.test.ts:663`. Self-review, bypass and "only the protected default branch": `docs/macos-release.md:670-682`. Secret and variable names: `docs/macos-release.md:682-699`; step-level reads: `macos-release-protected.yml:242-245, 333-335, 341-346`.
- Throwaway keychain and cleanup: `scripts/import-apple-signing.sh:66-148`; `-P` on the command line: lines 118-121; the identity name from a variable: lines 127-147.
- Team key decoded and passed to `notarytool` in the notarize step: `scripts/notarize-macos.sh:19-49`.
- Draft, re-download, compare, then publish and mark latest: `docs/macos-release.md:573-585`; one write job with one shell step and no checkout: lines 663-668; a failed tag is never moved: lines 1166-1168.
