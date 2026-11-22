# Typr

Typr is a standalone iPhone dictation keyboard with a containing app, widgets and
Live Activity. Speech recognition runs on-device: Apple Speech (iOS 26+), Parakeet
V2 (iOS 18+), Whisper Large V3 Turbo, Parakeet V3, Orukeet or Cohere Transcribe
(explicit model downloads).
An explicit engine or language choice never silently falls back to another.

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
  If iOS reports another app playing audio before
  microphone activation, Typr leaves idle input cold. Dictate then opens Typr to
  start recording and interrupt that audio. Stopping or cancelling the recording
  fully releases the audio session with `notifyOthersOnDeactivation`, before
  transcription, so the interrupted app can resume. That capture ends the warm
  session; another cold dictation may require opening Typr again. When no other
  audio is playing, normal warm behavior is preserved without changing category
  options on a running input. Later playback/interruption events are also checked
  before restarting idle input. Detection is a momentary iOS audio signal, not a
  per-app media inventory; actual resumption is controlled by the media app and iOS.
  Experimental › **Keep other audio playing** follows Hex: recording mixes with other
  audio (`.playAndRecord`, never ducking), so media keeps playing, the warm session
  stays on while it plays, and the iPhone keeps its own sample rate (Typr resamples
  to 16 kHz). A warm input that keeps stopping by itself is restarted after 1 s, 2 s,
  4 s … up to 30 s instead of every 100 ms.
- **Microphone** picks the input. Automatic (default) records from a wired or USB
  headset, from the car in CarPlay, else from the iPhone; iPhone always uses the
  iPhone's. Neither turns on Bluetooth hands-free (HFP), so headphones and car kits
  never switch to call audio. Bluetooth also records from hands-free microphones, and
  its warm session holds that call audio for as long as it runs, between dictations
  too. After a phone call, a Bluetooth warm session resumes without hands-free until
  it ends. Experimental › **Warm mic on iPhone** follows Hex: the idle warm input stays
  on the iPhone and each dictation moves to the chosen microphone, which can end the
  warm session while Typr is in the background.
- Text processing combines vocabulary corrections, optional AI cleanup and
  formatting styles. Experimental › **Clean up what I say** (off by default, skipped in
  Verbatim) runs Hex's German word rules, with English rules added, before AI cleanup,
  line by line: it removes hesitations (äh, ähm, öh, hm; English um, uh), a conjunction or
  preposition said twice (und und) and self-repairs of a day, month or number set off by a
  marker (am Dienstag, ich meine, Mittwoch). Anything less certain stays as said: eh,
  pronoun, article and emphatic repeats, negated sentences, explanations and answers. Cleanup runs on-device with Apple Intelligence (iOS 26+,
  default) or, with your own Anthropic API key (stored in the Keychain), with
  Claude in the cloud; the plain transcript is used whenever cleanup is
  unavailable. Apple Intelligence cleanup is Hex's iOS cleaner at `d65b02d3` word for word
  (instructions, options, 2 s budget, answer check), with German words added to the
  check's reply, speaker and preamble rules; the share of the transcript a cleanup must keep
  is counted on the words as heard, as before; only a cleanup that keeps the words after
  one of Hex's English self-correction markers ("no wait", "I mean", "actually") may keep
  less; Claude gets Hex's dictation rewrite prompt word for
  word, with the host app and the text around the cursor as context. With Experimental ›
  Spoken punctuation (off by default), every style but Verbatim writes punctuation said by name as the mark in German and English ("Komma",
  "Fragezeichen", "Anführungszeichen unten/oben", "Klammer auf/zu", "question mark"),
  with Hex's guards so "ein wichtiger Punkt" or "zwei Komma fünf" stay as said. Experimental ›
  Format lists (off by default) writes "erstens … zweitens …", "Punkt eins … Punkt
  zwei …", "first … second …" as numbered lines, "Spiegelstrich"/"bullet" as "- " lines and
  "neue Zeile"/"new line" as line breaks, in every style but Verbatim; "Das ist erstens teuer
  und zweitens hässlich" or "das Wort Zeilenumbruch" stay prose. Style › End with a period
  (on by default) off drops every line's final period, and Style › Lowercase (off by default)
  lowercases everything, nouns and vocabulary included, as in Hex; neither touches Verbatim. With Experimental ›
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
  language of the sentence they were typed in (a word typed in both belongs to both; older
  ones too); with Experimental › **Learn each language separately** (off by default), a German
  sentence gets no learned completions typed only in English, and the other way round.
  Suggestions, autocorrect, swipe and predictions never offer slurs, and offer
  swear words only once Typr learned them or with Keyboard › Suggest swear words (LDNOOBW list as curated by Hex). Your iOS text replacements expand on space and punctuation also with Autocorrect off, take a capital you typed on the shortcut ("Mfg") and expand again after a revert kept the shortcut once. Unless a keyboard Anthropic key is stored (then Claude predicts), on iOS 26+
  with Apple Intelligence available for every enabled language, the on-device model adds up to three next-word predictions from the current paragraph before the
  cursor (1 s budget; on failure the count-based predictions stay).
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
