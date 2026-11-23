# Typr

Typr is a standalone iPhone dictation keyboard with a containing app, widgets and
Live Activity. Speech recognition runs on-device: Apple Speech (iOS 26+), Parakeet
V2 (iOS 18+), Whisper Large V3 Turbo, Parakeet V3, Orukeet or Cohere Transcribe
(explicit model downloads).
An explicit engine choice never silently falls back to another. A German or English
dictation language that Apple's speech recognition lacks falls back to the language
it picks automatically, as in Hex; Experimental › Typr strict dictation language
keeps the choice strict instead. With no engine chosen, Typr picks one as Hex does:
from iOS 26 Apple Speech for every language it has (SpeechTranscriber, else
DictationTranscriber), English on Parakeet V2 only where Apple Speech has no
SpeechTranscriber and Parakeet fits in memory. Before iOS 26, Parakeet V2 takes
English where it has room and Apple's on-device recognizer takes everything else.
After two Parakeet loads in a row ended Typr, or one found too little memory,
Parakeet is set aside for a day and Typr no longer loads it at launch. When Typr
picks the engine itself, a preparation that says nothing for 30 s, or makes no
progress for 120 s, ends with Try again; a language Apple can't install here or
Parakeet without room moves on to the next pick, and a failed new pick keeps the
engine that worked, with a note on home. A download cut off in the background is
tried again when Typr returns.
Experimental › Hex experiments › **Multilingual model (Parakeet)** (off by default,
6 GB iPhones) downloads Parakeet Ultra (632 MB, 25 languages, also mixed in one
sentence) with progress, automatic retries and Try again. Typr tries loading it
beside the current engine when memory allows. If memory is too low or the load
fails, the current engine stays available. Try again when more memory is free,
or relaunch Typr to load an already compiled Ultra model directly. Ultra requires
an eligible dictation language and automatic engine selection. Once ready,
keyboard dictation opens Typr. Choosing an explicit engine stops Ultra's download
and retries. Choosing an unsupported language pauses the download until you return
to a supported one. Turning the experiment off deletes its files after any download
or load finishes stopping.

## How it works

- The app records and transcribes; the keyboard sends commands and inserts text
  through an App Group. The keyboard needs Full Access but never accesses the
  microphone or speech model, except with Experimental › **Keyboard dictation: Apple
  Speech in the keyboard** (off by default, iOS 26): without a warm mic, the keyboard
  records through a hidden web view (Hex's approach) and transcribes with Apple Speech,
  not Orukeet, streaming the audio into Apple Speech without storing it. A warm mic keeps
  the selected engine; low memory, a refused microphone or no Apple Speech model for the
  dictation language opens Typr as before.
- From a cold start, Dictate opens Typr to record, then returns to the host app.
  Host detection and return use private APIs with fallbacks. Transient surfaces
  such as share sheets require **Keep mic warm** instead.
- **Keep mic warm** keeps microphone input running so repeated dictations can start
  without leaving the keyboard. The duration is 5 minutes, 15 minutes or 1 hour.
  While it runs, touching the Typr key already holds the running input's audio in
  memory (at most 3 s, never on disk); the hold writes it as the start of the
  dictation, and a tap (space), slide or 1.5 s without a hold drops it.
  Holding the suggestion bar where no word or chip is dictates the same way, push
  to talk: lifting the finger stops it, and a tap there does nothing.
  Recording follows Hex: it mixes with other audio (`.playAndRecord`, never ducking),
  so music and videos keep playing, the warm session stays on while they play, and the
  iPhone keeps its own sample rate (Typr resamples to 16 kHz mono for every engine).
  Each dictation stops after one minute, as in Hex. A warm input that keeps stopping by
  itself is restarted after 1 s, 2 s, 4 s … up to 30 s instead of every 100 ms. If iOS
  refuses the microphone, dictation fails at once, as in Hex.
  Experimental › Typr variants restore Typr's earlier audio, each on its own:
  **Typr exclusive audio session** records input-only at 16 kHz and interrupts other
  audio. Then, if iOS reports another app playing audio before microphone activation,
  Typr leaves idle input cold; Dictate opens Typr to start recording and interrupt that
  audio, and stopping or cancelling the recording fully releases the audio session
  with `notifyOthersOnDeactivation` before transcription, so the interrupted app can
  resume. That capture ends the warm session. Detection is a momentary iOS audio
  signal; actual resumption is controlled by the media app and iOS.
  **Typr audio activation retries** tries a refused activation again for about five
  seconds, as iOS refuses it briefly after another app's audio (seen after WhatsApp
  voice messages).
- **Microphone** picks the input. Automatic (default) records from a wired or USB
  headset, from the car in CarPlay, else from the iPhone; iPhone always uses the
  iPhone's. Neither turns on Bluetooth hands-free (HFP), so headphones and car kits
  never switch to call audio. Bluetooth also records from hands-free microphones.
  As in Hex, the idle warm input stays on the iPhone's microphone and each dictation
  moves to the chosen one; when that needs a new input (a headset, CarPlay or
  Bluetooth), iOS can refuse it while Typr is in the background and the dictation fails.
  Experimental › **Typr keep selected warm microphone** keeps the warm input on the
  chosen microphone instead, so background dictation works there; with Bluetooth it
  holds call audio for as long as the warm session runs. After a phone call, such a
  Bluetooth warm session resumes without hands-free until it ends.
- Text processing combines vocabulary corrections, optional AI cleanup and
  formatting styles. Experimental › **Clean up what I say** (off by default, skipped in
  Verbatim) runs Hex's German word rules, with English rules added, before AI cleanup,
  line by line: it removes hesitations (äh, ähm, öh, hm; English um, uh), a conjunction or
  preposition said twice (und und) and self-repairs of a day, month or number set off by a
  marker (am Dienstag, ich meine, Mittwoch). Anything less certain stays as said: eh,
  pronoun, article and emphatic repeats, negated sentences, explanations and answers. Typr AI
  cleanup runs on-device with Apple Intelligence (iOS 26+,
  default) or, with your own Anthropic API key (stored in the Keychain), with
  Claude in the cloud; the plain transcript is used whenever cleanup is
  unavailable. Typr's Apple Intelligence provider uses Hex's iOS cleaner at `d65b02d3`
  (instructions, options, 2 s budget, answer check), with German words added to the
  check's reply, speaker and preamble rules; the share of the transcript a cleanup must keep
  is counted on the words as heard, as before; only a cleanup that keeps the words after
  one of Hex's English self-correction markers ("no wait", "I mean", "actually") may keep
  less; Claude gets Hex's dictation rewrite prompt word for
  word, with the host app and the text around the cursor as context.
  Experimental › Hex experiments › **Clean up with Apple Intelligence** is off by default.
  When on, app dictation uses Hex's on-device cleaner at `0c1c13d7` after spoken cleanup,
  in every style except Verbatim. An unavailable model, unsupported language, late reply or
  rejected answer keeps the text from that point in the pipeline. Turn the experiment off to
  resume using the saved AI & vocabulary settings.
- Formatting is Hex's shared `DictationPipeline`, the same in the app and in in-keyboard
  dictation: learned fixes, vocabulary and glossary, Clean up what I say, AI cleanup (app
  only), translation (app only), the style, the vocabulary's spellings again, Lowercase and
  French spacing. Style offers Hex's Polished, Casual (texting: lowercase start, no final
  period on a short message), Notes and Verbatim. Style › Format lists (on by default) writes
  "first … second …" and "bullet" as lines, in English and Spanish; German lists stay as
  said. Style › Spoken punctuation (on by default) writes "Komma", "Fragezeichen", "question
  mark" and other names as the mark in English, German, French, Spanish, Italian and
  Portuguese, with Hex's guards so "ein wichtiger Punkt" or "zwei Komma fünf" stay as said.
  Both skip Verbatim. Style › End with a period (on by default) off drops every line's final
  period, and Style › Lowercase (off by default) lowercases everything, Verbatim too, as in
  Hex. A style saved by an earlier Typr build that Hex doesn't have dictates as Polished.
  Experimental › **Typr German formatting rules** uses Typr's German and English list and
  punctuation rules ("erstens … zweitens …", "Punkt eins …", "Spiegelstrich", "neue Zeile",
  "Klammer auf/zu"), switched by Experimental › Format lists and Spoken punctuation instead
  of the Style settings. Notes keeps spoken colons and semicolons before bullets and line
  breaks, and drops a line-final spoken period. With Experimental ›
  Learn from my edits (off by default, needs Full Access), the full keyboard follows each
  dictation for a minute like Hex: kept, edited, rewritten, undone, deleted or dictated again.
  A word you replace with a similar one ("Wal" → "Wahl"), by editing or dictating again, is
  stored as that word pair only (up to three words a side, at most 200 pairs, never the
  dictation); fixed the same way twice, never contradicted and never fixed another way,
  later dictations write it so, before Custom vocabulary. Undo dictation and translated
  dictations teach nothing.
  AI & vocabulary lists the learned fixes to delete. Language › **Translate what
  I say** (off by default, iOS 26+) inserts German dictations in English or English ones in
  German with Apple's on-device Translation, after cleanup and before formatting in the
  output language. The languages are downloaded once from that page; a failed attempt is
  retried once in a new session, and both together get 5 s. Without the languages, on
  failure or timeout the dictation goes in as spoken and the keyboard says so for 8 s.
  The full keyboard adds German/English autocorrect and adaptive suggestions. With both
  languages on, a word only English knows takes the German umlauts or ß once the next word
  is German ("fur dich" → "für dich", Hex); one Delete takes it back.
  ; and ) correct the word before them like space and . , ? !. Experimental › **Words from
  context** follows Hex: its/it's, your/you're, there/their/they're and then/than follow the
  words around them, at their own space or the next word's, and German writes geht's and gibt's.
  Your Custom vocabulary words (each word of a phrase) are never corrected away and are
  completed in German and English sentences, after your contacts (Hex). Learned words carry the
  language of the sentence they were typed in only while every use leaned that way; a word
  used in both, first typed leaning neither, or learned before stays in both. With
  Experimental › **Learn each language separately** (off by default), a German sentence gets no
  learned completions or next-word predictions typed only in English that German does not know,
  and the other way round.
  Suggestions, autocorrect, swipe and predictions never offer slurs, and offer
  swear words only once Typr learned them or with Keyboard › Suggest swear words (LDNOOBW list as curated by Hex). Your iOS text replacements expand on space and punctuation also with Autocorrect off, take a capital you typed on the shortcut ("Mfg") and expand again after a revert kept the shortcut once. Unless a keyboard Anthropic key is stored (then Claude predicts), on iOS 26+
  with Apple Intelligence available for every enabled language, the on-device model adds up to three next-word predictions from the current paragraph before the
  cursor (1 s budget; on failure the count-based predictions stay).
  With Experimental › **Slide delete to remove words** on, pressing Delete removes
  one letter in ordinary text and holding it does not repeat. Slide left to delete
  words and back right to restore them. This also works in the split layout.
- While learning is on, the keyboard keeps a typing log on the iPhone: taps,
  corrections and the final word of the most recent 10,000 to 20,000 words, never
  from secure, URL or email fields. Keyboard › Words and privacy exports it as
  JSON with the keyboard's learning and your personal words for the desktop
  replay (`ios/tools/keyboard_replay`), or deletes it.

## Downloaded model preparation

Opening Typr automatically prepares an installed, explicitly chosen Whisper,
Parakeet V3, Orukeet or Cohere Transcribe model without downloading. On iOS 26+, Typr asks to continue that preparation after you
leave the app; older iOS has only limited background grace time. Opportunistic
maintenance can also prepare it while charging. iOS may decline, pause or stop
this work; there is no immediate post-update guarantee. Reopen Typr to retry.
Preparation never starts the microphone or audio keepalive.

Delete in Speech engine removes a downloaded model (Whisper, Parakeet V2,
Parakeet V3, Orukeet or Cohere Transcribe) with its partial downloads, after
releasing it if it is loaded. The chosen engine stays chosen: Whisper, Parakeet
V3, Orukeet and Cohere Transcribe then need Download again, Parakeet V2 downloads
again on next use. Apple Speech has no Delete; iOS manages its assets.

Cohere Transcribe has no language detection. German or English dictation passes
that language; automatic passes the first iPhone language Cohere supports, else
English.

Background Neural Engine access on iOS 27+ requires the Background Inference
capability (`com.apple.developer.background-tasks.continued-processing.inference`)
in the app's provisioning profiles; signing fails closed if it is missing.

## Build and test

Requires Xcode 26+ and XcodeGen 2.46.0+ on macOS:

```sh
cd ios
xcodegen generate
xcodebuild test -project Typr.xcodeproj -scheme Typr -destination "id=<SIM_UDID>"
```

Simulator tests exercise capture, handoff, text processing and keyboard logic.
Background microphone behavior, speech performance, host-app return, Live Activity,
Bluetooth/CarPlay and real typing quality require a physical iPhone.
CI and releases: [.github/typr/README.md](.github/typr/README.md).

## Origin and licenses

Based on [Hex by Kit Langton](https://github.com/anomalyco/hex), base commit
`cae389a8`, under MIT; the original [LICENSE](LICENSE) is preserved.
Other third-party code and data: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
