// Minimal CSV reader for the geo-dvf files (comma separated, header line,
// optional RFC 4180 quoting). Lines without a quote take the fast path.

/** Splits one CSV line into fields. */
export function splitCsvLine(line: string): string[] {
  if (!line.includes('"')) return line.split(",");
  const fields: string[] = [];
  let field = "";
  let quoted = false;
  for (let i = 0; i < line.length; i++) {
    const char = line[i];
    if (quoted) {
      if (char === '"') {
        if (line[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          quoted = false;
        }
      } else {
        field += char;
      }
    } else if (char === '"') {
      quoted = true;
    } else if (char === ",") {
      fields.push(field);
      field = "";
    } else {
      field += char;
    }
  }
  fields.push(field);
  return fields;
}

/** Parses [text] into records keyed by the header names. */
export function parseCsv(text: string): Record<string, string>[] {
  const lines = text.split(/\r?\n/);
  const header = splitCsvLine(lines[0] ?? "");
  const records: Record<string, string>[] = [];
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i];
    if (line.trim() === "") continue;
    const values = splitCsvLine(line);
    const record: Record<string, string> = {};
    for (let j = 0; j < header.length; j++) record[header[j]] = values[j] ?? "";
    records.push(record);
  }
  return records;
}
