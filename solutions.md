# Rescu assessment — solutions

All seven bug tickets and all three features are done. Each ticket was done
on its own branch, with one logical change per commit, and merged into `main`
with `--no-ff`. `git log --graph` shows the work ticket by ticket.

- **Tests:** 38 unit/widget tests (`flutter test`). Every bug fix with logic
  that can be tested has a test that I first ran against the original code to
  confirm it fails.
- **Device checks:** Android emulator (Pixel 6 image, x86_64). Deep links,
  the timing behaviour and the request logs were all checked there.
- **Performance numbers:** taken from the app's VM service (the protocol
  DevTools uses), with a small probe in [`tool/perf/`](tool/perf/README.md).
  The probe reports frame timings and per-widget build counts.
- **Toolchain:** Flutter 3.27.0 (via fvm) and Java 17, as pinned. No package
  was upgraded or added. `fake_api_service.dart` and `assets/data/` are
  untouched.

> Caveat on the numbers: they come from an emulator, not a mid-range phone.
> The emulator renders on a software GPU, so raster times (~16 ms) mostly
> reflect emulator overhead. The UI-thread numbers and the rebuild counts are
> what the fixes change, and the rebuild counts don't depend on the device.

---

## Part A — Bugs

### RES-101 · Search shows results for the wrong query

**Root cause.** Every keystroke started a search, and the backend answers
broad (short) queries more slowly (`1200 − 280 × length` ms). So for
"sushi", the request for "s" can come back *after* the one for "sushi".
`_search` assigned every response to `results` unconditionally, so the last
response to **arrive** won, not the last query **sent**. The first response
to land also cleared `isLoading` while newer requests were still in flight.

**Fix.** Each request gets an incrementing id, and a response (or error) that
isn't the latest is dropped. Clearing the text box also invalidates in-flight
requests. A separate commit adds a 300 ms debounce, which only cuts load:
typing "sushi" now sends 1 request instead of 5.

**Alternatives rejected.**
- *Debounce alone* is the usual answer, but it doesn't fix the race: pause
  for 300 ms mid-word and two requests are in flight again.
- *Cancelling the previous Future* isn't possible, because Dart Futures can't
  be cancelled and the repository has no cancel token. Ignoring the stale
  result is equivalent and simpler.
- *Comparing the response's query to the text field* would couple the
  controller to the widget, and it breaks if the user types "sushi" again
  after "sush".

**Edge cases.** An error from a stale request is ignored too, otherwise it
could hide fresh results. Not handled: if the latest request fails, the
previous results stay on screen, which is the original behaviour.

**Test.** `test/search_deals_controller_test.dart` answers fake requests in
reverse order. All 3 cases fail on the original code.

### RES-102 · Crash after leaving My orders

**Root cause.** `PickupCountdown` started a `Timer.periodic` in `initState`
and threw the returned `Timer` away, so nothing could ever cancel it. After
the orders route was popped, the `State` was disposed but the timer kept
calling `setState` every second.

**Fix.** Keep the timer and cancel it in `dispose()`.

**Alternative rejected.** `if (mounted) setState(...)` makes the error go
away, but a periodic timer then leaks on every visit to My orders. That's
exactly the "hide the symptom" fix the brief warns about.

**Test.** `test/pickup_countdown_test.dart` removes the widget and pumps
time. Before the fix it fails with the exact `setState() called after
dispose()` error.

### RES-103 · Requests pile up the longer you browse

**Root cause.** `DealDetailsController.onInit` called
`ever(cartService.itemCount, …)` and threw away the returned `Worker`. I read
the GetX 4.7.3 source to confirm: `ever()` is a plain
`listener.listen(...)` on the Rx, and nothing ties it to the controller that
created it. `CartService` is permanent, so every deal page ever opened kept a
live subscription, plus a reference to its controller, after GetX had closed
and deleted that controller. Every cart change then fired
`GET /deals/:id` once for each of those pages.

**Fix.** Store the `Worker` and `dispose()` it in `onClose()`.

**Evidence.** On the emulator I opened 3 deals and backed out of each, opened
a 4th, and tapped "Add to bag": **4 requests before, 1 after**.

**Alternative rejected.** Using `GetxController`'s own workers or
`once`/`debounce` doesn't help; any subscription to a longer-lived object
needs an explicit owner. I also considered moving the availability re-check
into `CartService` (refresh only the deal that changed), which would be a
nicer design. I rejected it as scope creep for this ticket.

### RES-104 · Duplicate deals in the home feed

**Root cause.** `loadMore` did `_page++` and awaited page N+1. A pull-to-
refresh during that wait reset `_page = 1` and replaced the list with page 1.
When the stale page N+1 then arrived, `deals.addAll` appended it to the
*fresh* page 1. Later loads then fetched pages 2…N+1 again, which produced
duplicates and more items than the catalog has. A failure did `_page--`
after a refresh, which could also send `_page` to 0.

**Fix.**
1. Each refresh bumps a `_generation` counter. A page load or refresh that
   started under an older generation drops its result. `_page` only
   advances once a page has actually arrived, so the `_page--` rollback is
   gone.
2. A separate commit: a dropped load never calls `loadComplete()`, so the
   SmartRefresher footer could stay stuck in "loading". A refresh now
   completes the footer, which also clears a stale "no more data" state.

**Alternative rejected.** Blocking pull-to-refresh while a page loads works,
but it punishes the user for something that isn't their fault. De-duplicating
by id when appending hides the symptom, and the list would still be missing
pages.

**Test.** `test/home_controller_test.dart` answers the refresh and the page
load in both orders. The "page lands after refresh" case fails on the
original code. On the emulator I refreshed while page 2 was loading, then
scrolled to the bottom: pages 2 and 3 loaded normally.

### RES-105 · Home feed is janky and memory keeps climbing

Three contributing causes, one commit each:

1. **The whole screen rebuilt on every scroll frame.** `HomeController`
   pushed `scrollController.offset` into an Rx on every scroll event, and
   `HomeScreen` wrapped the *entire* Scaffold in one `Obx` that read it.
   Only two things depend on the offset: the app bar elevation (`> 4`) and
   the scroll-to-top button (`> 800`). The fix replaces the raw offset with
   two derived bools. Rx only notifies when the value changes, so they fire
   on threshold crossings, not per pixel. Each one gets its own `Obx`.
2. **The feed wasn't lazy.** `ListView(children: [...deals.map(DealCard)])`
   re-filtered the list and allocated a `DealCard` widget for every loaded
   deal (up to 122) on each rebuild. The fix uses `ListView.builder`, keyed
   by deal id. (Elements were already created lazily, so this is the
   smallest of the three wins.)
3. **Images were decoded at full size.** Every image is a 1600×1200 photo,
   decoded at full resolution: about 9.8 MB each with mipmaps, even for a
   996×420 card or a 504×236 rail tile. The fix makes `TheNetworkImage` pass
   `memCacheWidth`/`memCacheHeight` from its laid-out size × device pixel
   ratio. It constrains only one side (width for wide boxes, height for
   square or tall ones), so the aspect ratio is kept and `BoxFit.cover`
   never has to upscale.

**Before/after** (profile build, same scroll script):

| | before | after |
|---|---|---|
| UI thread per frame, avg / p90 / p99 | 2.24 / 3.70 / 6.10 ms | **0.94 / 1.56 / 4.36 ms** |
| `BUILD` phase avg | 0.75 ms | **0.02 ms** |
| Rebuilds during one swipe: `Scaffold` / `Obx` / `DealCard` / `CachedNetworkImage` | 14 / 14 / 75 / 127 | **0 / 2 / 2 / 2** |
| Card image decode size | 1600×1200 (~9.8 MB) | **996×747 (~2.9 MB)** |
| Rail image decode size | 1600×1200 | **504×378** |
| Images held by the 100 MB `ImageCache` | 13 | **35** |

How each row was measured:
- **Frames and rebuilds:** `tool/perf/measure.dart`. Rebuild counts come
  from `ext.flutter.profileWidgetBuilds`, the same switch as DevTools'
  "Track widget builds".
- **Image rows:** a temporary probe (never committed) using
  `debugOnPaintImage` and `ImageCache.currentSizeBytes`, over 40 swipes.
- **Oversized-image check:** with DevTools' "Highlight oversized images"
  on, every feed image rendered inverted before the fix
  (`docs/evidence/105_oversized_before.png`).

**What didn't work as evidence, and why:**
- **The "Highlight oversized images" toggle.** Images still render inverted
  after the fix. `BoxFit.cover` crops a 4:3 photo into a 2.4:1 card, so even
  a correctly sized decode holds more pixels than are visible, and that
  exceeds DevTools' 128 KB allowance. So I used decode sizes instead.
- **`dumpsys meminfo`.** It barely moved (+11.4 MB vs +10.9 MB over a deep
  scroll). On this emulator, decoded images live in host-GPU texture memory,
  which Android's PSS doesn't count (Graphics reports 0 kB). On a real phone
  that memory counts toward the process, which is the "memory keeps climbing
  until the OS kills the app" in the ticket.

**Alternatives rejected.**
- `AppBar.scrolledUnderElevation` (Material 3) would drop the scroll listener
  entirely, but it changes the visual style. I kept the original look.
- Resizing on the server or requesting smaller picsum URLs: the backend is
  off-limits.
- Raising `ImageCache.maximumSizeBytes` treats the symptom: it would just
  hold more 10 MB images.

### RES-106 · Wrong pickup times; "Pickup today" misses deals

**Root cause (two bugs).**
1. `DateTime.parse("…Z")` returns a **UTC** `DateTime`, and `DateFormat`
   prints whatever fields it holds. So a bakery opening at 06:00 Bangkok time
   (UTC+7, which is 23:00Z) was shown as "23:00 – 02:30". The backend team
   was right: the client never called `toLocal()`.
2. `isToday` compared `start.day` (the UTC day-of-month) with
   `DateTime.now().day` (local). Stores opening before 07:00 Bangkok time
   start on the *previous* UTC day, so they were filtered out. It also
   ignored month and year, so 15 January matched 15 February.

**Fix.**
- The model keeps the UTC instants. Comparisons between instants
  (`isOpenNow`, countdowns) don't depend on the time zone.
- `label` formats `toLocal()`.
- "Today" becomes "the window **overlaps** today's local calendar day". The
  catalog has overnight windows (22:00–01:00), and at 00:30 such a store is
  open now even though its window started "yesterday".
- `isTodayAt(DateTime now)` makes the clock injectable for tests.

**Alternatives rejected.**
- Converting to local inside `fromJson` mixes two meanings into one field
  (an instant plus a display value) and breaks the existing `isUtc` test.
- Showing times in the *store's* time zone (always UTC+7) would be right for
  a tourist whose phone is set to another zone. But the API doesn't send a
  per-store zone, so the client would have to hard-code +7 and duplicate
  backend knowledge. Device-local time is correct for the market's users.

**Edge cases.** Overnight windows, a different month with the same
day-of-month, and a UTC `now` are all tested. Not handled: a device whose
time zone differs from the store's shows the device's local time, as
decided above.

**Test.** `test/pickup_window_model_test.dart` has 8 cases. Against the old
code, the label test fails with the ticket's exact symptom
`'23:00 – 02:30'`, and 5 of the 8 cases fail. (They only fail in a non-UTC
time zone; see design question Q3.)

### RES-107 · Deep link opens to a crash

**Root cause.** In-app taps passed the whole `DealModel` as
`Get.arguments`, and the controller did `Get.arguments as DealModel`. A deep
link only carries the URL (`/deal?id=42&source=push`), so `arguments` was
`null` and the cast threw. The route already put the id in the URL
(`Routes.dealRoute`), but the page ignored it.

**Fix.**
- The route's `?id=` is the source of truth. `arguments` is only a preloaded
  copy for instant rendering; otherwise the page fetches `GET /deals/:id`.
- The page shows a spinner while loading, and "Try again" if the fetch fails
  or the id is invalid.
- A second commit: on a **cold start** from a push, Flutter opens the deep
  link as the *only* route, so Back closed the app. If the deal page is the
  first route, Back (and an app-bar back arrow) now replaces it with Home.

**Alternative rejected.** Having the deep-link handler fetch the deal and
then navigate with `arguments` only fixes the in-app simulator. A cold-start
Android link goes straight to the route and would still crash, and every
future entry point would have to remember the same trick.

**Evidence.** I reproduced the red crash screen via `adb` before the fix
(`docs/evidence/107_deeplink_before.png` / `…_after.png`).
After it, cold- and warm-start links open deal 42, "Add to bag" works, and
Back goes to Home in both cases.

---

## Part B — Features

### F-1 · Live flash-sale countdowns

**Design.**
- **`ClockService`:** one app-wide `Timer.periodic(1s)` exposing `now` as an
  Rx. 100+ countdowns cost one timer, not one each.
- **`FlashCountdownText`:** an `Obx` around a single `Text`, so a tick
  rebuilds only the mounted countdown strings. Format is `mm:ss`, or
  `hh:mm:ss` from one hour up. It rounds up, so it never shows `00:00`, then
  says "Expired".
- **`FlashExpiryBuilder`:** one `Timer` for the deal's end, rebuilding its
  subtree **once** when it fires.
  - Cards and rail tiles switch to a greyed, non-tappable "Expired" state.
  - The deal page disables "Add to bag" ("Flash sale ended").
  - The controller refuses to add an expired deal.
- **Bag expiry:** `CartService` keeps one timer per flash line, so expiry
  works even when no card is on screen. When it fires, the line is removed
  and the user sees a snackbar on whatever screen is open, plus a
  dismissible banner in the bag (in case they missed the snackbar).
- **Late timers:** Dart timers can fire late after the app was suspended
  (iOS pauses them), so the bag also runs `expireOverdue()` when it opens
  and before checkout.

**Evidence.**
- 5 idle seconds on Home: **30 `Obx` + 30 `Text` rebuilds** (6 mounted
  countdowns × 5 ticks) and **0** for `DealCard`, rail tile,
  `FlashDealsSection`, `ListView` and `Scaffold`.
- With 100+ deals in the feed, only the rows on screen exist (lazy list from
  RES-105), so the per-second cost scales with *visible* countdowns.
- On the emulator I added the 8-minute "Last-call Bakery Box" and waited:
  the line was removed with the notice
  (`docs/evidence/f1_bag_flash_expired.png`), and the rail tile shows
  "Expired".

**Alternatives rejected.**
- A `Timer` per countdown widget is simple, but it means 100+ timers, and
  each needs correct disposal (see RES-102).
- `StreamBuilder` on a periodic stream would work too, but `Obx` is the
  codebase's idiom.
- Putting the expiry check in the card's build via the clock would rebuild
  the whole card every second, which is exactly what the brief forbids.

**Edge cases.** A flash line removed before expiry cancels its timer (no
false notice). An expired deal can't be re-added from the bag's "+" or from
the details page.

### F-2 · Impression tracking

**Design.**
- **`ImpressionTracker`:** a `VisibilityDetector` around list items on the
  home feed, flash rail and search results. `position` is the index in that
  list.
- **`ImpressionService` (permanent):**
  - **One-second rule:** ≥ 50% visible starts a 1 s timer per (source,
    deal). Dropping below 50%, or leaving the tree (reported as 0), cancels
    it.
  - **Once per deal per session, across screens:** the deal goes into a
    session-wide set *when the event is queued*, before anything is sent. A
    slow or failed batch can never cause a repeat.
  - **Batching:** events go to `AnalyticsService` (the debug screen) and to
    a queue sent via `sendAnalyticsBatch` at 10 events, or 15 s after the
    first unsent event, whichever comes first.
  - **Failure and backgrounding:** a failed batch goes back to the front of
    the queue and retries on the next trigger. The queue is flushed when the
    app goes to the background.
- **Update interval:** `VisibilityDetector`'s interval is lowered from
  500 ms to 100 ms, so visibility changes are reported within about 0.1 s
  and the 1 s rule stays accurate.

**Performance** (profile build, 6 swipes):

| | UI frame avg | p99 | frames > 16 ms |
|---|---|---|---|
| before F-2 | 0.94 ms | 4.4 ms | 0 |
| F-2, 500 ms interval | 0.97 ms | 3.6 ms | 0 |
| F-2, 100 ms interval | 1.05 ms | 4.9 ms | 0 |

The differences are within run-to-run noise, so the 100 ms interval is
effectively free.

**Evidence.**
- On the emulator, deal 1 logged from the flash rail wasn't logged again
  from the feed.
- Fast flings logged nothing.
- Batches of 5 and 6 were posted 15 s after their first event.
- `test/impression_service_test.dart` covers the 1 s rule, a drop before
  1 s, once-per-deal across sources, the 10-event and 15 s triggers, and
  retry.

**Alternatives rejected.**
- Computing visibility by hand from `ScrollController` offsets: every list
  would need its own maths, and horizontal rails make it worse.
- Tracking inside `DealCard`: the card doesn't know its list or position,
  and the rail uses a different widget.

**Edge cases and decisions.**
- `position` is the index when the card first became visible.
- An impression in progress when the app is killed is lost, and so are
  queued events if the process dies before the background flush. There's no
  disk persistence; I judged it not worth it for analytics.

### F-3 · Stock reservations with optimistic UI

**Design.** Every bag line holds **one** reservation for its whole quantity
(`CartItemModel.reservation`, with `status` reserving/held/expired).

| Action | Optimistic UI | On success | On failure |
|---|---|---|---|
| Add | line appears, "Reserving…" | held | line removed + message |
| + (increase) | quantity +1 | reserve new qty, **then** release old hold | quantity restored, old hold kept |
| − (decrease) | quantity −1 | reserve new qty, then release old hold | reduced qty kept on old, larger hold |
| Remove / − to 0 | line removed | hold released | — |

- **Messages are non-technical.** A 409 says "Someone just grabbed the last
  Mystery Thai Feast. Please try again."; any other error says "We couldn't
  reach the store to hold …".
- **Order of operations.** I reserve the new quantity *before* releasing the
  old one, so a failure never leaves a line unheld.
- **Late holds don't leak.** A hold that arrives after its line was removed
  is released straight away.
- **One request per line.** +/− on a line are disabled while it's
  reserving.
- **Hold time left.** Each line shows "Held for mm:ss", turning orange in
  the last minute (warning, not just a countdown).
- **Checkout** passes the reservation ids (already wired in `OrderRepo`).

**Product decision: what happens when a hold expires while the user is in
the app.** The line stays in the bag, greyed out, with "Hold expired" and a
**Re-reserve** action. Checkout is blocked ("Re-reserve or remove expired
items to check out") until every line is held again. If checkout returns
**410** (the hold expired mid-checkout, or the server forgot it), the bag
marks those lines expired (or all of them, if none looks expired locally)
and says *"Re-reserve the highlighted items to check out. You have not been
charged."*

Why this and not the alternatives:
- **Silently re-reserving in the background** promises stock we may not
  get, and hides a real change in availability. The user finds out at the
  worst moment, or never.
- **Auto-removing the line** throws away the user's intent and surprises
  them.
- **Extending holds automatically while the bag is open** holds stock
  hostage from other users. That defeats the point of a 5-minute hold.
- With my choice, the bag always tells the truth, the user decides, and one
  tap usually fixes it.

**Evidence.**
- Emulator: add → `POST /reservations qty=1`; adding the same deal again →
  `qty=2` then `DELETE /reservations/res_1`; the 3rd reservation hit the
  backend's scripted 409 and the line was rolled back. The bag showed
  "Held for 04:38". After 5 minutes the line turned "Hold expired" and
  Checkout was disabled (`docs/evidence/f3_bag_hold_expired.png`).
  Re-reserve took a new `qty=2` hold and released the old one, and checkout
  then succeeded.
- `test/cart_service_reservation_test.dart` covers the optimistic add,
  rollback, failed and successful increase, release on remove, a late hold
  after removal, expiry → renew, and a 410.

**Edge cases not handled.**
- Holds aren't renewed or restored after an app restart, because the bag
  itself isn't persisted.
- With two lines, if one is renewed and the other is still expired, checkout
  stays blocked until both are resolved. That's intentional.

---

## AI usage log

**Tools.** Claude Code (Claude Opus) in the terminal for:
- reading the codebase and the GetX / pull_to_refresh / Flutter sources
- writing fixes, tests and commit messages
- driving the Android emulator through `adb`
- building the VM-service performance probe

I set the product decisions up front: which clock to show times in, how
expiry notices work, the reservation model, what happens when a hold
expires, and impression retry. The AI did the implementation, and I
reviewed it.

**Where the AI was wrong or misleading, and what I did instead:**

1. **The RES-104 fix was incomplete.** The first version dropped stale page
   loads, and the unit tests passed. But a dropped load never calls
   `RefreshController.loadComplete()`, so the footer could stay stuck in
   "loading" and paging would stop. The tests couldn't see it because they
   don't render the footer. It was caught by reading the `pull_to_refresh`
   source after the fix (`loadComplete` / `loadNoData` are the only things
   that move the footer out of loading), and fixed in its own commit, which
   was then checked on the emulator.
2. **The RES-105 evidence plan assumed DevTools' "Highlight oversized
   images" would clear after the fix.** It doesn't: with `BoxFit.cover`
   cropping, a correctly sized decode still exceeds the 128 KB allowance.
   The next idea, capturing `Flutter.ImageSizesForFrame` events from the VM
   service, produced no events in this setup either. I switched to a
   temporary `debugOnPaintImage` + `ImageCache` probe that logs actual
   decode sizes and cache contents, and kept it out of the commits.
3. **The image decode heuristic had an upscaling bug.** The first version
   decoded square boxes (64×64 order thumbnails) by width, so a 4:3 photo
   came out shorter than the box and `cover` would upscale it. I changed
   `w >= h` to `w > h` before committing.
4. **An overstated comment.** The AI wrote that a 100 ms visibility interval
   means an impression "can never fire more than 100 ms late or early". The
   "never early" part was wrong: a drop below 50% can also be reported up to
   100 ms late. I corrected the comment.
5. **Toolchain advice.** The AI recommended `fvm install 3.27.0`. On my
   connection, fvm's full git clone of Flutter was crawling (about 100 MB in
   15 minutes). I switched to the official 3.27.0 zip, downloaded in
   parallel range requests, verified it against Google's published SHA-256,
   and placed it where fvm expects it.
6. **Style.** The first diffs had long explanatory comments. I asked for
   minimal comments, with the reasoning moved here and into commit messages.

---

## Design questions

**Q1 — `GetxController` lifecycle vs widget `State` lifecycle.**
- **`GetxController`:** created by a route's `Binding` (lazily, on the first
  `Get.find`). `onInit`/`onReady` run once, and `onClose` runs when GetX
  deletes it, normally when its route is removed. It survives any number of
  rebuilds of the screen. It is *not* tied to a widget, and GetX only cleans
  up what it owns: anything the controller subscribes to must be released in
  `onClose`.
- **`State`:** lives exactly as long as its element in the tree.
  `initState`/`dispose` can run many times for the "same" screen (list items
  scroll out and back in, keys change), and resources must be released in
  `dispose`.
- **The bug:** RES-103 exists because the deal page's cart subscription was
  treated as if it would end with the screen. `ever()` is owned by the
  permanent `CartService`'s stream, so it outlived both the page and its
  controller. RES-102 is the `State`-side version of the same mistake: a
  timer started in `initState` was never cancelled in `dispose`.

**Q2 — When does one big `Obx` hurt, and how tightly to scope reactivity?**
An `Obx` re-runs its whole builder whenever *any* Rx read inside it changes.
That hurts when a high-frequency value (scroll offset, a clock tick, a
progress value) is read high in the tree. In RES-105 that rebuilt the whole
screen, including every visible card, on every scroll frame. My rules:
- Put the `Obx` around the smallest widget that actually displays the value.
- Turn high-frequency sources into the low-frequency values the UI needs,
  such as threshold booleans.
- Never read per-frame or per-second Rx above a list.
- For timed state changes that happen once (flash expiry), use a one-shot
  timer instead of watching a ticking clock.
- A big `Obx` is fine when everything inside really changes together and
  rarely (a loading/empty/content switch).
- Check with DevTools' widget rebuild counts rather than guessing.

**Q3 — A test that would have caught RES-106.**
- A unit test on `PickupWindowModel` fed **API-shaped** input (UTC
  ISO-8601 strings with `Z`), asserting the label and "today" for an
  early-morning store, an overnight store, and a date in another month.
  That is `test/pickup_window_model_test.dart`.
- **Code change needed:** "today" depended on `DateTime.now()` inside a
  getter. `isTodayAt(DateTime now)` makes the clock injectable.
- **The time-zone catch:** the bug only shows when local time isn't UTC, and
  Dart can't change the local zone inside a test. CI should run the suite
  with a pinned zone (`TZ=Asia/Bangkok flutter test` on Linux runners); a
  UTC CI box would pass the buggy code.
- **Next step:** inject a clock into `HomeController` (or pass `now` into
  `visibleDeals`), so a controller test can cover the "Pickup today" filter
  end to end.

---

## Time spent

<!-- TODO(candidate): replace with your own honest numbers. -->

- **Setup:** about 3 hours, mostly downloading Flutter 3.27.0 over a slow
  connection and the first Gradle build.
- **Bugs RES-101…107:** about X hours.
- **F-1…F-3:** about X hours.
- **Write-up:** about X hours.

**With one more day I would:**
- Persist the bag and its reservation ids across app restarts, re-checking
  hold status on launch.
- Inject a clock into `HomeController` and `CartService` for fully
  deterministic tests.
- Add widget tests for the bag's hold states.
- Re-run the RES-105 / F-1 profiles on a real mid-range Android phone.
  Emulator raster numbers aren't representative.
- Move deal-page availability re-checks into `CartService`, refreshing only
  the deal that changed instead of every open page.
