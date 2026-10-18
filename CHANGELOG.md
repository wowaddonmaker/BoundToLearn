# Changelog

All notable changes to BoundToLearn are documented here.

## [1.2.1] - 2026-10-17

### Changed
- **Icon Game start**: The song and the first falling note start together the moment the countdown ends. Songs with a quiet opening play it silently during the countdown, so the real music is playing on GO; the countdown runs up to 5 seconds for longer openings.
- **Icon Game life bar**: The life bar is much wider, using the room the score, combo and timer leave free.
- **Keybind Audit reach**: Keys for the right hand (U, I, O, P, J, K, L, M and everything right of them, the numpad and the arrows) now count as distant keys, like 7 to 0.
- **Keybind Audit modifier combos**: A Shift, Ctrl or Alt combo on a key that is already a stretch (6, Y, H, N) or a distant key scores lower than the key alone. Combos on keys near WASD still score in full.
- **Keybind Audit suggestions**: Distant keys and stretch combos mention when keys closer to WASD are still free.

### Fixed
- **Icon Game**: A different-sounding sting no longer plays over the first seconds of a song, and the music no longer fades in from silence.

---

## [1.2.0] - 2026-10-17

### Added
- **Keybind Quiz**: Try Again when a quiz ends starts a fresh run in the same mode.
- **Ping Trainer bests per difficulty**: Your best score is kept for each difficulty, so a high Easy score never stands in for a good Extreme run.
- **Tracking and Pet care filters**: Find Herbs, Find Minerals, Find Treasure and the Track spells, plus the hunter's Feed Pet, Tame Beast and Beast Training, are skipped by the tracker and the audit. Both are on by default in Options.

### Changed
- **Ping Trainer difficulty**: Easy is one large target at a time with six seconds to ping it, and each step up adds a target and shortens the time. Health drains steadily and every hit refills it, so standing still loses the round while steady play keeps you up.
- **Ping Trainer grade**: Comes from accuracy (S at 95%, A at 90%, B at 80%, C at 70%). Expired targets and pings into empty space count as misses, and a round that runs out of health is an F.
- **Ping Trainer start screen**: Shows the backdrop of the expansion you picked.
- **Keybind Audit modifiers**: Modifier combos are expected only once your abilities outnumber the keys around WASD, so a character with a dozen abilities is no longer told to use them.
- **Keybind Audit recommendations**: Grouped under each action bar, with General for the rest.
- **Keybind Audit navigation**: A Back button at the top left replaces the Settings, Scorecard and Back buttons. The results update by themselves when you change a keybind or an action bar, so Refresh is gone. The methodology opens from a link under the title.
- **Keybind Quiz piles**: The correct and wrong piles spread out more.
- **Scroll bars**: The game's own, shown only when there is something to scroll.

### Fixed
- **Icon Game**: Two notes in the same screen column no longer fall on top of each other.
- **Ping Trainer**: Start lights up as soon as the last ping is bound from its own key bar.
- **Ping Trainer**: 3D targets no longer stay invisible; a target whose model does not load shows its portrait.
- **Ping Trainer**: Target timer bars no longer overlap the health bar.
- **Ping Trainer**: Pings and texts from one round no longer show up in the next.
- **Windows**: Names in the world no longer show through window backgrounds.
- **Keybind Audit**: Skips the Hearthstone and profession spells such as First Aid, even with the tracker off.
- **Keybind Audit**: Says "No major issues found" when the score is below 100.

---

## [1.1.0] - 2026-10-15

### Added
- **WoW Forever**: BoundToLearn now loads on the WoW Forever beta from the same download. The Icon Game plays 36 tracks from Forever's own soundtrack in place of the ones that client does not have.
- **Icon Game menu**: The game opens on a menu with a looping demo, an action bar picker that lists only the bars you can see, and Start to go to track select.
- **Give feedback**: Every window has a Give feedback button that makes a report link with the screen's details filled in.
- **Share stats**: Post your stats to chat from the stats pages.

### Changed
- **The game's own look**: Every window now uses the game's own frames, buttons and checkboxes, so BoundToLearn matches the rest of your UI. Color themes are gone.
- **Options**: A sidebar window with Home and Feedback pages, and the reset buttons grouped together.
- **Pause**: Only in Practice mode. Entering combat ends a scored run.
- **Ping Trainer**: Start needs every ping bound, targets respawn when hit, and the sound option is now called Ping SFX.
- **Track select**: A Back to Menu button, and art picked per track.

### Fixed
- **Mouse binds**: In the Icon Game and the Keybind Quiz, an ability bound to a mouse button or the mouse wheel counts as a hit instead of casting the spell.
- **Two keybinds**: An action button with two keybinds accepts either one in the game and the quiz.
- **Pausing practice**: Pausing a practice round, or entering combat during one, gives your action bars back until you resume.
- **Layout**: Titles, buttons and text no longer overlap or sit on window borders.
- **Retail 12.1.5**: No longer listed as out of date.

---

## [1.0.1] - 2026-07-14

### Added
- **Keybind Tracker**: Real-time tracking of keybinds versus clicks, with a live ratio, encouraging feedback, and session summaries.
- **Practice Game**: A rhythm game where you press the correct keybind as abilities fall toward your action bar, across four difficulties. Includes a song-select carousel with per-expansion art, unlockable modifiers, a competitive mode with leaderboards, and per-song stats (best score, accuracy, combo, plays) searchable by track.
- **Keybind Quiz**: Timed and practice flashcard drills that hide your action bars for pure recall.
- **Keybind Audit**: A report card grading your keybind coverage, reachability, modifier usage, and anti-patterns, with tailored recommendations.
- **Click Blocking**: Optional enforcement that blocks clicking your action buttons so the keybind habit sticks.
- **Ping Trainer**: A quick minigame for practicing ability timing.
- **Statistics and achievements**: History trends, personal bests, per-difficulty breakdowns, and unlockable achievements.
- **Themes and settings**: Several color themes (blue by default) and a full options panel.

---
