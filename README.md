# Sip

A water bottle on your desktop that fills as you drink. Sip sits on the
wallpaper like a system widget, behind your windows and on every Space. The
water in it moves: waves roll, bubbles rise, fish swim, and every drink pours
in from the neck and splashes.

Built for Apple Silicon, macOS 14.2+. Uses Liquid Glass on macOS 26+ and a
frosted material below that. A small ring in the menu bar shows today's
percent. There's no Dock icon until you open one of Sip's windows (Settings,
Insights); then it acts like a normal app, with its menus in the menu bar
and ⌘-Tab, until the window closes.

Also inside the same app: a **system widget** for the desktop and
Notification Center (small, medium, large, with tappable cups) and two
**Control Center buttons** (Log Water, Quick Log).

## Build and run

```bash
./install.sh                    # build, replace /Applications/Sip.app, relaunch
./build.sh                      # build only, into .build/Sip.app
./test.sh                       # 139 SipCore tests, plus the animation guard
```

The app is built by `Sip.xcodeproj`, which needs Xcode because App Intents
(Siri, Shortcuts, Spotlight, the Focus filter) are extracted at build time.
The project uses synchronized folders: a new file under `Sources/Sip` is
picked up with no project edits. `Package.swift` holds what builds and tests
from a shell: the `SipCore` logic, its tests, and the `sip` command.

Everything is signed by Xcode with the Apple Development identity of the
team in `Sip.xcodeproj` (`DEVELOPMENT_TEAM`; override with `SIP_TEAM=…`). The
widget extension and Control Center controls need that; macOS ignores them
from self-signed apps. Settings, history and the login item belong to the
bundle id, so `./install.sh` keeps them.

Builds stay in `.build` (hidden from Spotlight) and are unregistered from
Launch Services right after, so the only Sip macOS knows is the one in
`/Applications`. Building in the Xcode app goes to `.build/xcode-ide` for the
same reason (set per user in the workspace settings). Only one Sip runs at a
time: the copy in `/Applications` asks any other running copy to quit, and
any other copy shows the installed one and quits itself. The command-line target is called `SipCLI` (product `sip`):
a target named `sip` next to the app `Sip` shared a build folder on a
case-insensitive disk and linked the wrong code into the app.

## The bottle

The water is a small physics simulation, drawn with Core Animation:

- **Level** springs toward your total with a slight overshoot.
- **Waves**: two layers out of phase, a bright meniscus, light shafts and
  drifting caustics.
- **Pouring**: the cap pops, droplets fall from the neck, each splashes,
  ripples and nudges the level up.
- **Slosh**: drag the widget and the water tips against the motion. Shake it
  and everything churns and fizzes.
- **Playful**: the cursor brushing the surface leaves ripples.
- **Layers**: coffee, tea, juice and milk settle as their own bands.
- **Pour it out**: drag down from the neck and the bottle tips over and
  empties your last drink (same as Undo).

**Nine bottles**: Classic, Sport, Carafe, Glass, Steel Flask (opaque, with a
window strip), Mason Jar (gold lid, embossed glass), Gallon Jug (with a
handle), Lab Flask, and **Your Design**, shaped with sliders (body, shoulder,
waist, neck, base, cap). Any bottle can carry a printed label and a glass tint.

**Alive**:

- **Fish** live in the water. One at first, another at 7, 30 and 100 days in a
  row. They swim up to drink when you pour, slow down when you're behind,
  and sleep on the bottom at night.
- **A plant** in a pot beside the bottle grows a leaf for each good day of the
  last two weeks, flowers on a 7-day streak and droops when you're behind. A
  drop arcs into it whenever you drink.
- **Time markers**: gold marks on the glass show where you'd ideally be by
  9 AM, 11 AM, 1 PM… The next one is lit, green once you're past it.
- **Weather on the glass** (from your city's hourly forecast): frost creeps
  in when it's cold, raindrops run down when it's raining, condensation
  thickens when it's humid, heat haze rises on hot days.
- **Festivals and seasons**: Diwali lights strung across the shoulder, Holi
  colours in the celebration, monsoon rain, winter frost, Christmas snow on
  the cap, New Year fireworks.
- **Ice** on hot days, an optional **lemon** slice, **steam** after tea or
  coffee.
- **Night**: after bedtime the water dims, the fish sleep and the bottle
  draws less often.
- **Celebrations** when you reach your goal: confetti, fireworks, a crown
  splash, a bubble storm or a rainbow wave (or "Surprise me"). Streak
  milestones get fireworks; a level-up gets a rainbow.

## Using it

- **Click the bottle** to log your default cup; **drag up** to pour any amount.
- **Quick-add cups** log a fixed amount; **Finished my bottle** logs a full one
  of your bottle's size, counted as "2/4" toward the goal.
- **Point at the widget** for its **⋯** button, or **right-click** it: every
  cup, Custom Amount, Undo, Size, Bring Forward, Show/Hide, Insights, Share
  and Settings.
- **Click the ring in the menu bar** for the panel: today's numbers, today's
  challenge, every cup, a custom amount, a coach tip, buddies, today's list and
  a Settings button. Right-click it for the full menu.
- **Open Sip from Spotlight** (or Launchpad, Finder or the Dock) to get
  Settings.
- **⌃⌥W** logs the default cup from any app. **⌃⌥⇧W** brings a buried widget
  forward for a moment, or shows and hides it. **⌃⌥Space** opens the
  quick-log box ("330 tea", "2 glasses", "1.5 L", "half a bottle").
- Logged from somewhere you can't see the widget (a hotkey, Siri, the command
  line, your phone)? A small **HUD** drops in at the top of the screen.

### Sizes

Small, Medium, Large and **Extra Large** (732 × 376, like the macOS widget).
Extra Large adds a second column: today's score, caffeine in your body, the
daily challenge, a coach tip, and your buddies or the last 12 weeks.

## Coaching

- **Weekly schedule**: a different goal on some weekdays, and workout days
  with a bonus (500 ml by default).
- **Weather**: a hot day raises the goal by 250–750 ml.
- **Coach**: patterns from your last four weeks, e.g. "60% of your water comes
  after 4 PM", "weekends run 30% lower", "on coffee days you drink less
  water", and goal suggestions you can accept with a click (up when it comes
  easily, a stepping stone when you keep missing).
- **Caffeine in your body**: a half-life model (5 h by default) shows what's
  still in you and when it'll be under 50 mg, with a curve in Insights.
- **Hydration score**: 0–100 a day from amount, how evenly you spread it,
  caffeine and the last seven days.
- **Reminders**, each with Log and Snooze:
  - **smart timing**: only when you'd fall behind an even pace, never outside
    waking hours, never after the goal;
  - **wind-down**: none in the last hour before bed (adjustable);
  - **last call**: 2.5 h before bed if you're behind, in glasses;
  - **morning glass**: an hour after waking if you haven't started;
  - **day planner** (optional, reads your calendar): today's remaining goal
    spread into the free gaps between meetings, front-loaded; reminders come
    at those times;
  - **meeting heads-up**: ten minutes before meetings of 45 minutes or more;
  - **workouts**: a rehydrate reminder after "Gym" or "Run" on your calendar,
    and the workout bonus on that day's goal;
  - **quiet times**: a due reminder waits while you're on a call, in a
    meeting, away, presenting full screen, or in a Focus that has Sip's
    filter.

## Play

- **Levels**: XP for every drink, plus bonuses for reaching your goal, your
  streak, an early start and challenges. 30 levels, from Droplet to Poseidon.
  XP is computed from history, never stored, so it's always right, even
  across synced Macs.
- **Daily challenge**: one small goal a day, sized to your own numbers. For
  example, a share of your goal before noon, six separate drinks, a drink in six
  different hours, or no coffee after 2 PM.
- **Comeback**: missed a day? 110% of your goal the next day repairs the
  streak (once a month). Streak freezes still work as before.
- **Trophy shelf**: 35 badges with rarity (common, rare, epic, legendary).
- **Buddies**: pick a shared iCloud Drive folder; each person's Sip writes
  only today's percent, streak and level there (never history). Friends'
  bottles appear in the panel and on the Extra Large widget; click one to
  nudge them with a notification.
- **Recap**: "Your September in water" on the 1st of each month: litres (in
  bathtubs), goal days, longest run, favourite drink, thirstiest hour, best
  day and level, with an image to save. **Year in Water** from Settings.

## Siri, Shortcuts, Spotlight, the command line

- **App Intents**: Log a Drink (amount, unit, drink), Log a Cup, Log Water,
  Log a Coffee, Undo Last Drink, Finished My Bottle, Today's Hydration,
  Show the Sip Widget, Open Sip Insights.
- **Phrases with no setup**: "Log water in Sip", "Log a coffee in Sip",
  "How much have I drunk in Sip", "Undo my last drink in Sip".
- **Focus filter**: System Settings → Focus → a Focus → Focus Filters → Sip:
  pause reminders and the HUD, and calm the water, while that Focus is on.
- **`sip` command** (Settings → Siri, iPhone & More → Install, which links
  `~/.local/bin/sip` to the helper inside the app):

  ```bash
  sip log 330 tea
  sip status --json
  sip undo
  sip peek
  ```

  It talks to the running app in the background and prints today's status.
  **Raycast**: "Create Raycast Commands" writes script commands (log, status,
  undo, refill) to add as a script directory.
- **`sip://` links** for anything else: `sip://log?ml=330&drink=tea`,
  `sip://log?text=2 glasses`, `sip://log?cup=Glass`, `sip://refill`,
  `sip://undo`, `sip://quicklog`, `sip://peek`, `sip://show|hide|toggle`,
  `sip://settings`, `sip://insights`, `sip://share`.
- **iPhone and Apple Health**: an iPhone Shortcut appends a line to
  `iCloud Drive/Shortcuts/Sip Inbox.txt`; Sip logs it within seconds. The
  same Shortcut can log a Health "Water" sample. Steps are in Settings.
- **iCloud Drive sync** between Macs, merged so deletions stick.

## Settings

| Tab | What's in it |
|---|---|
| Goal | Daily goal and units, the calculator, weather, weekly schedule and workout days, your day (start, wake, bed), streak freezes |
| Drinks | Cups, your bottle's size, caffeine (rates, cut-off, limit, half-life), drink types and hydration factors |
| Appearance | The nine bottles, the designer, label and tint, liquid, fish, plant, time markers, ice, lemon, steam, weather on the glass, festivals, playful water, night dimming, celebrations, motion, card |
| Widget | Show, placement, size and scale, display, position, click action, pour-out, menu bar icon, HUD |
| Reminders | Timing, morning and evening, calendar (planner, meetings, workouts), quiet times, Sunday summary, the wobble nudge |
| Coach & Play | Coach tips and goal suggestions, levels, challenges, buddies, recaps |
| Sound & Keys | Sounds, volume, haptics, shortcuts, open at login |
| Siri, iPhone & More | Siri phrases, Focus, the `sip` command and Raycast, iCloud sync, the iPhone inbox, links |
| Data | Export/import CSV, edit any day, daily backups and restore, erase |

The sidebar has a search field ("frost", "caffeine", "raycast"…).
Onboarding uses the same controls as Settings, so the two can't disagree.

**Insights**: stat tiles, level and today's score (with its parts), the
coach, caffeine in your body, 30 days against your goal, a 12-week calendar,
what you drink, the trophy shelf, and when you drink. Plus the week card and
the recap.

## Data and privacy

Everything stays on this Mac unless you turn on iCloud sync or buddies:

- **History**: `~/Library/Application Support/Sip/history.json`, written
  atomically; each day keeps the goal it had.
- **Backups**: `…/Sip/Backups`, the last 7 days and one a week for a month,
  with Restore in Settings → Data.
- **Status** for the command line: `…/Sip/status.json`, only once the command
  is installed.
- **Calendar** (only if you turn on a calendar feature): today's events are
  read on this Mac; nothing is stored or sent.
- **Weather**: only your chosen city's coordinates go to Open-Meteo, once a
  day; the hourly forecast is cached for the day.

## What it costs

The water is drawn with Core Animation, driven by the display's refresh
signal. The glass, marks, labels, time markers and frost are images drawn
once; each frame only swaps a few layer paths, about 0.5–0.9 ms. Fish, rain,
lights and haze update in the same frame and pause with it.

One rule keeps it cheap, enforced by `test.sh`: **nothing in SwiftUI animates
forever.** A repeating SwiftUI effect redraws the whole card on every frame,
even under other windows (a looping flame once held Sip at 10% CPU and 124 MB).
Continuous motion lives only in the Core Animation bottle, which stops when
nobody can see it. SwiftUI uses one-shot, value-driven animations.

| Situation (medium widget, M4 iMac) | Frame rate | CPU (one core) | Memory |
|---|---|---|---|
| A drink: pour, toast, numbers | up to 60 fps | ~10–20% for about a second | small/medium peak ~28–32 MB; large/XL briefly ~115 MB of GPU buffers, released within 2 s |
| Visible, at rest, plain | 20 fps | ~1.3% | ~24 MB |
| Visible with fish, plant, markers, effects | 15–20 fps | ~1–1.8% | ~25–27 MB |
| Extra Large with everything | 20 fps | ~1.5% | ~29 MB |
| No input for 90 s, or at night | 10 fps | ~0.5% | |
| Covered by windows, asleep, hidden | nothing drawn | ~0.05% | ~27 MB |

Measured with the `bench` hook (footprint, not RSS). Two fixes from that
work: the plant's watering-drop animation and the week strip's animated
mini bottles redrew SwiftUI canvases on the CPU every frame of a pour; they
now redraw only when they change. Sounds are pre-rendered clips played with
`NSSound` instead of an audio engine built per drink.

Nothing new runs on a timer of its own: folders are watched with
file-system events, the calendar with change notifications, weather is
fetched once a day, buddies' cards are written at most once a minute, backups
once a day, and everything periodic rides one 30-second clock. Frame rates
are divisors of 60 and 120 Hz (asking for 24 fps got 30).

## Checking it from a shell

`SIP_DATA_DIR` points history at a scratch folder **and keeps settings in a
separate domain** (`com.himanshudixit.sip.scratch`), so test runs never
touch your real history or preferences.

```bash
open --env SIP_DEBUG=demo,goalmet,fish=3 --env SIP_DATA_DIR=/tmp/sip Sip.app --args -placement floating -widgetSize large
```

| Hook | What it does |
|---|---|
| `demo` | 60 days of made-up history, in memory only |
| `goalmet` | Today's goal already reached (the state benchmarks must cover) |
| `pour`, `celebrate` | Pour every 4 s; play the celebration |
| `fish=N`, `glass=frost\|rain\|heat\|humid`, `season=diwali\|holi\|monsoon\|winter\|christmas\|newYear`, `night` | Force a look |
| `size=s\|m\|l\|xl`, `style=…`, `theme=…`, `background=…` | Force a look for this launch |
| `settings[=tab]`, `popover`, `insights`, `onboarding`, `recap`, `whatsnew`, `hud` | Open that on launch |
| `cover` | Pretend the widget is buried under windows |
| `diagnostics` | Window level, frame, occlusion, totals, next reminder |
| `bench` | CPU, fps, ms/frame and memory footprint per interval, then quits (`SIP_BENCH_SECONDS`, `SIP_BENCH_EVERY`) |
| `idlefps=N`, `nodraw` | Benchmark knobs |
| `quicklog=330_tea`, `sharecard` | Preview the quick-log box; write the week card |

Any preference can also be overridden for one launch with `--args -key value`.

## Notes

- The widget is a non-activating `NSPanel` one level above the desktop icons;
  it never takes keyboard focus. Its panel opens as a floating card under it,
  and the widget lifts above other windows while it's open. The menu bar panel
  is the same card under the ring. `NSPopover` isn't used: pointed at the
  desktop-level panel it lands well above it, and from the menu bar it sized
  itself before the SwiftUI content had laid out, then grew up off the screen.
- The widget's hover handlers are on a plain `NSObject`, so they're exported
  as `@objc(mouseEntered:)` and `@objc(mouseExited:)`. Without the explicit
  names Swift exports `mouseEnteredWith:`, and AppKit threw an exception on
  every hover.
- **Covered** is checked directly once a second against the windows stacked
  above the card, because macOS only reports occlusion for opaque windows.
- **The system widget** (`Sources/SipWidget`) is sandboxed and reads only
  `~/Library/Application Support/Sip/widget.json`, a small summary the app
  rewrites when today's numbers change, then asks WidgetKit to reload. Its
  buttons and the Control Center controls hand actions back as `sip://`
  links, so they behave exactly like logging in the app.
- **Launch at login** uses `SMAppService`.

---

Designed by **Himanshu Dixit**.
