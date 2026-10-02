// EPIC-13: the app (PropertyTypeProfile) and the Edge Functions agree on
// which property types the voice agent serves and the estimate covers.
import { assertEquals } from "jsr:@std/assert@1";
import { isVoiceType, VOICE_TYPES } from "../_shared/agent/schema.ts";
import { ESTIMATED_TYPES } from "../estimate-property/subject.ts";

const fixture = JSON.parse(
  Deno.readTextFileSync(new URL("./fixtures/property_type_profiles.json", import.meta.url)),
) as Record<string, { voice: boolean; estimate: boolean }>;
const types = Object.keys(fixture).filter((key) => !key.startsWith("_"));

Deno.test("voice types match the fixture", () => {
  assertEquals(
    [...VOICE_TYPES].sort(),
    types.filter((type) => fixture[type].voice).sort(),
  );
  for (const type of types) assertEquals(isVoiceType(type), fixture[type].voice, type);
  assertEquals(isVoiceType(null), true);
});

Deno.test("estimated types match the fixture", () => {
  assertEquals(
    [...ESTIMATED_TYPES].sort(),
    types.filter((type) => fixture[type].estimate).sort(),
  );
});
