// Builders of model answers for the voice agent tests.
import type { ModelAnswer, ModelEntityOp, ModelOutput } from "../_shared/agent/validate.ts";

export function output(partial: Partial<ModelOutput>): ModelOutput {
  return {
    reply_fr: "Merci.",
    answers: [],
    lifestyle_items: [],
    next_field: "none",
    done: false,
    ...partial,
  };
}

export function answer(field: string, value: string, quote: string, confidence = 0.9): ModelAnswer {
  return { field, value, quote, confidence };
}

export function op(partial: Partial<ModelEntityOp>): ModelEntityOp {
  return { entity: "room", op: "create", target: "new", target_quote: "", fields: [], ...partial };
}

export function f(field: string, value: string, quote: string, confidence = 0.9) {
  return { field, value, quote, confidence };
}
