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
