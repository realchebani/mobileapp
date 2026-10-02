// Evidence rules of the voice agent (plan §4.2), on top of the literal
// quote: a number must be in its quote (numeric anchor), a code must have
// one of its keywords there (lexical anchor), and a free text may only
// hold words that were said (coverage).

import { numbersIn } from "./french_numbers.ts";
import type { Anchors } from "./steps/types.ts";

/** Lower case, no accents nor punctuation, single spaces. */
export function normalize(text: string): string {
  return text
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

/** Whether [quote] is a literal (normalized) extract of [transcript]. */
export function quoteFound(quote: string, transcript: string): boolean {
  const q = normalize(quote);
  return q.length > 0 && ` ${normalize(transcript)} `.includes(` ${q} `);
}

/** Whether one of [stems] starts a word of [text] (normalized). */
export function hasStem(text: string, stems: readonly string[]): boolean {
  const t = ` ${normalize(text)} `;
  return stems.some((stem) => t.includes(` ${normalize(stem)}`));
}

/** Whether every code of [codes] has one of its keywords in [quote]
 * (codes without keywords, e.g. "autre", always pass). */
export function lexicalAnchor(
  anchors: Anchors | undefined,
  codes: string[],
  quote: string,
): boolean {
  if (!anchors) return true;
  const any = anchors["*"];
  if (any && !hasStem(quote, any)) return false;
  return codes.every((code) => {
    const stems = anchors[code];
    return !stems || hasStem(quote, stems);
  });
}

/** Whether [value] is one of the numbers said in [quote]. */
export function numericAnchor(value: number, quote: string): boolean {
  return numbersIn(quote).some((n) => Math.abs(n - value) < 0.005);
}

const STOPWORDS = new Set(
  (
    "les des une dans sur sous avec pour par est sont ils elles nous vous " +
    "qui que pas plus tres tout tous toute toutes son ses leur leurs mon mes " +
    "notre nos etait ete avoir etre fait mais donc car comme aussi bien cette " +
    "ces aux elle ont avait vers chez"
  ).split(" "),
);

const PHONE = /(?:\d[\s.-]?){8,}/;
const EMAIL = /[^\s@]+@[^\s@]+|arobase/i;

/** The share (0…1) of the meaningful words of [value] that were said in
 * [transcript] (same word, or same first 5 letters: plural, gender). */
export function coverage(value: string, transcript: string): number {
  const said = normalize(transcript).split(" ");
  const words = normalize(value).split(" ")
    .filter((w) => w.length >= 3 && !STOPWORDS.has(w) && !/^\d+$/.test(w));
  if (words.length === 0) return 1;
  const covered = words.filter((w) =>
    said.some((s) => s === w || (s.length >= 5 && w.length >= 5 && s.slice(0, 5) === w.slice(0, 5)))
  );
  return covered.length / words.length;
}

/** Minimum share of said words in a free text. */
export const MIN_COVERAGE = 0.8;

/** Whether a free text [value] only holds what was said: ≥ 80 % of its
 * words said, no number that was not said, no phone number nor e-mail. */
export function textCovered(value: string, transcript: string): boolean {
  if (PHONE.test(value) || EMAIL.test(value)) return false;
  const said = numbersIn(transcript);
  const own = numbersIn(value.replace(/[^0-9,.\s]/g, " "));
  if (own.some((n) => !said.some((s) => Math.abs(s - n) < 0.005))) return false;
  return coverage(value, transcript) >= MIN_COVERAGE;
}

/** Whether a name (a co-owner's) is plausible: letters, spaces, hyphens
 * and apostrophes only. */
export function isPersonName(value: string): boolean {
  return /^[\p{L}][\p{L}' ’-]{0,99}$/u.test(value.trim());
}
