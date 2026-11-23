# Running a workhorse with its lid closed

This guide is for a spare Mac laptop that you use as your workhorse and want to keep running with its lid shut. The short answer: keep it plugged in, on a hard, flat surface, and turn on MacMosh's lid-closed mode from the menu. This project turned the setting on by hand on one MacBook Pro, and it stayed awake and reachable for 43 minutes. MacMosh's menu button sends the same command, but the button itself was not part of that test. The setting is one Apple doesn't document, so read the battery and heat sections before you depend on it.

Two names come up throughout. The **workhorse** is the laptop that runs your work. The **daily Mac** is the one you sit at, with the MacMosh menu.

## Which one do I use?

| Option | What it costs | What is known | Pick it when |
|---|---|---|---|
| Leave the lid open | Nothing | Works, per the design: once set up, the Mac doesn't sleep on power. The setup checklist line `It stays awake on power and wakes for network access` covers it. | You have room for an open laptop. It is the simplest choice. |
| MacMosh's lid-closed mode | Nothing | The setting it changes was tested by hand on one MacBook Pro on 2026-11-22: lid closed, on power, no display, awake and reachable for 43 minutes. The menu button and `macmosh power` were not part of that test. It uses a setting Apple doesn't document. | You want the lid shut with no extra hardware, and the Mac stays plugged in on a hard surface. |
| An external display (Apple's own way) | A display, plus an external keyboard and mouse | Documented by Apple. Apple's pages describe working on the display with the lid closed; they don't say whether the Mac stays awake when nobody is using it. Not tested by this project. | You already have a display for the workhorse, or you want the setup Apple supports. |
| A display emulator plug (a "dummy plug" that imitates a display) | About $10 | Apple says nothing about these plugs. Not tested by this project. | Only if you want to try it yourself. This guide can't tell you whether it works. |

## What lid-closed mode does

Lid-closed mode changes one power setting on the workhorse with `pmset`, which is macOS's own command for power settings. To turn the mode on, MacMosh runs:

```
sudo pmset -a disablesleep 1
```

To turn it off, it runs `sudo pmset -a disablesleep 0`.

- **Apple doesn't document `disablesleep`.** It is not in the `pmset` manual on macOS 27.3, although the program accepts it.
- **`-a` means every power source.** The manual says `-a` applies a setting to battery, charger (wall power) and UPS alike. That is why the setting matters on battery too (see below).
- **It needs root, and MacMosh doesn't.** Changing any `pmset` setting needs root, so the command starts with `sudo`. MacMosh itself never runs as root. It runs this one command on the workhorse over ssh, and you type the workhorse's password into ssh; MacMosh can't see it. The command is fixed text: nothing you type and nothing the workhorse reports is pasted into it.
- **It is for laptops only.** For a Mac with no battery, MacMosh says `This setting is for laptops. This Mac has no battery, so it has no lid to close.`
- **It stays on after a restart** until you turn it off.

## Turn on lid-closed mode from the menu

Before you start, plug the workhorse into power and put it on a hard, flat surface.

1. **Open the MacMosh menu on the daily Mac.**
   The workhorse's first line says `workhorse · Ready`, with your workhorse's name in place of `workhorse`. Under it, right after `Restart…`, is `Turn on lid-closed mode…`.

2. **Click `Turn on lid-closed mode…`.**
   A terminal tab opens and shows what it is about to run:

   ```
   This runs on workhorse:
   sudo pmset -a disablesleep 1
   Keeps the Mac running with its lid closed. It must stay plugged in: the setting also stops sleep on battery, so a closed Mac in a bag keeps running until its battery is empty. A closed Mac runs hotter. The setting stays on after a restart until you turn it off.
   ssh asks for the Mac's password, for sudo. You are typing into ssh; MacMosh can't see it.
   Type yes to run it:
   ```

3. **Read it, then type `yes` and press Return.**
   Anything other than `yes` stops here with `Nothing was changed.` After `yes`, ssh asks for a password.

4. **When ssh asks for a password, type the workhorse's login password.**
   You should see a line that ends in `Lid-closed mode: on`, such as:

   ```
   Sleep on power: 0 · Wake for network access: 1 · Restart after a power cut: not listed · Lid-closed mode: on
   ```

5. **Look at the menu again.**
   The summary line now includes `Lid-closed mode on`, and the button reads `Turn off lid-closed mode…`. If the menu still shows the old text, click `Check now`.

6. **Close the workhorse's lid.**
   The menu should keep saying `Ready`. In this project's test, `macmosh status` and ssh reached the workhorse for the whole 43 minutes.

## Turn it on from the command line

`macmosh` below is the command inside the app: `/Applications/MacMosh.app/Contents/Helpers/macmosh`.

1. **Run `macmosh list`.**
   You should see one line per workhorse, such as `workhorse (id) · alex@192.168.1.20 · paired`: its name, its id in brackets, the user and address, and `paired`. The last word is `not paired` if the workhorse isn't paired.

2. **Run `macmosh power workhorse lid on`**, with your workhorse's name or id in place of `workhorse`.
   You should see the same lines as in step 2 above, ending in `Type yes to run it:`.

3. **Type `yes`, then the workhorse's password when ssh asks for it.**
   You should see the line that ends in `Lid-closed mode: on`.

## Check that it is on

Any one of these is enough.

- **The menu.** The summary line includes `Lid-closed mode on`, and the button reads `Turn off lid-closed mode…`.
- **`macmosh status` on the daily Mac.** For a workhorse that is `Ready`, it prints the same summary line.
- **The workhorse itself.** Open a desk from the menu and run `pmset -g`. Reading settings needs no password. Look for a line that says `SleepDisabled` followed by `1`. Don't look in `pmset -g custom`: it never lists this setting, before or after you turn it on. Plain `pmset -g` shows the settings currently in use, and that is where this one appears.

MacMosh reads the same `SleepDisabled` line. A Mac where the setting was never turned on has no such line, and MacMosh shows that as off.

## Turn it off

1. **Click `Turn off lid-closed mode…` in the menu**, or run `macmosh power workhorse lid off`.
   The tab shows `sudo pmset -a disablesleep 0` and the words `The Mac sleeps again when its lid closes.`

2. **Type `yes`, then the workhorse's password when ssh asks for it.**
   You should see a line that ends in `Lid-closed mode: off`.

3. **Look at the menu.**
   The summary line includes `Lid-closed mode off`, and the button reads `Turn on lid-closed mode…` again.

If you are at the workhorse without the daily Mac, you can type `sudo pmset -a disablesleep 0` in Terminal there instead. Type your password when sudo asks for it. To check, run `pmset -g` and look at the `SleepDisabled` line.

What `pmset -g` prints after the setting is turned off was not recorded in this project's test. MacMosh treats a `0` and a missing line both as off.

If you take MacMosh off the workhorse with `macmosh remove`, it doesn't turn lid-closed mode off. It lists `sudo pmset -a disablesleep 1` under `Power settings changed through MacMosh, in case you want to put them back:`. Turn the mode off first if you don't want it left on. Once you turn it off through MacMosh, that command drops off the list.

## If something's off

| What you see | What to do |
|---|---|
| No `Turn on lid-closed mode…` in the menu | Only a laptop that is `Ready` gets it. If the workhorse's first line says something else, follow the line under it first. A Mac with no battery never gets the button. |
| `Ready, sign-ins off` and a `Fix…` button | The lid-closed button is still there, after `Restart…`. The two are separate. |
| `Say whether to turn lid-closed mode on or off` | You left off the last word. Type `macmosh power workhorse lid on` or `macmosh power workhorse lid off`. |
| `Nothing was changed.` | You typed something other than `yes`. Start again. |
| `ssh ended with exit code …, so nothing was recorded.` | If the setting didn't change, check the password and start again. |
| `The change ran, but a new check couldn't read the values.` | Click `Check now` in the menu, or run `macmosh status`, and look at the summary line. |
| The menu says `Can't reach it` after you close the lid | Open the lid. Check that the workhorse is plugged in and that `pmset -g` on it shows `SleepDisabled` followed by `1`. |

## Use an external display (Apple's way)

Apple documents a closed lid only with a display connected. These steps follow the order on Apple's page for M3 MacBook Air and MacBook Pro with two displays. This project has not tried them with MacMosh, and Apple's pages don't say whether the Mac stays awake when nobody is using it. Apple's page gives the order of the steps; it doesn't say what you should see at each of the first three.

1. **Connect an external keyboard and mouse or trackpad.**

2. **Connect the workhorse to power.**
   If the display provides power to the Mac, Apple says a separate power adapter isn't needed.

3. **Connect the display.**
   If the display needs power, plug it in to an outlet first. You may also need to turn it on.

4. **Close the lid.**
   You should be able to keep working on the display with the keyboard and mouse. Apple's words: "After you connect a display to your MacBook Pro, you can close the lid and continue to use it with connected accessories."

If the display stays dark, Apple suggests these steps:

- Make sure the Mac is connected to power and using an external keyboard and mouse.
- Disconnect the display from the Mac and from its power source, then connect it again.
- Put the Mac to sleep, then wake it. On a laptop you can close the lid for a few seconds, then open it again.

On a MacBook Air or MacBook Pro with M3 chip and two displays connected, Apple says opening the lid makes the second display go dark or disconnect.

## On battery, and before the Mac goes in a bag

With lid-closed mode on, assume the workhorse does **not** sleep on battery either. The `-a` in the command applies the setting to every power source, and MacMosh's own warning says that "a closed Mac in a bag keeps running until its battery is empty." That warning comes from a published report, not from this project: the workhorse was tested on power only. Another report says a laptop goes to sleep within a few minutes once the charger comes loose. The reports disagree, so plan for the worse case.

Before you put the workhorse in a bag:

1. **Turn lid-closed mode off**, from the menu or with `macmosh power workhorse lid off`.
   You should see the line that ends in `Lid-closed mode: off`.

2. **Check the menu.** The summary line includes `Lid-closed mode off`.

3. **Close the lid and pack it.**
   MacMosh's off text says `The Mac sleeps again when its lid closes.`, so the menu should soon show `Can't reach it`. This project has not watched that happen. If you need to be sure, shut the Mac down from the Apple menu instead.

A workhorse that stays plugged in spends long stretches on power, and Apple has two features for that. Apple says Optimized Battery Charging reduces wear on the battery by reducing the time the Mac spends fully charged; Charge Limit lets you cap the charge. Its page about them doesn't mention a closed lid.

- **Optimized Battery Charging** (macOS Big Sur 11 or later) learns your daily charging routine and can delay charging past 80% when it predicts the Mac will be on power for a long time.
- **Charge Limit** (macOS Tahoe 26.4 or later, on a Mac with Apple silicon) lets you set a limit between 80% and 100%. The Mac stops charging a few points short of it. With either feature, the Mac will still charge to 100% now and then.

## Heat

**What Apple says.** Apple doesn't say what a closed lid does to cooling. Its general advice for Mac laptops applies whatever the lid's position:

- Use the Mac on a stable surface with good ventilation; a hard, flat surface such as a table or desk is best.
- Don't use it in a bed, on a pillow or under bedding. Don't put anything over the keyboard or into any ventilation openings.
- On a soft surface its fans may run more, and when the room is hot they turn on sooner and run faster.
- Keep the room between 10° and 35° C (50° and 95° F). Apple adds that a Mac laptop can get warm during normal use.
- Remove any camera, palm rest or keyboard cover before you close the lid. Apple says material left on the display, keyboard or palm rest might interfere with the display when it's closed.

**What MacMosh says.** Its warning with the on command includes: "A closed Mac runs hotter."

**What this project saw.** After 43 minutes with the lid closed, the owner opened it and found the Mac "not much warmer". `pmset -g therm` on the workhorse said that no thermal warning level, performance warning level or CPU power status had been recorded. That is all: no temperature in degrees, no test under load, and no run longer than 43 minutes.

**What you can check yourself.** In a desk on the workhorse, run `pmset -g therm`. It needs no password. Apple's manual says it "shows thermal conditions that affect CPU speed" and that it is not available on all platforms. When nothing has been recorded it prints three lines that start `Note: No`. This project has not yet seen what it prints once macOS records a warning, and the project's own research found it isn't enough on its own to tell how hot the Mac is.

**What MacMosh doesn't do yet.** MacMosh doesn't show how hot the workhorse is. That is issue #91, "Show when a lid-closed workhorse runs hot", and nothing for it is built yet.

## What we tested, and what we did not

The test ran on 2026-11-22 on one MacBook Pro running macOS 27.3. The full record is in [`sittings/sitting-2-results.md`](sittings/sitting-2-results.md).

**What was done.** At 10:02 the owner typed `sudo pmset -a disablesleep 1` in a desk on the workhorse. At 10:05 he closed the lid, with the Mac on power and no display plugged in. He opened it at 10:48, after 43 minutes. The plan was 15 minutes; it ran longer because he stepped away.

**What was seen.**

- The workhorse did not sleep. Its power log has no sleep or wake entry between 10:00 and 10:49.
- The daily Mac reached it the whole time. In every check, `macmosh status` and ssh to each of the workhorse's three addresses succeeded, and the workhorse's key was the expected one every time.
- The workhorse's own log has 317 status lines between 10:05 and 10:49, and no two are more than 45 seconds apart.
- The screen was on when the lid was opened. Whether it was lit while the lid was closed is not known.
- `pmset -g` gained a line with `SleepDisabled` followed by `1`. `pmset -g custom` never listed it.
- After a full restart later that day, the setting was still on. The lid was open during that restart.

**What was not tested.**

- Turning the mode on or off with MacMosh's menu button or `macmosh power`. The test typed the command by hand; the button's screens in this guide come from the code.
- Running on battery with the mode on.
- Closing the lid with the mode off, to watch the workhorse go to sleep.
- A restart with the lid closed.
- Any run longer than 43 minutes, any run under load, or any temperature reading in degrees.
- Any other Mac model, chip or macOS version. The test record doesn't note the chip.
- What `pmset -g` shows after the mode is turned off.
- An external display or a display emulator plug with MacMosh.

**What others report.** Of five published write-ups the design collected, four say this setting keeps an Apple-silicon MacBook running with the lid closed and no display on macOS 26, and one says it no longer does. They disagree on whether the screen stays lit and whether the setting survives a restart. The project's own test is one run on one Mac, so treat it as a good sign, not a promise.

## Sources

Apple:

- Connect an external display to MacBook Pro: https://support.apple.com/guide/macbook-pro/apd8cdd74f57/mac
- If your external display is dark or low resolution: https://support.apple.com/en-us/102501
- Use dual monitors with your MacBook Air and MacBook Pro with M3 chip: https://support.apple.com/en-us/117373
- Keep your Mac laptop within acceptable operating temperatures: https://support.apple.com/en-us/102336
- About fans and fan noise in your Apple product: https://support.apple.com/en-us/101576
- Using a camera cover, palm rest, or keyboard cover on a Mac notebook: https://support.apple.com/en-us/102051
- About Optimized Battery Charging and Charge Limit on Mac: https://support.apple.com/en-us/102338
- Set sleep and wake settings for your Mac: https://support.apple.com/guide/mac-help/set-sleep-and-wake-settings-mchle41a6ccd/mac
- `man pmset` on macOS 27.3

Reports (not Apple):

- The setting also applies on battery: https://slack.green/en/blog/pmset-disablesleep
- A laptop sleeps within minutes once the charger comes loose: https://pasqualepillitteri.it/en/news/779/disable-laptop-sleep-lid-close-ai-agents
- The five write-ups summarised above: reference 16 in the [design](superpowers/specs/2026-11-18-macmosh-v1-design.md), section 8.5

This project:

- The test: [`sittings/sitting-2-results.md`](sittings/sitting-2-results.md)
- The design, sections 5.6, 7.10 and 8.5: [`superpowers/specs/2026-11-18-macmosh-v1-design.md`](superpowers/specs/2026-11-18-macmosh-v1-design.md)
- Heat: issue #91, "Show when a lid-closed workhorse runs hot"
- The commands and the words MacMosh shows: `Sources/MacMoshKit/Setup/PowerPlanner.swift`, `Sources/MacMoshKit/Setup/PowerFlow.swift`, `Sources/MacMoshKit/Menu/MenuModel.swift`, `Sources/MacMoshKit/Format/StatusFormat.swift`, `Sources/MacMoshKit/Setup/Removal.swift` and `Sources/macmosh/PowerCommand.swift`
