# Retrasmetter — developer notes

A macOS menu bar app for learning English from the games you play.

```
game → capture subtitle area → Apple Vision OCR → clean text → translate (free) →
analyze words & expressions → mark known/learning → save with context → Anki
```

Everything in the core flow is free and local: Vision (OCR), NaturalLanguage (analysis),
Apple Translation (macOS 15+, on-device) or a LibreTranslate server on localhost, SwiftData
(storage), AnkiConnect on localhost. No API keys, no backend, screenshots never touch disk or network.

> **Status: written without a compiler.** This was authored on a Linux sandbox with no Swift
> toolchain, so it has never been built. Expect a handful of compile errors on the first
> `swift build`; send me the messages and I'll fix them.

## Build & run

Requires macOS 14+, Xcode 15+ (Xcode 16+ for Apple Translation).

```bash
Scripts/build-app.sh        # builds build/Retrasmetter.app (ad-hoc signed)
open build/Retrasmetter.app
```

or open `Package.swift` in Xcode and run it. The `.app` build is recommended because macOS
attaches the Screen Recording permission to the app bundle (running from Terminal attaches it to
Terminal). Ad-hoc signing may make macOS forget the permission after each rebuild; sign with a
free Apple Development certificate (`SIGN_IDENTITY="Apple Development: …" Scripts/build-app.sh`) to avoid that.

First run:
1. Menu bar icon → **Grant Screen Recording Access…**, enable the app, relaunch it.
2. **Select Capture Area**, drag over the game's subtitle box (it is remembered).
3. Press **⌥Q** in the game. The overlay appears without taking focus.
4. Click highlighted words (or chips) → Save / Learning / Known / Ignore / Anki.

Games must run windowed or borderless; exclusive fullscreen hides every overlay and blocks capture.

## Translation setup (free options)

| Option | Needs | Notes |
|---|---|---|
| Apple Translation | macOS 15+ | On-device. Settings → Translation → **Download / Check…** once to fetch the en→ru pack. |
| LibreTranslate on localhost | `pip install libretranslate` then `libretranslate --load-only en,ru --port 5001` (or Docker) | Works on macOS 14 too. Default URL `http://127.0.0.1:5001`. |

"Automatic" tries Apple first, then the local server. If neither is available you still get the
original sentence and highlighted vocabulary, plus a clear message.

### First launch, windows and menu bar
- First launch shows a 10-step onboarding wizard (language, game/target language, provider, API key, Screen Recording permission, capture area + **Test OCR**, hotkey, Anki, finish). *Settings → General → Run Setup Again* reopens it.
- Afterwards the app opens a main window: sidebar **Home / Vocabulary / History / Anki / Settings**. The menu bar icon opens a compact popover (current game, language pair, *Translate Now*, shortcuts, OCR/Translation/Anki status).
- Vocabulary is a table (Expression, Translation, Status, Times Seen, Game, Added) with filters All/New/Learning/Known/Anki and actions Mark as Known / Learn / Ignore / Add to Anki / Delete. History shows details and extracted vocabulary for the selected dialogue.

### Optional cloud providers: DeepL and OpenAI
Both need your own API key, entered in onboarding or Settings → Translation (with **Test Connection** and a *How do I get a key?* help sheet). OpenAI is billed separately from a ChatGPT subscription; the model name is in Settings → Advanced. Both fall back to Apple Translation / the local server on failure.

### Optional: DeepL
Pick *DeepL* in Settings → Translation and paste your own API key (stored in the macOS Keychain, never in files).
Keys ending in `:fx` use the free endpoint. Only recognized text is sent. If DeepL fails (no key, quota, offline),
the app falls back to Apple Translation and then the local server. Note: DeepL's free API plan may be unavailable to new accounts.

## Interface language & overlay position
- Settings → General → *Interface language*: System default, English, Русский, Deutsch, Türkçe, Español, Français. Switches live.
  To add a language: add a case in `Localization/L10n.swift` and a `L10n+xx.swift` dictionary (English text is the key; missing entries fall back to English).
- Settings → Overlay → *Position*: above/below the capture area, top/center/bottom of the screen, or *Where I last dragged it*.
  Drag the overlay by its background to move it — the spot is remembered and the mode switches to the last-dragged position. *Show preview* shows a sample.

## Anki

Install the AnkiConnect add-on (code `2055492159`), keep Anki open. Settings → Anki → **Test
connection** lists your decks and note types. Anki localizes built-in note-type names (e.g. a Russian
UI), so pick them from the menus. Any note type with ≥2 fields works: the first gets the sentence
(target expression bold, or as a cloze), the second gets expression, translation and the sentence translation.

## Architecture

```
App/              composition root (AppState), pipeline (DialogueProcessingCoordinator), menu bar app, WindowManager
Capture/          CaptureRegion, ScreenCaptureManager (ScreenCaptureKit), region selection UI
OCR/              OCRService protocol, VisionOCRService, OCRTextCleaner
Translation/      TranslationService protocol, Apple / Local(LibreTranslate) / Fallback chain
LanguageAnalysis/ LanguageAnalyzer protocol, NaturalLanguage analyzer, PhraseDetector, DifficultyEstimator, WordGlossService
Vocabulary/       SwiftData VocabularyItem, VocabularyStatus, repository, manager (known-word system), list UI
Anki/             AnkiService protocol, AnkiConnectService, card builder
Overlay/          non-activating NSPanel controller, SwiftUI overlay, word detail card
Hotkeys/          Carbon global hotkey
History/          DialogueRecord, repository, history UI
Settings/         SettingsView        Models/ AppSettings, Language        Services/ PermissionManager, GameContextManager
```

Every pipeline stage is injected into the coordinator as a protocol, so OCR, translation or
analysis engines can be swapped (other providers are just more `TranslationService`s
behind the same factory; paid ones are never required).

### Deviations from your spec (and why)

- **Swift Package + build script instead of an `.xcodeproj`**: I can't generate Xcode projects reliably here. Open `Package.swift` in Xcode if you want a project.
- **Windows via AppKit (`WindowManager`), not SwiftUI `Window` scenes**: scenes can auto-open at launch; this app must start silently in the menu bar.
- **Word detail card is inline in the overlay, not a SwiftUI popover**: system popovers open their own window and can activate the app, stealing focus from the game. `VocabularyPopoverView` keeps the requested name.
- **Carbon `RegisterEventHotKey` for the hotkey**: needs no Accessibility permission and consumes the key. Change it in Settings.
- **The analyzer returns *all* candidates; `VocabularyManager.suggestions` filters them.** That keeps the analyzer pure and makes the known-word logic (below) live and testable.
- **Apple Translation goes through a hidden SwiftUI host window** because on macOS 15 a `TranslationSession` can only be obtained via `.translationTask`.
- **On macOS 14, Translation.framework is absent.** The code compiles it conditionally, but SwiftPM links it strongly; to launch on macOS 14 build in Xcode and set Translation.framework to *Optional*, or use the LibreTranslate provider on 15+ only.

### Known-word system

- `known` / `ignored` → never suggested again.
- `learning` / saved (`unknown`) → always surfaced when they reappear (cyan), `timesSeen` and `dateLastSeen` updated.
- never seen → suggested only if `difficulty ≥ threshold` (Settings → Learning).
- Expressions (`count on somebody`, `be supposed to`, …) rank above single words and win the highlight when they overlap; their individual words remain available as chips.
- Context is always stored: sentence, its translation, game, first/last seen.

### Modes

`Translation` is the default. `Learning` (translation hidden until "Show full translation") and
`Immersion` (no automatic translation, "Translate" on demand) are only a few lines in the overlay and
coordinator, so they are already switchable in Settings, but the learning-specific UX is not built out.

## Limitations & next steps

- Difficulty is a heuristic (common-word list + length), not CEFR. Add words to `~/Library/Application Support/GameLanguageCompanion/common-words.txt` to mark them easy; swap in a CEFR-based `DifficultyEstimating` later.
- The expression table has ~45 entries; extend `EnglishPhraseDetector.table`. Idioms and grammar notes are the natural place for an optional local/cloud LLM `LanguageAnalyzer`.
- Single-word translation is context-free (lemma translated alone); the full sentence translation shown beside it supplies context.
- Option+letter hotkeys were restricted on some macOS 15.x builds; if ⌥Q never fires, pick another modifier.
- Multi-monitor selection works (one dimming window per screen) but is lightly tested; the region is stored per display ID.
- No tests yet. `OCRTextCleaner`, `EnglishPhraseDetector` and `VocabularyManager.suggestions` are pure and the best first targets.

## Reading Mode (visual-novel / JRPG dictionary layer)

- **Passive monitoring** watches only the dialogue area (ScreenCaptureKit stream, cheap change detection, wait until the typewriter text settles, OCR cooldown, dedupe, ≤ 4 checks/s). Frames stay in memory, never on disk.
- **⌥Q** (configurable) toggles **Reading Mode**: a transparent layer over the dialogue. Click a word or drag across several words → a small popup with the in-context translation, 🔊 pronunciation, **+ Anki** and **More** (Translate Entire Sentence, Explain via OpenAI if a key is set, Learn / Known / Ignore). Esc, the hotkey again, or a click outside closes things.
- **Games** screen: one profile per game — game window, window-relative dialogue area, languages, Test OCR, Activate, Delete.
- **Anki**: duplicates are detected by an expression tag ("Already in Anki" → *Add this context* / Cancel); the card front is the sentence with a blank plus the expression, the back has the expression, translation, full sentence, its translation and the game.
- **Vocabulary** counts "Times Selected" and shows the Anki status.
- Settings → Monitoring: on/off, checks per second, stability delay, OCR cooldown, Save Dialogue History.

Note: this version has not been compiled by the author — if Xcode/`swift build` reports errors, send them over.

## Release / DMG

```
Scripts/release.sh                       # dist/Retrasmetter.app + .dmg (ad-hoc signed, local testing)
DEVELOPER_ID="Developer ID Application: Name (TEAMID)" Scripts/release.sh   # signed, hardened runtime
DEVELOPER_ID=... NOTARY_PROFILE=retrasmetter-notary Scripts/release.sh            # + notarized and stapled
```

One-time notarization setup (no credentials are stored in the repo):
`xcrun notarytool store-credentials retrasmetter-notary --apple-id <id> --team-id <TEAMID> --password <app-specific-password>`

The DMG contains the app and an Applications shortcut (install `create-dmg` via Homebrew for a styled window).
Unsigned local build: on first launch right-click the app → Open. Then onboarding starts; grant Screen Recording and relaunch once.
The icon lives in `Support/AppIcon.icns` (source: `Support/AppIcon.png`).
Test checklist: launches outside Xcode · onboarding · Screen Recording flow · DMG drag to /Applications · launches from /Applications.

## Vocabulary vs Anki

The local vocabulary is the primary database; Anki is an optional export. In the Reading Mode popup **+ Vocabulary** saves with one click (→ *Added ✓*, later *✓ In Vocabulary*); **+ Anki** saves to the vocabulary first if needed. Repeated selections update *Times Seen* and add new contexts.
