#!/usr/bin/env python3
"""Fill the gaps the shipped Kokoro lexicon leaves in this book.

sherpa-onnx >= 2.0 phonemises Kokoro from a lexicon alone — espeak-ng is no
longer consulted — and a word the lexicon does not know is not guessed at but
**dropped from the audio without a sound**. The page and the voice then say
different things, and every word position after the gap shifts.

In this corpus that is 2.19 % of all words: 6310 occurrences of 723 distinct
words, among them `god's` (434x), `created` (320x) and `illusions` (239x).
Almost all of them are ordinary inflections of words the lexicon *does* have:
it holds `exist` and `existing` but neither `exists` nor `existed`.

So derive them. English inflection is regular enough that the pronunciation of
`exists` follows from `exist` by rule, and the lexicon's own entries confirm
each rule:

    tests   = test  + s       (after a voiceless consonant)
    dogs    = dog   + z       (after a voiced one)
    wishes  = wish  + ᵻ z     (after a sibilant)
    needed  = need  + ᵻ d     (after t or d)
    wanted  = want  + ᵻ d

Run after fetching the voices; writes lexicon-acim.txt beside them.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
VOICES = ROOT / "ACIMAudio/Resources/Voices"
BASE = VOICES / "lexicon-us-en.txt"
OUT = VOICES / "lexicon-acim.txt"
CORPUS = ROOT / "ACIMAudio/Resources/acim.json"

SIBILANTS = {"s", "z", "ʃ", "ʒ", "ʧ", "ʤ", "tʃ", "dʒ"}
VOICELESS = {"p", "t", "k", "f", "θ", "s", "ʃ", "ʧ", "h"}
STRESS = {"ˈ", "ˌ"}
APOSTROPHES = "'’"
WORD = "[A-Za-z][A-Za-z'’]*"

# Section numbers read as numbers, not spelled out letter by letter.
ROMAN = {"ii": "two", "iii": "three", "iv": "four", "vi": "six", "vii": "seven",
         "viii": "eight", "ix": "nine", "xi": "eleven", "xii": "twelve",
         "xiii": "thirteen", "xiv": "fourteen", "xv": "fifteen"}


def read_lexicon(path):
    lex = {}
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            word, _, phonemes = line.rstrip("\n").partition(" ")
            if word and phonemes:
                lex[word] = phonemes.split()
    return lex


def last_sound(phonemes):
    """The final phoneme, ignoring stress marks."""
    for symbol in reversed(phonemes):
        if symbol not in STRESS:
            return symbol
    return ""


def plural(phonemes):
    tail = last_sound(phonemes)
    if tail in SIBILANTS:
        return phonemes + ["ᵻ", "z"]
    return phonemes + (["s"] if tail in VOICELESS else ["z"])


def past(phonemes):
    tail = last_sound(phonemes)
    if tail in {"t", "d"}:
        return phonemes + ["ᵻ", "d"]
    return phonemes + (["t"] if tail in VOICELESS else ["d"])


def progressive(phonemes):
    return phonemes + ["ɪ", "ŋ"]


def archaic_third(phonemes):
    """abideth, passeth — the King James forms the book quotes."""
    return phonemes + ["ᵻ", "θ"]


def archaic_second(phonemes):
    """betrayest, doest."""
    return phonemes + ["ᵻ", "s", "t"]


def comparative(phonemes):
    """baser, surer."""
    return phonemes + ["ə", "ɹ"]


def candidates(word):
    """Possible (base spelling, inflection) pairs, most specific first."""
    if word.endswith("'s") or word.endswith("’s"):
        yield word[:-2], plural
    if word.endswith("ies") and len(word) > 4:
        yield word[:-3] + "y", plural
    if word.endswith("ied") and len(word) > 4:
        yield word[:-3] + "y", past
    if word.endswith("es") and len(word) > 3:
        yield word[:-2], plural
        yield word[:-1], plural
    if word.endswith("s") and not word.endswith("ss") and len(word) > 2:
        yield word[:-1], plural
    if word.endswith("ed") and len(word) > 3:
        yield word[:-1], past          # created -> create
        yield word[:-2], past          # wanted  -> want
        yield word[:-3], past          # stopped -> stop
    if word.endswith("ing") and len(word) > 4:
        yield word[:-3], progressive
        yield word[:-3] + "e", progressive
        yield word[:-4], progressive
    if word.endswith("eth") and len(word) > 4:
        yield word[:-3], archaic_third
        yield word[:-2], archaic_third          # abideth -> abide
    if word.endswith("est") and len(word) > 4:
        yield word[:-3], archaic_second
        yield word[:-2], archaic_second
    if word.endswith("er") and len(word) > 3:
        yield word[:-2], comparative
        yield word[:-1], comparative            # baser -> base


def main():
    if not BASE.exists():
        sys.exit(f"{BASE} is missing — run Tools/fetch-voices.sh first.")
    lexicon = read_lexicon(BASE)

    # Parse the corpus rather than scanning it raw: in the file an escaped
    # newline is two characters, and a raw scan reads the next word as "nbut",
    # a word nobody ever wrote.
    def strings(node):
        if isinstance(node, str):
            yield node
        elif isinstance(node, dict):
            for value in node.values():
                yield from strings(value)
        elif isinstance(node, list):
            for value in node:
                yield from strings(value)

    text = " ".join(strings(json.loads(CORPUS.read_text(encoding="utf-8"))))
    words = sorted({w.lower() for w in re.findall(WORD, text)})
    missing = [w for w in words if w not in lexicon]

    # Two passes, so a possessive can build on a plural derived in the first.
    derived, unresolved = {}, []
    for _ in range(2):
        known = {**lexicon, **derived}
        unresolved = []
        for word in missing:
            if word in derived:
                continue
            if word in ROMAN and ROMAN[word] in lexicon:
                derived[word] = lexicon[ROMAN[word]]
                continue
            if word[-1] in APOSTROPHES and word[:-1] in known:
                derived[word] = known[word[:-1]]       # dreams' sounds like dreams
                continue
            for base, inflect in candidates(word):
                if base in known:
                    derived[word] = inflect(known[base])
                    break
            else:
                unresolved.append(word)

    # Every sound must be one the model has a token for. A rule that invents a
    # symbol would otherwise sail through here and be dropped at synthesis —
    # which is the very failure this file exists to repair. `ᵻ` and `ᵬ` differ
    # by one codepoint and not at all on screen.
    tokens = set()
    with open(VOICES / "tokens.txt", encoding="utf-8") as handle:
        for line in handle:
            symbol = line.split(" ")[0]
            if symbol:
                tokens.add(symbol)
    used = {sound for phonemes in derived.values() for sound in phonemes}
    unknown = sorted(used - tokens)
    if unknown:
        sys.exit(f"derived sounds the model has no token for: {unknown}")

    with open(OUT, "w", encoding="utf-8") as handle:
        handle.write("# Generated by Tools/build_lexicon_supplement.py — do not edit.\n")
        handle.write("# Inflections of words the shipped lexicon knows, which it\n")
        handle.write("# itself lacks. Without these the voice drops the word in silence.\n")
        for word in sorted(derived):
            handle.write(f"{word} {' '.join(derived[word])}\n")

    covered = len(derived)
    print(f"missing from the shipped lexicon: {len(missing)}")
    print(f"derived:     {covered}")
    print(f"unresolved:  {len(unresolved)}")
    if unresolved:
        print("  " + ", ".join(unresolved[:20]) + (" …" if len(unresolved) > 20 else ""))
    print(f"sounds used: {len(used)}, all known to the model")
    print(f"written: {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
