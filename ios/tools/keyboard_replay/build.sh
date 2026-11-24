#!/bin/bash
# Builds keyboard-replay from the keyboard's shared sources in place. Prints the binary's path.
# Usage: build.sh [BUILD_DIR]   (default: ~/.cache/typr-keyboard-replay, outside every Git checkout)
set -euo pipefail

tool=$(cd "$(dirname "$0")" && pwd)
shared=$(cd "$tool/../../TyprShared" && pwd)
build=${1:-${XDG_CACHE_HOME:-$HOME/.cache}/typr-keyboard-replay}
case $build in /*) ;; *) build=$PWD/$build ;; esac
dir=$build
while :; do
  if [ -L "$dir" ]; then
    echo "build.sh: $build goes through the symbolic link $dir; use the real path" >&2
    exit 1
  fi
  [ "$dir" = / ] && break
  dir=$(dirname "$dir")
done
dir=$build
while [ ! -d "$dir" ]; do dir=$(dirname "$dir"); done
dir=$(cd "$dir" && pwd -P)
while :; do
  if [ -e "$dir/.git" ]; then
    echo "build.sh: $build is inside a Git checkout; choose a directory outside it" >&2
    exit 1
  fi
  [ "$dir" = / ] && break
  dir=$(dirname "$dir")
done
mkdir -p "$build"
build=$(cd "$build" && pwd -P)

if command -v xcrun >/dev/null 2>&1; then
  swiftc=(xcrun swiftc)
elif [ -x "$HOME/.local/share/swiftly/bin/swiftc" ]; then
  swiftc=("$HOME/.local/share/swiftly/bin/swiftc")
else
  swiftc=(swiftc)
fi

sources=(
  FullKeyboard/TyprAutocorrectEngine FullKeyboard/TyprAutocorrectEngine+Revision FullKeyboard/DeleteWordSlide FullKeyboard/TyprDictationUndo FullKeyboard/TyprFullKeyboardEngine FullKeyboard/GermanAutocorrect
  FullKeyboard/KeyboardBoundaryDecoder FullKeyboard/KeyboardBoundaryTouch FullKeyboard/KeyboardContextModel
  FullKeyboard/EmojiIndex FullKeyboard/KeyboardDiagnostics FullKeyboard/KeyboardKeyMap FullKeyboard/TyprKeyboardLayout
  FullKeyboard/KeyboardLearningSession FullKeyboard/KeyboardLearningStore FullKeyboard/KeyboardLetterMap FullKeyboard/KeyboardModelPredictions FullKeyboard/AnthropicPredictionProvider
  FullKeyboard/KeyboardMultipartSegmenter FullKeyboard/OnDeviceModelPredictions FullKeyboard/KeyboardSuggestionWorker FullKeyboard/KeyboardTouchInput
  FullKeyboard/KeyboardUndoWindow FullKeyboard/LexiconDelivery FullKeyboard/NeverSuggestWords FullKeyboard/PersonalBigramModel
  FullKeyboard/PersonalCompletionIndex FullKeyboard/PersonalTypingModel FullKeyboard/ProtectedPersonalLexicon
  FullKeyboard/TyprShiftStateMachine FullKeyboard/SpatialPrefixSearch FullKeyboard/SpatialWordDecoder
  FullKeyboard/SpatialWordRanking FullKeyboard/TyprSwipeDecoder FullKeyboard/SwipeEncoder
  FullKeyboard/TyprTrackpadCursor FullKeyboard/TypingLog FullKeyboard/TypingModelTypes Statistics/UsageStatistics
  Statistics/UsageStatisticsSession Statistics/UsageStatisticsStore DictationFeedback DictationFeedbackBridge
  DictationLanguage SpeechEngineChoice HexLanguageSettings FullKeyboard/Hex/KeyboardLanguage TyprSettings FullKeyboard/TyprFullKeyboardSettings FullKeyboard/TyprReturnKeyStyle
)
sources+=(
  FullKeyboard/KeyboardAutocorrecting FullKeyboard/TyprAutocorrectAdapter
  FullKeyboard/Hex/AdaptiveTouch FullKeyboard/Hex/AdaptiveTouchLabels FullKeyboard/Hex/AutocorrectEngine
  FullKeyboard/Hex/AutocorrectEngine+Accents FullKeyboard/Hex/AutocorrectEngine+Dictionaries
  FullKeyboard/Hex/AutocorrectEngine+Distance FullKeyboard/Hex/AutocorrectEngine+Vocabulary FullKeyboard/Hex/CzechTyping
  FullKeyboard/Hex/FullKeyboardEngine FullKeyboard/Hex/FullKeyboardEngine+Field FullKeyboard/Hex/FullKeyboardEngine+Hangul
  FullKeyboard/Hex/FullKeyboardEngine+HostText FullKeyboard/Hex/FullKeyboardEngine+Keys FullKeyboard/Hex/FullKeyboardEngine+Revert
  FullKeyboard/Hex/FullKeyboardEngine+Selection FullKeyboard/Hex/FullKeyboardEngine+SmartSpace
  FullKeyboard/Hex/FullKeyboardEngine+SwipeTyping FullKeyboard/Hex/FullKeyboardEngine+Trackpad
  FullKeyboard/Hex/FullKeyboardEngine+TyprCursorSliding FullKeyboard/Hex/FullKeyboardEngine+TyprTypingLog
  FullKeyboard/Hex/FullKeyboardSettings FullKeyboard/Hex/FullKeyboardTouch FullKeyboard/Hex/GermanCapitals
  FullKeyboard/Hex/GreekTyping FullKeyboard/Hex/HangulComposer FullKeyboard/Hex/KeyboardLayout FullKeyboard/Hex/KeyboardLayout+Typr
  FullKeyboard/Hex/KeyboardPadRows FullKeyboard/Hex/LanguageLearning FullKeyboard/Hex/OffensiveWords
  FullKeyboard/Hex/ShiftStateMachine FullKeyboard/Hex/SmartPunctuation FullKeyboard/Hex/SwipeDecoder FullKeyboard/Hex/TextChecking
  FullKeyboard/Hex/TrackpadCursor FullKeyboard/Hex/TrackpadSelection FullKeyboard/Hex/TypingDecoder
  FullKeyboard/Hex/TypingJournal FullKeyboard/Hex/TypingJournalLearning Hex/DictationCorrections Hex/DictationEditInference
  Hex/TypingLog/TypingLogEvent CustomVocabularySettings VocabularySpelling
)
files=()
for name in "${sources[@]}"; do files+=("$shared/$name.swift"); done
rm -rf "$build/trimmed"
mkdir -p "$build/trimmed"
for name in FullKeyboard/Hex/SwipeTyping FullKeyboard/Hex/AccentPicker; do
  out="$build/trimmed/$(basename "$name").swift"
  awk '/^(\/\/\/|@MainActor)/ { held = held $0 "\n"; next }
       /^final class [A-Za-z]+: UIView / { exit }
       { printf "%s", held; held = ""; print }' "$shared/$name.swift" > "$out"
  files+=("$out")
done

# Stand-in modules for the Apple frameworks this platform lacks.
modules=(UIKit)
[ "$(uname)" = Darwin ] || modules=(CoreFoundation CoreGraphics QuartzCore Darwin UIKit)
rm -rf "$build/modules" "$build/WordData"
mkdir -p "$build/modules" "$build/WordData"
objects=()
for module in "${modules[@]}"; do
  "${swiftc[@]}" -parse-as-library -swift-version 6 -module-name "$module" -I "$build/modules" \
    -emit-module -emit-module-path "$build/modules/$module.swiftmodule" \
    -c "$tool/Shims/$module.swift" -o "$build/modules/$module.o" >&2
  objects+=("$build/modules/$module.o")
done
cp "$shared"/FullKeyboard/WordData/keyboard-{de,en}.{words,tbg} "$build/WordData/"
cp "$tool"/../../TyprKeyboard/TypingModel/{de,en}.hextm "$tool"/../../TyprKeyboard/TypingModel/de.capitals \
  "$shared"/FullKeyboard/Hex/never-suggest.tsv "$build/"

"${swiftc[@]}" -O -swift-version 6 -I "$build/modules" "${files[@]}" "$tool"/Sources/*.swift "${objects[@]}" \
  -o "$build/keyboard-replay" >&2
echo "$build/keyboard-replay"
