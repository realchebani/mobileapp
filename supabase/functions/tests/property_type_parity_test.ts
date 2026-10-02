// EPIC-13 / EPIC-14: the app (PropertyTypeProfile) and the Edge Functions
// agree on which steps are voiced for which property type, which types the
// V4 audit serves, which V4b columns each type asks, and which types the
// estimate covers.
import { assertEquals } from "jsr:@std/assert@1";
import { isVoiceType, VOICE_TYPES } from "../_shared/agent/schema.ts";
import { codesOf, isAsked, stepSchema, voiceStepsFor } from "../_shared/agent/steps/index.ts";
import { ESTIMATED_TYPES } from "../estimate-property/subject.ts";

interface Row {
  voice_audit: boolean;
  voice_steps: string[];
  technical: string[];
  parking_features?: string[];
  neighbourhood?: boolean;
  estimate: boolean;
}

const fixture = JSON.parse(
  Deno.readTextFileSync(new URL("./fixtures/property_type_profiles.json", import.meta.url)),
) as Record<string, Row>;
const types = Object.keys(fixture).filter((key) => !key.startsWith("_"));

Deno.test("V4 audit types match the fixture", () => {
  assertEquals(
    [...VOICE_TYPES].sort(),
    types.filter((type) => fixture[type].voice_audit).sort(),
  );
  for (const type of types) assertEquals(isVoiceType(type), fixture[type].voice_audit, type);
  assertEquals(isVoiceType(null), true);
});

Deno.test("voiced steps match the fixture", () => {
  for (const type of types) assertEquals(voiceStepsFor(type), fixture[type].voice_steps, type);
  assertEquals(voiceStepsFor(null).length, 5);
});

Deno.test("V4b columns and choices match the fixture", () => {
  // Conditions met, to list the heat pump and pool columns too.
  const conditions = { heating_systems: ["pac"], outdoor_equipment: ["piscine"] };
  for (const type of types) {
    const values = { property_type: type, ...conditions };
    const asked = stepSchema("technical").fields.filter((f) => isAsked(f, values))
      .map((f) => f.column);
    assertEquals(asked.sort(), [...fixture[type].technical].sort(), type);
    const features = stepSchema("technical").fields.find((f) => f.column === "parking_features")!;
    if (fixture[type].parking_features) {
      assertEquals(Object.keys(codesOf(features, values)), fixture[type].parking_features, type);
    }
    const noise = stepSchema("lifestyle").fields.find((f) => f.column === "noise_level")!;
    if (fixture[type].voice_steps.includes("lifestyle")) {
      assertEquals(isAsked(noise, values), fixture[type].neighbourhood ?? true, type);
    }
  }
});

Deno.test("estimated types match the fixture", () => {
  assertEquals(
    [...ESTIMATED_TYPES].sort(),
    types.filter((type) => fixture[type].estimate).sort(),
  );
});
