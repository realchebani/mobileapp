// Audio helpers: some TTS models (Gemini TTS) only return raw PCM
// (signed 16-bit little-endian, mono, 24 kHz); players need a container.

/** TTS models that only answer in `pcm`. */
export function speechFormatFor(model: string): "mp3" | "pcm" {
  return model.startsWith("google/") ? "pcm" : "mp3";
}

/** Wraps raw 16-bit mono PCM in a WAV (RIFF) container. */
export function pcmToWav(pcm: Uint8Array, sampleRate = 24_000): Uint8Array {
  const header = new ArrayBuffer(44);
  const view = new DataView(header);
  const ascii = (offset: number, text: string) => {
    for (let i = 0; i < text.length; i++) {
      view.setUint8(offset + i, text.charCodeAt(i));
    }
  };
  ascii(0, "RIFF");
  view.setUint32(4, 36 + pcm.length, true);
  ascii(8, "WAVE");
  ascii(12, "fmt ");
  view.setUint32(16, 16, true); // fmt chunk size
  view.setUint16(20, 1, true); // PCM
  view.setUint16(22, 1, true); // mono
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * 2, true); // byte rate
  view.setUint16(32, 2, true); // block align
  view.setUint16(34, 16, true); // bits per sample
  ascii(36, "data");
  view.setUint32(40, pcm.length, true);
  const wav = new Uint8Array(44 + pcm.length);
  wav.set(new Uint8Array(header), 0);
  wav.set(pcm, 44);
  return wav;
}

// MPEG audio frame tables (kbit/s; index 0 = free, 15 = bad).
const BITRATES = {
  v1l3: [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],
  v2l3: [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
};
const SAMPLE_RATES: Record<number, number[]> = {
  3: [44100, 48000, 32000], // MPEG-1
  2: [22050, 24000, 16000], // MPEG-2
  0: [11025, 12000, 8000], // MPEG-2.5
};

export interface Mp3Info {
  /** Offset of the first frame (after an ID3v2 tag). */
  start: number;
  /** Frames walked until the end (or the first invalid header). */
  frames: number;
  /** Duration of the walked frames. */
  seconds: number;
}

/** Walks the MPEG Layer III frames of [bytes] (null when not an mp3). */
export function mp3Info(bytes: Uint8Array): Mp3Info | null {
  let p = 0;
  if (bytes[0] === 0x49 && bytes[1] === 0x44 && bytes[2] === 0x33) {
    p = 10 + ((bytes[6] << 21) | (bytes[7] << 14) | (bytes[8] << 7) |
      bytes[9]);
  }
  const start = p;
  let frames = 0;
  let seconds = 0;
  while (p + 4 <= bytes.length) {
    if (bytes[p] !== 0xff || (bytes[p + 1] & 0xe0) !== 0xe0) break;
    const version = (bytes[p + 1] >> 3) & 3;
    const layer = (bytes[p + 1] >> 1) & 3;
    const bitrateIndex = bytes[p + 2] >> 4;
    const rateIndex = (bytes[p + 2] >> 2) & 3;
    const padding = (bytes[p + 2] >> 1) & 1;
    const rates = SAMPLE_RATES[version];
    if (layer !== 1 || !rates || rateIndex === 3) break;
    const table = version === 3 ? BITRATES.v1l3 : BITRATES.v2l3;
    const bitrate = (table[bitrateIndex] ?? 0) * 1000;
    if (bitrate === 0) break;
    const sampleRate = rates[rateIndex];
    const samples = version === 3 ? 1152 : 576;
    const size = Math.floor((samples / 8) * bitrate / sampleRate) + padding;
    frames++;
    seconds += samples / sampleRate;
    p += size;
  }
  return frames === 0 ? null : { start, frames, seconds };
}

/**
 * Fixes the frame and byte counts of a Xing / Info header that disagree
 * with the stream (Kokoro declares ~1/3 of its frames, so players that
 * trust the header stop early). Returns [bytes] unchanged otherwise.
 */
export function repairXingHeader(bytes: Uint8Array): Uint8Array {
  const info = mp3Info(bytes);
  if (!info) return bytes;
  const window = bytes.subarray(info.start, info.start + 200);
  let tag = -1;
  for (let i = 0; i + 4 <= window.length; i++) {
    const text = String.fromCharCode(...window.subarray(i, i + 4));
    if (text === "Xing" || text === "Info") {
      tag = info.start + i;
      break;
    }
  }
  if (tag < 0 || tag + 16 > bytes.length) return bytes;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const flags = view.getUint32(tag + 4);
  // The header frame itself carries no audio.
  const frames = info.frames - 1;
  const repaired = bytes.slice();
  const out = new DataView(repaired.buffer);
  let offset = tag + 8;
  if (flags & 1) {
    if (view.getUint32(offset) !== frames) out.setUint32(offset, frames);
    offset += 4;
  }
  if (flags & 2) {
    out.setUint32(offset, bytes.length - info.start);
  }
  return repaired;
}

/** Duration of an mp3 (walked frames) or of a 16-bit mono WAV. */
export function audioSeconds(
  bytes: Uint8Array,
  format: "mp3" | "wav",
  sampleRate = 24_000,
): number {
  if (format === "wav") {
    return Math.max(0, bytes.length - 44) / (sampleRate * 2);
  }
  return mp3Info(bytes)?.seconds ?? 0;
}

/**
 * Whether the speech is implausibly short for [chars] characters (French
 * is spoken at ~15 characters per second; under a third of that, the
 * audio is truncated): the app then shows the reply as text only.
 */
export function isSpeechTooShort(seconds: number, chars: number): boolean {
  return chars >= 20 && seconds < chars / 45;
}

/** Duration declared by the `mvhd` box of an MP4 / m4a file, or null
 * (never throws, whatever the bytes). */
export function m4aSeconds(bytes: Uint8Array): number | null {
  try {
    for (let i = 4; i + 4 <= bytes.length; i++) {
      if (
        bytes[i] !== 0x6d || bytes[i + 1] !== 0x76 || bytes[i + 2] !== 0x68 ||
        bytes[i + 3] !== 0x64
      ) continue; // "mvhd"
      const box = i + 4;
      const version = bytes[box];
      // version 0: timescale @12, duration @16 (4 bytes); version 1:
      // timescale @20, duration @24 (8 bytes).
      const end = box + (version === 1 ? 32 : 20);
      if (end > bytes.length) return null;
      const view = new DataView(bytes.buffer, bytes.byteOffset + box, end - box);
      const timescale = view.getUint32(version === 1 ? 20 : 12);
      const duration = version === 1 ? Number(view.getBigUint64(24)) : view.getUint32(16);
      return timescale > 0 && Number.isFinite(duration) ? duration / timescale : null;
    }
  } catch {
    // Malformed: fall back to the size bounds.
  }
  return null;
}

/** Highest bit rate expected from a voice recording (16 KB/s = 128 kbit/s,
 * four times the app's AAC 32 kbit/s): the size bounds the duration from
 * below. */
export const MAX_AUDIO_BYTES_PER_SECOND = 16_000;

/** Lowest bit rate accepted (1 KB/s = 8 kbit/s, a quarter of the app's):
 * the size bounds the duration from above. */
export const MIN_AUDIO_BYTES_PER_SECOND = 1_000;

/**
 * Server-measured duration of an uploaded recording, for the quotas and
 * the 60 s limit. The m4a header is trusted only within the bounds given by
 * the size (≥ 8 kbit/s and ≤ 128 kbit/s), and the upper bound is used when
 * there is no header: a forged header cannot shrink the count. The client's
 * own figure is never trusted; the STT provider's measure is added later.
 */
export function recordingSeconds(bytes: Uint8Array): number {
  const lower = bytes.length / MAX_AUDIO_BYTES_PER_SECOND;
  const upper = bytes.length / MIN_AUDIO_BYTES_PER_SECOND;
  const declared = m4aSeconds(bytes);
  return declared === null ? upper : Math.min(Math.max(declared, lower), upper);
}
