// Numbers said in French, as the STT writes them: digits ("38", "38,5",
// "320 000", "320 k", "2 m 50") or words ("trente-huit", "deux mille
// douze", "quatre-vingt-dix-huit", "trois cent vingt mille", "deux mètres
// cinquante", "douze et demi"). Used by the numeric anchor of the voice
// agent (plan §4.2): a number the model extracts must be found in its
// quote.

const SMALL: Record<string, number> = {
  zero: 0,
  un: 1,
  une: 1,
  deux: 2,
  trois: 3,
  quatre: 4,
  cinq: 5,
  six: 6,
  sept: 7,
  huit: 8,
  neuf: 9,
  dix: 10,
  onze: 11,
  douze: 12,
  treize: 13,
  quatorze: 14,
  quinze: 15,
  seize: 16,
  vingt: 20,
  vingts: 20,
  trente: 30,
  quarante: 40,
  cinquante: 50,
  soixante: 60,
};

const HUNDRED = new Set(["cent", "cents"]);
const THOUSAND = new Set(["mille", "milles", "k", "ke"]);
const MILLION = new Set(["million", "millions"]);
const METRE = new Set(["m", "metre", "metres", "mètre", "mètres"]);

/** Lower case, no accents, hyphens and apostrophes as spaces; "320 000"
 * and "1 250 000" (thousands groups) joined when [group]. */
function tokens(text: string, group: boolean): string[] {
  let t = text
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[  ]/g, " ");
  if (group) {
    t = t.replace(
      /\b(\d{1,3})((?:[ .]\d{3})+)(?![\d,])/g,
      (_, head: string, rest: string) => head + rest.replace(/[ .]/g, ""),
    );
  }
  t = t.replace(/(\d)(k|ke|m|m2|m²)\b/g, "$1 $2").replace(/€/g, " ");
  return t.split(/[^a-z0-9,.]+/).map((w) => w.replace(/^[,.]+|[,.]+$/g, ""))
    .filter((w) => w.length > 0);
}

function parseDigits(token: string): number | null {
  if (!/^\d+([.,]\d+)?$/.test(token)) return null;
  return Number(token.replace(",", "."));
}

function decimalOf(value: number): number {
  const digits = String(value).length;
  return value / 10 ** digits;
}

/** Whether a small number or a ten [v] can extend [current] (French
 * composition: "dix-sept", "soixante et onze", "cent douze"). */
function canAppend(current: number, v: number): boolean {
  if (current === 0) return true;
  const r = current % 100;
  if (v >= 20) return r === 0;
  if (r === 0) return true;
  if ([20, 30, 40, 50].includes(r)) return v <= 9;
  if (r === 60 || r === 80) return v <= 19;
  // "dix-sept", "soixante-dix-huit", "quatre-vingt-dix-neuf".
  if (r === 10 || r === 70 || r === 90) return v <= 9 && v > 0;
  return false;
}

/** Every number of [text] (see the file header), in order of appearance;
 * a number may appear several times. */
export function numbersIn(text: string): number[] {
  const found: number[] = [];
  for (const group of [true, false]) found.push(...scan(tokens(text, group)));
  return found;
}

function scan(words: string[]): number[] {
  const found: number[] = [];
  let total = 0;
  let current = 0;
  let active = false;
  /** Whether the running number ends with a digit token (digits do not
   * add up: "12 11 et 10" are three numbers). */
  let lastDigit = false;
  let lastSmall = -1;

  const flush = () => {
    if (active) found.push(total + current);
    total = 0;
    current = 0;
    active = false;
    lastDigit = false;
    lastSmall = -1;
  };

  for (let i = 0; i < words.length; i++) {
    const w = words[i];
    const digits = parseDigits(w);
    if (digits !== null) {
      flush();
      current = digits;
      active = true;
      lastDigit = true;
      continue;
    }
    if (w === "et" && active) {
      // "soixante et onze", "douze et demi".
      const next = words[i + 1];
      if (next === "demi" || next === "demie") {
        found.push(total + current + 0.5);
        i++;
        flush();
        continue;
      }
      if (next !== undefined && next in SMALL && !lastDigit) continue;
      flush();
      continue;
    }
    if (w in SMALL) {
      const v = SMALL[w];
      if (active && !lastDigit && v === 20 && lastSmall === 4) {
        current += 76; // quatre-vingt(s)
        lastSmall = 20;
        continue;
      }
      if (!active || lastDigit || !canAppend(current, v)) {
        flush();
        active = true;
      }
      current += v;
      lastSmall = v;
      continue;
    }
    if (HUNDRED.has(w)) {
      if (!active || lastDigit) {
        flush();
        active = true;
      }
      const r = current % 100;
      current = r > 0 && r < 20 ? current - r + r * 100 : current + 100;
      lastSmall = -1;
      lastDigit = false;
      continue;
    }
    if (THOUSAND.has(w) && active) {
      total += (current === 0 ? 1 : current) * 1000;
      current = 0;
      lastDigit = false;
      lastSmall = -1;
      continue;
    }
    if (w === "mille") {
      flush();
      total = 1000;
      active = true;
      continue;
    }
    if (MILLION.has(w) && active) {
      total += (current === 0 ? 1 : current) * 1_000_000;
      current = 0;
      lastDigit = false;
      lastSmall = -1;
      continue;
    }
    if (w === "virgule" && active) {
      // "trente-huit virgule cinq".
      const before = total + current;
      flush();
      const rest = scan(words.slice(i + 1, i + 4));
      if (rest.length) found.push(before, before + decimalOf(rest[0]));
      else found.push(before);
      continue;
    }
    if (METRE.has(w) && active) {
      // "2 m 50", "deux mètres cinquante": 2,50 m.
      const before = total + current;
      flush();
      found.push(before);
      const rest = scan(words.slice(i + 1, i + 3));
      if (rest.length && rest[0] > 0 && rest[0] < 100 && Number.isInteger(rest[0])) {
        found.push(before + rest[0] / 100);
      }
      continue;
    }
    flush();
  }
  flush();
  return found;
}

/** Whether [value] is one of the numbers of [quote] (to the hundredth). */
export function numberInQuote(value: number, quote: string): boolean {
  return numbersIn(quote).some((n) => Math.abs(n - value) < 0.005);
}
