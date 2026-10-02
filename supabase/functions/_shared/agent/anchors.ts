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

export const PHONE_MASK = "[numéro masqué]";
export const EMAIL_MASK = "[e-mail masqué]";

// A French number (0X XX XX XX XX, +33 X XX…, digits grouped or not) or an
// international one; an e-mail written or spelled out (« jean point dupont
// arobase gmail point com »).
const PHONE_NUMBER =
  /(?:(?:\+|00)\s?33\s?\(?0?\)?\s?|\b0)[1-9](?:[\s.-]?\d{2}){4}\b|(?:\+|\b00)\s?\d{1,3}(?:[\s.-]?\d){7,12}\b/g;
const EMAIL_ADDRESS = /[\p{L}\d._%+-]+@[\p{L}\d.-]+\.[\p{L}]{2,}/gu;
const SPOKEN_EMAIL =
  /(?:\S+\s+(?:point|tiret)\s+)*\S+\s+(?:arobase|at)\s+\S+(?:\s+point\s+\S+)+/giu;

/** [text] with its phone numbers and e-mails masked (plan §5.1): applied
 * to every transcript, reply and note before it is kept. Years, prices and
 * surfaces are not phone numbers (a phone has 10 digits starting with 0, or
 * an international prefix). */
export function maskContacts(text: string): string {
  return text
    .replace(EMAIL_ADDRESS, EMAIL_MASK)
    .replace(SPOKEN_EMAIL, EMAIL_MASK)
    .replace(PHONE_NUMBER, PHONE_MASK);
}
