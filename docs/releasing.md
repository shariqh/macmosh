# Releasing MacMosh

This runbook explains how to make a copy of MacMosh that anyone can download and open without a warning. One command, `scripts/release.sh`, does the work. It publishes nothing: it ends by printing the commands that would publish, and those wait for your yes.

Two rules hold everywhere in this page:

- A secret (a password or a key) is typed only into a tool's own prompt, never on a command line, and never given to an agent.
- The agent runs every rehearsal. You are at the Mac for the first real run, because that is when the Mac's keychain is first asked for the notary login.

## 1. What a release is

These are the words this page uses.

- **Signing:** your Developer ID certificate puts a seal on the app that says who made it and shows it has not been changed since. `scripts/build-app.sh`, our own build script, signs with the certificate named in `MACMOSH_SIGN_IDENTITY`.
- **Notarization:** Apple's automatic check of the signed app for malware. It is not App Review.
- **Ticket and stapling:** the ticket is Apple's record that the check passed. Stapling attaches it to the app, so a Mac can see it even when it is offline.
- **Keychain profile:** a named entry in the Mac's keychain (the Mac's own locked store of passwords) that holds the notary login. Scripts pass only its name, never the password.
- **Gatekeeper:** the macOS check that runs when a downloaded app first opens. It looks for the signature and the ticket.

And the tools:

- `xcrun` is Apple's launcher for the developer tools that come with Xcode. `xcrun notarytool` sends an app to Apple's notary service and asks about it. `xcrun stapler` staples the ticket and checks it.
- `codesign` reads and checks a signature. `spctl` asks Gatekeeper what it would do with an app.
- `ditto` is Apple's copy tool. It makes and unpacks zip files without damaging an app's signature.
- `shasum -a 256` prints a checksum: a 64-character fingerprint of a file, so anyone can check that a download is the same file.
- `gh` is GitHub's command-line tool. It can make a release on GitHub, the page people download from.
- A Homebrew **cask** is a small recipe file that lets people install the app with `brew install --cask`. It lives in a **tap**, a separate GitHub repository of recipes (issue #37).

What `scripts/release.sh <version>` does, in order:

1. It refuses before building anything when something is wrong: the version is not the app's, a setting is empty, the checkout has changes or is not the same commit as `origin/main`, the tag is already there, or `dist/release/<version>` already exists.
2. It builds and signs the app with `scripts/build-app.sh --into dist/release/<version>`.
3. It checks the signed app: the signature, the entitlements (the permissions the app asks macOS for), the hardened runtime (a protection Apple requires for notarization), the secure timestamp, that it is built for Apple silicon only, that it holds no folder path from the Mac that built it and no sample menu, and its version.
4. It sends a zip of the app to Apple and waits up to 30 minutes for the answer. It keeps Apple's log, and shows its issues even when Apple accepts.
5. It staples the ticket, asks Gatekeeper, and makes `MacMosh-<version>.zip`, the file people download.
6. It unpacks that zip into a temporary folder and checks the copy again, then writes the checksum, `MacMosh-<version>.zip.sha256`.
7. It prints the tag, draft-release and cask text. It runs none of them.

Everything goes in `dist/release/<version>/`, which git ignores. The files that name the certificate's owner (codesign's and Gatekeeper's longer answers) stay there and are never printed.

`scripts/release.sh --rehearsal <version>` does steps 2 and 3 and makes the zip for Apple, on any branch, and sends nothing to Apple's notary service. It writes to `dist/rehearsal/<version>/` and moves the previous rehearsal of that version to the Trash.

## 2. Once only: the notary login (yours alone)

Apple's notary service needs a login. You save it once in your Mac's keychain, under the profile name `macmosh-notary`. There are two kinds of login.

### Which one do I use?

| | App-specific password | App Store Connect team key |
|---|---|---|
| What it is | A password Apple makes for one outside app, used in place of your Apple Account password | A key file (`.p8`) with a key ID and an issuer ID |
| What it needs | Two-factor authentication on your Apple Account | An Admin account in App Store Connect. It must be a team key: Apple says individual keys cannot use notarytool |
| Where you make it | account.apple.com, Sign-In and Security, App-Specific Passwords | App Store Connect, Users and Access, Integrations, App Store Connect API, Team Keys |
| What to watch | Every app-specific password is revoked when you change or reset your Apple Account password | The `.p8` file downloads only once. Keep it outside this repository |
| Use it when | Your Apple Account is on the team that owns the Developer ID certificate (the usual case) | Your Apple Account is not on that team |

Use the app-specific password unless your Apple Account is not on the team that owns the signing certificate.

You also need your Team ID, a 10-character code for your developer team. Apple's page on where to find it is https://developer.apple.com/help/account/manage-your-team/locate-your-team-id/. Open that page in your browser; it shows where the Team ID is.

### Steps

1. Make the app-specific password: sign in at account.apple.com, open Sign-In and Security, select App-Specific Passwords, then select "Generate an app-specific password" and follow the steps on your screen.
   You should see the new password. Leave that page open until step 2 is done; you need the password there.
2. In your own Terminal, not through an agent, run:

   ```
   xcrun notarytool store-credentials "macmosh-notary" --apple-id "<your Apple Account email>" --team-id "<your Team ID>"
   ```

   You should see a secure password prompt. Paste or type the app-specific password there. Nothing shows as you type.
   For a team key instead, run this. Here the key file is the secret, so it stays outside this repository:

   ```
   xcrun notarytool store-credentials "macmosh-notary" --key "<path to the .p8 file>" --key-id "<key ID>" --issuer "<issuer ID>"
   ```

   Never add `--password` to that command: a password on a command line is kept in the shell's history.
   Never add `--sync` either: it copies the login to iCloud Keychain, onto your other devices.
3. You should see notarytool check the login with Apple before it saves it (it does this by default). What it prints when it saves is not recorded yet: tell the agent, so it can go in this runbook. Before you pass it on, replace any name, email address or Team ID in it with <name>, <email> or <Team ID>. If Apple turns the login down, see "If something's off".
4. In the Terminal where you release, run `export MACMOSH_NOTARY_PROFILE=macmosh-notary`. It lasts only for that Terminal window, so you type it again in each new window, unless you add that line to your own shell file yourself. It holds only the profile's name, not the password.
5. Check that `MACMOSH_SIGN_IDENTITY` is set in that window, without printing it: `[ -n "$MACMOSH_SIGN_IDENTITY" ] && echo set || echo missing`. You should see `set`. It holds your signing certificate's name, as it does for `scripts/build-app.sh`; this page never writes that name.
   If you see `missing`: the variable comes from your own shell file, where you set it yourself to the certificate's name as Keychain Access shows it. Open a new Terminal window after you add it. Never paste that name to an agent, and never write it in this repository.

## 3. Each release

1. **The agent rehearses.** The agent runs `scripts/release.sh --rehearsal <version>` on your Mac, where `MACMOSH_SIGN_IDENTITY` is set, and reads the output. A rehearsal signs with your Developer ID key but sends nothing to Apple's notary service. Signing does ask Apple's timestamp server for the time, so a rehearsal needs the internet.
   It should end with `release.sh: rehearsal finished. Nothing was sent to Apple's notary service, and nothing in dist/rehearsal/<version> is a release.`
2. **You get main ready.** The pull requests for this version are merged, `main` here is the same commit as `origin/main`, and nothing is left uncommitted. The agent can check this for you.
3. **You run the release, at the Mac.** In a Terminal with both variables set (section 2, steps 4 and 5), from the repository folder, run `scripts/release.sh <version>`, for example `scripts/release.sh 0.1.0`.
   You should see the build, then `release.sh: checks passed: …`, then `release.sh: sending for-notary.zip to Apple's notary service …`.
   A keychain prompt may appear, the first time, for the notary profile. Its exact wording is not known yet. Read it before you answer, and tell the agent what it said, so this first real run records it here. Before you pass it on, replace any name, email address or Team ID in it with <name>, <email> or <Team ID>; the agent records only that wording.
4. **You wait for Apple.** It usually answers within 5 to 15 minutes. The script waits up to 30. Nothing prints while it waits. In the first minute, glance at the screen for a keychain prompt (it can hide behind other windows); after that, the silence is Apple's wait.
5. **You read the end.** A finished run ends with `release.sh: done. MacMosh <version> is notarized, stapled and checked.`, the zip and its checksum, `release.sh: Gatekeeper: accepted (…)` above them, and then the printed commands and the cask.
6. **You say yes or no to the tag and the draft release.** The printed `git tag`, `git push` and `gh release create … --draft` lines make the tag and a draft release, which is saved but not published. The coordinator runs them only after your yes.
7. **Separate yeses later.** Publishing the draft release, and adding the printed cask to the tap (issue #37), each wait for their own yes. Before you are asked to publish, the coordinator rewrites the draft's notes, and the agent tests a download on a Mac with no MacMosh on it.

## 4. Who does what

| Step | Who |
|---|---|
| Saving the notary login (section 2) | You, alone, in your own Terminal |
| Every rehearsal, and reading its output | The agent |
| The first real run | You, at the Mac |
| Any keychain prompt, and any run that sits silent | You, at the Mac |
| Reading a real run's output and the notary log | The agent, with you |
| Running the printed tag and draft-release commands | The coordinator, after your yes |
| The download test, on a Mac with no MacMosh, over ssh | The agent |
| Publishing the release, and the tap | Each after your yes |

## 5. If something's off

Each line starts with what the script printed after `release.sh: refused:` or `release.sh: stopped:`.

**Refused** (nothing was built):

- *could not read the app's version …* : the version line in `Sources/MacMoshKit/MacMoshKit.swift` has changed shape. Ask the agent.
- *… is not the app's version …* : type the version the message names, or change the version in a pull request first.
- *MACMOSH_SIGN_IDENTITY is empty …* : this Terminal window does not have it. Open a window where your shell file sets it (section 2, step 5).
- *MACMOSH_NOTARY_PROFILE is empty …* : run `export MACMOSH_NOTARY_PROFILE=macmosh-notary` in this window (section 2, step 4).
- *the checkout has changes that are not committed.* : commit them in a pull request, or move them aside. `git status` lists them.
- *the checkout is on …, not main.* : run `git switch main`.
- *could not fetch origin …* : the network or GitHub is down, or the login for GitHub has expired. Try `git fetch` by hand.
- *main here is not the same commit as origin/main.* : run `git pull --ff-only`, or push what is only here through a pull request.
- *the tag v… already exists here.* or *… on origin.* : this version was released, or a release was started. Bump the version, or ask the agent before you touch the tag.
- *could not ask origin whether the tag … exists.* : as for fetch, above.
- *dist/release/… already exists …* : an earlier run left it. Move that folder to the Trash, then run again.

**Stopped** (something was built, nothing was published):

- *scripts/build-app.sh failed …* : its own message, just above, says why.
- *the signature of … did not verify …*, *the entitlements on … are not exactly those of App/MacMosh.entitlements.*, *… does not have the hardened runtime switched on.*, *… has no secure timestamp.* : the build or its signing went wrong. Ask the agent to look at `signature-app.txt` and `signature-command.txt` in the output folder.
- *… is built for …; the first release is for Apple silicon (arm64) only.* : the build made a program for another kind of Mac. Ask the agent.
- *… contains a folder path from the Mac that built it (the text /Users/).* : the strip step in `scripts/build-app.sh` did not do its work; see #189.
- *… contains MACMOSH_SAMPLE_MENU, so it is not a release build.* : a debug build got in. Ask the agent.
- *MacMosh.app says version …, not ….* : the app's Info.plist and the source disagree. Ask the agent.
- *notarytool could not send for-notary.zip to Apple …* : what notarytool said is printed above and kept in `notary-submit.txt`. If it names the login, save the login again (section 2).
- *Apple had not finished after 30 minutes …* : Apple goes on without the script. Run the `xcrun notarytool info …` line it printed later; when it says Accepted, ask the agent how to go on.
- *could not download Apple's notary log …* : try again later; nothing was stapled.
- *Apple's answer is …, not Accepted …* : the issues are printed above and the whole log is in `notary-log.json`. Ask the agent to fix them. Once the fix is on main, move `dist/release/<version>` to the Trash and run the same version again: nothing was tagged.
- *xcrun stapler could not staple the ticket …* or *the ticket stapled to … did not validate.* : Apple accepted the app, but the ticket did not go on. Ask the agent.
- *Gatekeeper did not accept …* : its answer is in `gatekeeper.txt`. Ask the agent.
- *the copy unpacked from MacMosh-….zip …, so the zip is renamed NOT-FOR-RELEASE-…* : the zip people would download is broken. Do not publish it. Ask the agent.

**Other:**

- A run sits silent right after `release.sh: sending for-notary.zip …`: see section 3, step 4.
- A run sits silent right after `build-app.sh: signing with the Developer ID certificate`: this is unlikely, since signed builds already run on this Mac with no prompt. It may be waiting for a click on a keychain prompt, perhaps behind another window. Look for it on the screen.
- Signing fails during a rehearsal or a release with no internet: signing asks Apple's timestamp server for the time. Connect, then run again.
- notarytool says the login is wrong when you save it, or later: an app-specific password stops working when your Apple Account password changes. Make a new one and save it again (section 2).
