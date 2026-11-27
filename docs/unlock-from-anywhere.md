# Unlocking the workhorse from anywhere

This guide is for MacMosh users with Tailscale who want to unlock the workhorse after a restart while away from home. The short answer: with FileVault (Apple's disk encryption) on, the workhorse waits after a restart at a locked disk until someone types the Mac's password. Its Tailscale app doesn't run before login, so only its home address can be reached. An always-on device at home can pass your traffic to that address. Tailscale calls this a **subnet router**. With one, MacMosh's `Unlock disk…` and `Log in…` should work away as they do at home.

**Nobody in this project has followed this guide yet.** Steps marked *(Tailscale's page)* come from Tailscale's documentation, read on 2026-11-26, not from a try. The other steps come from MacMosh's code.

Two names come up throughout. The **workhorse** is the Mac that runs your work. The **daily Mac** is the one you sit at, with the MacMosh menu.

## Which one do I use?

Tailscale's pages cover these three, among others (Windows and Android too). The device must be on the workhorse's home network.

| Device | What Tailscale's pages say | Pick it when |
|---|---|---|
| Another Mac | The Standalone app (Tailscale's recommended one) and the App Store app don't run before login. Don't install both on one Mac. | A spare Mac stays on, plugged in and logged in. |
| An Apple TV | tvOS 17.0 or later (18.0 recommended), set up as a home hub, "which lets it remain connected to the network while in sleep mode". IPv4 only. | You already have one at home. |
| A Linux box | IP forwarding on (it lets the device pass traffic on), and a firewall that denies forwarding by default. | You already run one. |

## Which route do I advertise?

A **route** is a range of home addresses the always-on device offers to your Tailscale devices.

| Route | Example | Pick it when |
|---|---|---|
| The workhorse's address only | `192.168.1.20/32` (`/32` means this one address) | Almost always. |
| The whole home network | `192.168.1.0/24` (192.168.1.0 to 192.168.1.255) | You want other home devices too. Your router shows the range. |

## Before you start

1. **On the daily Mac, run `macmosh list --json`.**
   `macmosh` is the command inside the app: `/Applications/MacMosh.app/Contents/Helpers/macmosh`. The value after `"homeAddress"` is the workhorse's home address, such as `192.168.1.20`. If it is `null`, see `The home address is recorded` in the checklist (step 2).

2. **Click the workhorse's `Run the checklist…` in the menu.**
   The `macOS version and chip` line should end `Restart recovery over ssh is offered.` If it says you unlock it at the Mac, stop: the unlock over ssh needs Apple silicon and macOS 26 or later ([Apple](https://support.apple.com/guide/deployment/intro-to-filevault-dep82064ec40/web)).

## Set up the always-on device

1. **Install Tailscale on it and sign in to your tailnet** *(Tailscale's page)*.
   Your **tailnet** is your own Tailscale network. The device appears on the [Machines page](https://console.tailscale.com/admin/machines) of Tailscale's admin console, its web page for managing devices.

2. **Advertise the workhorse's address** *(Tailscale's page)*.
   - Standalone Mac app: in its **Settings**, under CLI integration, select **Show me how**, then **Install Now**. Then, in Terminal: `sudo tailscale set --advertise-routes=192.168.1.20/32`.
   - App Store Mac app: `/Applications/Tailscale.app/Contents/MacOS/Tailscale set --advertise-routes=192.168.1.20/32`.
   - Linux: turn on IP forwarding as Tailscale's subnet router page shows (with `firewalld`, see its masquerading note), then run the `sudo tailscale set` command above.
   - Apple TV: in the Tailscale app, select **Subnet Router**, then **Advertise New Route**, and change the placeholder to `192.168.1.20/32`.

   The device should then show a **Subnets** badge on the Machines page.

3. **Approve the route** *(Tailscale's page)*.
   On the Machines page, select the device, go to its **Subnets** section, select the route and select **Save**. Or, as Tailscale's quick guide puts it: the device's menu, then **Edit route settings**.

4. **Turn off key expiry for the device** *(Tailscale's page)*.
   On the Machines page, open its menu and select **Disable Key Expiry**. Tailscale says an expired router key leaves its routes "unreachable". See "The safety side" first.

5. **Allow the traffic in your access rules** *(Tailscale's page)*.
   **Access rules** say who in your tailnet may reach what. On the [Access controls page](https://console.tailscale.com/admin/acls), add this as a new entry in the `"grants"` list, with a comma between entries, then save:

   ```
   {"src": ["autogroup:member"], "dst": ["192.168.1.20/32"], "ip": ["*"]}
   ```

   `autogroup:member` is every member of your tailnet; `"ip": ["*"]` allows all ports. Skip this step only if a rule already lets your devices reach this address on all ports (Tailscale: rules that "allow access to your advertised subnet routes").

6. **On the daily Mac, check that Use Tailscale subnets is ticked** *(Tailscale's page)*.
   It is in Tailscale's menu in the menu bar; the Standalone and App Store apps turn it on by default. With the command-line-only variant, run `tailscale set --accept-routes=true`.

## Check it from the daily Mac

1. **Leave the home network, with Tailscale on.**
   A phone's hotspot will do.

2. **In the MacMosh menu, open the submenu of the workhorse's line**, `workhorse · Ready`, with its name in place of `workhorse`.
   Under the summary it should say `Home address reachable from here: yes`.

## After a restart, from away

1. **Open the MacMosh menu.**
   It should say `workhorse · Locked after a restart`, with `Unlock disk…  (you type the Mac's password)`.

2. **Click `Unlock disk…`.**
   A tab says `You are about to type the Mac's password into ssh. MacMosh can't see it.`

3. **Type the workhorse's password when ssh asks for it.**
   The tab then says `workhorse · Waiting for login` and `Next: press Log in…, or run: macmosh screen`, then the workhorse's id.

4. **Click `Log in…  (opens Screen Sharing)`.**
   Apple's Screen Sharing opens at the home address. Log in as you would at the Mac.

5. **Look at the menu.**
   Tailscale and MacMosh's desk server (it holds your terminal sessions) start by themselves. It may say `Waiting for the desk server` for up to a minute, then `Ready`.

After `Restart…`, if its tab said `The Mac restarts with its disk already unlocked.`, skip to step 4. That path has not been run on a real Mac.

## What this does not give you

- If the always-on device is off, asleep or logged out, or its key expired, you unlock at the Mac when away.
- At home too, the daily Mac may send the workhorse's traffic through the always-on device: Tailscale says the more specific route wins, and that a route "may still be present" while its router is offline. Not tried.
- If your router gives the workhorse a new address during the restart, the route points at the old one. [A fixed home address](fixed-home-address.md) prevents that.
- MacMosh sets none of this up.

## The safety side

- With the single-address route, only the workhorse is exposed.
- Approving a route doesn't allow traffic; your access rule decides who can use it.
- `autogroup:member` includes "all invited users". If others share your tailnet, put your own login, such as `user@example.com`, in `src` instead.
- Key expiry is a security feature. With it off, the device's keys "will no longer expire", so keep it somewhere you trust.
- The unlock still needs the Mac's password. If a different ssh key answers at any address, MacMosh says `Can't verify it` and offers no unlock: stop, and don't type a password.

## What was tested, and what was not

**Tested** on 2026-11-22, on one MacBook Pro at home, with no subnet router: `Unlock disk…` and `Log in…` after a full restart ([sitting 2](sittings/sitting-2-results.md)).

**Not tried:** every step above. Nobody has set up a subnet router for MacMosh, seen `Home address reachable from here: yes` away, unlocked through one, or unlocked at home with the route accepted.

## If something's off

| What you see | What to do |
|---|---|
| `Home address reachable from here: no`, away | On the Machines page, check the device is connected, its route approved and key expiry off. Then check your rule and **Use Tailscale subnets**. |
| No `Home address reachable` line | It shows only while the workhorse is `Ready`. In the checklist, look at `The home address is recorded`. |
| `Can't reach it` and `Tailscale says it is offline and you are away from home.` | The route isn't getting through, or the workhorse is off. If the Machines page shows the device connected, unlock at the Mac. |
| `Unlock disk…` fails at home while the always-on device is down | Untick **Use Tailscale subnets** on the daily Mac and try again. |
| `its home address may have changed` | Unlock at the Mac, then advertise and approve the new address. |
| `Log in…` fails after the unlock worked | If your rule lists ports, allow all (`"ip": ["*"]`). |

## Sources

Tailscale, read 2026-11-26: [subnet routers](https://tailscale.com/docs/features/subnet-routers), [quick guide](https://tailscale.com/docs/features/subnet-routers/how-to/setup), [macOS variants](https://tailscale.com/docs/concepts/macos-variants), [Apple TV](https://tailscale.com/docs/install/appletv), [route injection](https://tailscale.com/docs/reference/route-injection), [key expiry](https://tailscale.com/docs/features/access-control/key-expiry), [grants](https://tailscale.com/docs/reference/syntax/grants), [policy file](https://tailscale.com/docs/reference/syntax/policy-file), [client preferences](https://tailscale.com/docs/features/client/manage-preferences), [CLI](https://tailscale.com/docs/reference/tailscale-cli).

This project: the [design](superpowers/specs/2026-11-18-macmosh-v1-design.md), sections 5.5 and 7.9, and the words in `Sources/MacMoshKit`.
