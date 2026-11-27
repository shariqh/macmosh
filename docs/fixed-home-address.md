# Giving the workhorse a fixed home address

This guide is for keeping the workhorse on the same address on your home network after it restarts. The short answer: if the workhorse is on Wi-Fi, set its Private Wi-Fi Address to Fixed, then ask your router to reserve the address the workhorse has now. A **reservation** is a router setting that keeps one address for one device. **Private Wi-Fi Address** is a macOS setting that gives the Mac a different MAC address on each Wi-Fi network; a **MAC address** is the address a device's network connection shows the router. This is advice, not a requirement: in most homes the address survives a restart anyway.

**Nobody in this project has followed this guide yet.** Steps marked *(Apple's page)* take their wording from Apple's documentation, not from a try. Section 4 has no vendor page behind it. The other steps come from MacMosh's code.

Two names come up throughout. The **workhorse** is the Mac that runs your work. The **daily Mac** is the one you sit at, with the MacMosh menu.

**Who should bother:** people with an always-on device at home, as in [unlocking from anywhere](unlock-from-anywhere.md), since its route points at this address; and people who saw `Can't reach it` after a restart with the hint `If it just restarted, its home address may have changed.`

## Why the address matters

- The **home address** is the workhorse's address on your home network, such as 192.168.1.20. Every status check reads it and saves it.
- If you use Tailscale (it is optional), the main address is normally the workhorse's Tailscale name. Until someone logs in, Tailscale's Mac app (the Standalone and App Store versions) doesn't run, so that address doesn't answer ([Tailscale's page](https://tailscale.com/docs/concepts/macos-variants)). `Unlock disk…` then sends the password to the home address, or to the local name if that is what answered.
- Your router hands out addresses, and after a restart it may hand out a different one. MacMosh refreshes the home address only while the workhorse is up, so the old one stops answering. MacMosh then tries the local name, such as `Workhorse.local` (whether that answers before the unlock is not known). If neither answers, the menu says `Can't reach it`, and you unlock at the Mac.

## Which one do I use?

| Option | What it costs | What is known | Pick it when |
|---|---|---|---|
| Do nothing | Nothing | The design: in most homes the address survives a restart. If it changes, you unlock at the Mac. | You have no always-on device, and restart only when you are at home. |
| Reserve the address on the router | A few minutes in the router's app or page | The design's advice. Not tried here. On Wi-Fi it also needs Private Wi-Fi Address set to Fixed or Off. | You have the always-on device, or the address changed after a restart before. |
| Set a manual address on the Mac | A few minutes in System Settings | Apple documents `Manually` for an address "your ISP or administrator gave you", and says an address can clash with another device's. Not tried; no steps here. | Someone who runs your network gave you an address. |

## Before you start

Do this at home, with the workhorse logged in. Sections 1 and 3 are at the workhorse, section 2 on the daily Mac, and section 5 uses both. Have your router's app or admin page to hand. `macmosh` below is the command inside the app: `/Applications/MacMosh.app/Contents/Helpers/macmosh`.

## 1. Wi-Fi only: set Private Wi-Fi Address *(Apple's page)*

This needs macOS Sequoia 15 or later. Apple's pages describe the three choices:

- **Off:** "your device uses its hardware MAC address." Apple adds: "This Mac can be identified and tracked on this network, and across other networks."
- **Fixed:** "your device uses a private address, but the private address doesn't rotate". It lets this network track the Mac, but "helps reduce tracking across other networks". The Mac chooses it by default on a new network that uses WPA2 or stronger security.
- **Rotating:** "a private address that rotates to a different private address every 2 weeks." The Mac chooses it by default on a new network that uses "weak security or no security". A reservation would stop matching.

Choose Fixed unless you have a reason for Off. Fixed still changes in two cases Apple names: if the Mac forgets the network, "it also forgets the private address" (unless it last forgot it under 24 hours before); and "If you erase all content and settings or reset network settings on your device, it uses a different private address the next time it joins the network." Then make the reservation again.

1. **On the workhorse, choose Apple menu > System Settings, then click Wi-Fi in the sidebar.**

2. **Click Details (or More Info) next to your network's name.**

3. **From the menu next to Private Wi-Fi Address, choose Fixed or Off.**
   Apple's page doesn't say what you see next. If it was Rotating, the router may now see a different address (with Off it sees the hardware MAC address; Apple doesn't say whether Fixed keeps the Rotating one), so the workhorse may get a different IP address.

## 2. See the address MacMosh has saved

1. **On the daily Mac, run `macmosh status`.**
   You should see a line such as `Workhorse · Ready`. This check saves the latest home address.

2. **Run `macmosh list --json`.**
   You should see one line of text with `"homeAddress":"192.168.1.20"` in it, with your address in place of 192.168.1.20. Write it down. If it says `"homeAddress":null`, see "If something's off".

MacMosh saves the address of the connection macOS sends internet traffic through (with a VPN, the first network port that has one).

## 3. Note the addresses on the workhorse *(Apple's page)*

1. **On Wi-Fi, look in the same Details as in section 1.**
   Apple's page says Details shows "the IP and router addresses". The IP address should match the one from section 2. Note the **Wi-Fi address** row too: Apple calls it "The current Wi-Fi address." This project hasn't checked that it is the one your router lists.

2. **On Ethernet, or with Off, find the hardware MAC address.**
   On Ethernet, choose Apple menu > System Settings, click Network, then your Ethernet service; on Wi-Fi, use Details. Click **Hardware**, which lets you "view the hardware MAC address".

## 4. Reserve the address on the router

Routers differ, so this guide can't give the clicks; your router's own manual or app help has them.

1. **Open your router's app or admin page.**

2. **Find the workhorse in its list of connected devices, by its IP address.**
   Match by IP address first. If the router lists MAC addresses, use the Wi-Fi address (Fixed) or the hardware MAC address (Off or Ethernet) from section 3.

3. **For that device, find the setting that keeps one address for it, and choose the address it has now.**
   Routers name this setting differently. Keeping the current address means the address MacMosh has saved stays right.

4. **Save the change.**

## 5. Check it

1. **At the workhorse, choose Apple menu > Restart, then click Restart.** *(Apple's page)*

2. **If FileVault (Apple's disk encryption) is on, unlock the disk as you usually do.**
   Use `Unlock disk…  (you type the Mac's password)` in the menu if MacMosh offers it, or unlock at the Mac. If FileVault is off, skip this step.

3. **Log in as you usually do.**
   The menu should then show `Workhorse · Ready`. In the submenu that opens from that line, or at the foot of its page in the window, you should see `Home address reachable from here: yes`.

4. **On the daily Mac, run `macmosh status`, then `macmosh list --json`.**
   `"homeAddress"` should show the same address as before.

One restart proves little. The menu, the window and the checklist don't show the address itself; `macmosh list --json` does.

## What was tested, and what was not

Nothing in this guide has been tried in this project: no reservation on any router, no change to Private Wi-Fi Address on a workhorse, not the check above. Whether `Workhorse.local` answers before the unlock is not known. MacMosh's words come from its code.

## If something's off

| What you see | What to do |
|---|---|
| `Can't reach it` after a restart, with `If it just restarted, its home address may have changed.` | Unlock at the Mac. Run `macmosh status` so MacMosh saves the new address, then look at the reservation. |
| `Tailscale says it is offline and you are away from home.` | A reservation alone doesn't change this: from away you need an always-on device, as in [unlocking from anywhere](unlock-from-anywhere.md). Without one, unlock at the Mac. |
| `"homeAddress":null` | Run `macmosh status` while the workhorse is `Ready`, then look again. If the checklist says `Workhorse didn't report a home address. It may not be on a home network right now.`, check its network. |
| The address changed although you reserved it | Check that Private Wi-Fi Address isn't Rotating, and whether the Mac forgot the network or had its network settings reset. Reserve again. |
| The router has no such setting | Do nothing, and unlock at the Mac if the address changes. |

## Sources

Apple, read 2026-11-26: [private Wi-Fi addresses](https://support.apple.com/en-us/102509), [Wi-Fi settings](https://support.apple.com/guide/mac-help/wi-fi-settings-on-mac-mh11935/mac), [Ethernet settings](https://support.apple.com/guide/mac-help/ethernet-settings-on-mac-mh11939/mac), [a manual IP address](https://support.apple.com/guide/mac-help/use-dhcp-or-a-manual-ip-address-on-mac-mchlp2718/mac), [address conflicts](https://support.apple.com/guide/mac-help/resolve-ip-address-conflicts-on-mac-mh27606/mac), [restart](https://support.apple.com/guide/mac-help/shut-down-or-restart-your-mac-mchlp2522/mac).

Tailscale, read 2026-11-26: [macOS variants](https://tailscale.com/docs/concepts/macos-variants).

This project: the [design](superpowers/specs/2026-11-18-macmosh-v1-design.md), sections 7.6 and 7.9, and the code in `Sources/MacMoshKit`.
