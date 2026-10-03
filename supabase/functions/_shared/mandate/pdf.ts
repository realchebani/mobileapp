// EPIC-08 · PDF of the TEST mandate with pdf-lib (MIT): A4, standard
// Helvetica (WinAnsi, enough for French), the drawn signature (PNG), and a
// "SPÉCIMEN" watermark + notice on every page.

import {
  degrees,
  PDFDocument,
  type PDFFont,
  type PDFPage,
  rgb,
  StandardFonts,
} from "npm:pdf-lib@1.17.1";
import { type MandateFacts, mandateSections, SPECIMEN_NOTICE } from "./template.ts";

const A4: [number, number] = [595.28, 841.89];
const MARGIN = 56;
const BODY = 10.5;
const LEADING = 15;

/** WinAnsi characters above U+00FF (pdf-lib throws on any other). */
const WIN_ANSI_EXTRA = new Set(
  "€‚ƒ„…†‡ˆ‰Š‹ŒŽ‘’“”•–—˜™š›œžŸ".split(""),
);

/** [text] with the characters the standard fonts cannot encode replaced. */
export function winAnsi(text: string): string {
  let out = "";
  for (const char of text) {
    const code = char.codePointAt(0)!;
    if (char === " " || char === " ") {
      out += " ";
    } else if (char === "\n" || char === "\t") {
      out += " ";
    } else if ((code >= 0x20 && code <= 0x7e) || (code >= 0xa0 && code <= 0xff)) {
      out += char;
    } else if (WIN_ANSI_EXTRA.has(char)) {
      out += char;
    } else {
      out += "?";
    }
  }
  return out;
}

/** [text] cut into lines of at most [width] points. */
export function wrap(text: string, font: PDFFont, size: number, width: number): string[] {
  const words = winAnsi(text).split(" ");
  const lines: string[] = [];
  let line = "";
  for (const word of words) {
    const next = line ? `${line} ${word}` : word;
    if (line && font.widthOfTextAtSize(next, size) > width) {
      lines.push(line);
      line = word;
    } else {
      line = next;
    }
  }
  if (line) lines.push(line);
  return lines;
}

function watermark(page: PDFPage, font: PDFFont, bold: PDFFont): void {
  const [width, height] = [page.getWidth(), page.getHeight()];
  page.drawText("SPÉCIMEN", {
    x: width / 2 - 190,
    y: height / 2 - 120,
    size: 96,
    font: bold,
    color: rgb(0.85, 0.2, 0.2),
    opacity: 0.12,
    rotate: degrees(45),
  });
  page.drawText(winAnsi(SPECIMEN_NOTICE), {
    x: MARGIN,
    y: 28,
    size: 8.5,
    font,
    color: rgb(0.6, 0.1, 0.1),
  });
}

/** The PDF of the mandate; [signaturePng] is drawn when given. */
export async function renderMandatePdf(
  facts: MandateFacts,
  signaturePng: Uint8Array | null,
): Promise<Uint8Array> {
  const doc = await PDFDocument.create();
  doc.setTitle(winAnsi(`Mandat de vente (test) — SPÉCIMEN`));
  doc.setSubject(winAnsi(SPECIMEN_NOTICE));
  doc.setKeywords(["SPÉCIMEN", "test", facts.termsVersion, facts.mandateId]);
  doc.setProducer("Realesty");
  doc.setCreator("Realesty render-mandate");
  // Same facts → same bytes (a concurrent render stores an identical file).
  doc.setCreationDate(facts.signedAt);
  doc.setModificationDate(facts.signedAt);
  const font = await doc.embedFont(StandardFonts.Helvetica);
  const bold = await doc.embedFont(StandardFonts.HelveticaBold);
  const width = A4[0] - 2 * MARGIN;

  let page = doc.addPage(A4);
  let y = A4[1] - MARGIN;
  const ensure = (needed: number) => {
    if (y - needed < MARGIN + 20) {
      page = doc.addPage(A4);
      y = A4[1] - MARGIN;
    }
  };

  page.drawText(winAnsi("Mandat de vente — SPÉCIMEN"), {
    x: MARGIN,
    y,
    size: 18,
    font: bold,
  });
  y -= 30;

  for (const section of mandateSections(facts)) {
    ensure(LEADING * 3);
    page.drawText(winAnsi(section.title), { x: MARGIN, y, size: 12.5, font: bold });
    y -= LEADING + 3;
    for (const text of section.lines) {
      for (const line of wrap(text, font, BODY, width)) {
        ensure(LEADING);
        page.drawText(line, { x: MARGIN, y, size: BODY, font });
        y -= LEADING;
      }
    }
    y -= 8;
  }

  if (signaturePng) {
    const image = await doc.embedPng(signaturePng);
    const scale = Math.min(220 / image.width, 90 / image.height, 1);
    ensure(image.height * scale + 20);
    page.drawRectangle({
      x: MARGIN - 4,
      y: y - image.height * scale - 4,
      width: image.width * scale + 8,
      height: image.height * scale + 8,
      borderColor: rgb(0.8, 0.8, 0.78),
      borderWidth: 1,
    });
    page.drawImage(image, {
      x: MARGIN,
      y: y - image.height * scale,
      width: image.width * scale,
      height: image.height * scale,
    });
  }

  for (const each of doc.getPages()) watermark(each, font, bold);
  return await doc.save();
}

/** Hex SHA-256 of [bytes]. */
export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes as BufferSource);
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}
