// EPIC-15: handlers of vision-room and plan-reader, with an in-memory
// VisionDb and a fake OpenRouter.
import { assert, assertEquals } from "jsr:@std/assert@1";
import { OpenRouterClient } from "../_shared/openrouter/client.ts";
import type {
  DocumentRow,
  Download,
  PhotoRow,
  RequestUpdate,
  VisionDb,
  VisionKind,
} from "../_shared/vision/db.ts";
import { VISION_LIMITS } from "../_shared/vision/db.ts";
import {
  CONSENT_VERSION,
  handlePlanReader,
  handleVisionRoom,
  imageType,
  type VisionDeps,
} from "../_shared/vision/handlers.ts";
import type { PlanReading, RoomPhotoAnalysis } from "../_shared/vision/validate.ts";

const PHOTO = "11111111-1111-4111-8111-111111111111";
const PLAN = "22222222-2222-4222-8222-222222222222";
const PROPERTY = "33333333-3333-4333-8333-333333333333";
const JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0]);

class FakeVisionDb implements VisionDb {
  photos = new Map<string, PhotoRow>([[PHOTO, {
    id: PHOTO,
    property_id: PROPERTY,
    storage_path: "u/p/photos/r/1.jpg",
    analysis: null,
    property_status: "draft",
  }]]);
  documents = new Map<string, DocumentRow>([[PLAN, {
    id: PLAN,
    property_id: PROPERTY,
    kind: "plan",
    mime_type: "image/jpeg",
    storage_path: "u/p/plan.jpg",
    extracted: { other: 1 },
    property_status: "draft",
  }]]);
  files = new Map<string, Download>([
    ["u/p/photos/r/1.jpg", JPEG],
    ["u/p/plan.jpg", PNG],
  ]);
  requests: ({ kind: VisionKind; target: string } & RequestUpdate)[] = [];
  quotaLeft = 10;
  analyses: RoomPhotoAnalysis[] = [];
  readings: PlanReading[] = [];
  failSave = false;
  /** The dossier was sent while the model was answering. */
  lockedAtWrite = false;
  /** Another request is analysing the same target. */
  busy = false;
  /** Runs once the request is reserved (another request finishing). */
  onReserve?: () => void;
  /** The journal cannot be completed. */
  failFinish = false;

  photo(id: string) {
    return Promise.resolve(this.photos.get(id) ?? null);
  }
  document(id: string) {
    return Promise.resolve(this.documents.get(id) ?? null);
  }
  download(path: string, maxBytes: number) {
    assertEquals(maxBytes, VISION_LIMITS.imageBytes);
    return Promise.resolve(this.files.get(path) ?? "missing");
  }
  reserve(kind: VisionKind, propertyId: string, targetId: string, since: Date) {
    assertEquals(propertyId, PROPERTY);
    assertEquals(since.toISOString(), "2026-10-02T00:00:00.000Z");
    if (this.busy) return Promise.resolve("busy" as const);
    if (this.quotaLeft === 0) return Promise.resolve("quota" as const);
    this.quotaLeft--;
    this.requests.push({ kind, target: targetId, error: "in_progress" });
    this.onReserve?.();
    return Promise.resolve({ id: `r${this.requests.length}` });
  }
  finish(requestId: string, update: RequestUpdate) {
    if (this.failFinish) return Promise.reject(new Error("db: down"));
    Object.assign(this.requests[Number(requestId.slice(1)) - 1], update);
    return Promise.resolve();
  }
  saveAnalysis(_photo: PhotoRow, analysis: RoomPhotoAnalysis) {
    if (this.failSave) return Promise.reject(new Error("db: denied"));
    if (this.lockedAtWrite) return Promise.resolve(false);
    this.analyses.push(analysis);
    return Promise.resolve(true);
  }
  saveReading(_document: DocumentRow, reading: PlanReading) {
    if (this.lockedAtWrite) return Promise.resolve(false);
    this.readings.push(reading);
    return Promise.resolve(true);
  }
}

const ROOM_ANSWER = {
  room_kind: "livingRoom",
  floor_covering: "parquet",
  glazing: "double",
  condition_notes: ["Fissure au plafond"],
  personal_items: ["Photos de famille"],
  people_visible: false,
  quality_issues: [],
};

const PLAN_ANSWER = {
  is_floor_plan: true,
  rooms: [{ name: "Séjour", area_m2: 30, level: "rdc", kind: "livingRoom" }],
  printed_total_m2: 30,
};

function chat(content: unknown, cost = 0.0004) {
  return Response.json({
    choices: [{
      message: { content: typeof content === "string" ? content : JSON.stringify(content) },
    }],
    usage: { prompt_tokens: 1500, completion_tokens: 80, cost },
  });
}

// deno-lint-ignore no-explicit-any
type Body = any;

function deps(
  db: FakeVisionDb | null,
  answers: (Response | Error)[],
  bodies: Body[] = [],
  sleep?: (ms: number) => Promise<void>,
): VisionDeps {
  return {
    sleep,
    db,
    openrouter: new OpenRouterClient({
      apiKey: "k",
      fetch: (_url, init) => {
        bodies.push(JSON.parse(init!.body as string));
        const next = answers.shift();
        return next instanceof Error || !next ? Promise.reject(next) : Promise.resolve(next);
      },
    }),
    models: { room: "m/room", plan: "m/plan" },
    now: () => new Date("2026-10-02T10:00:00Z"),
  };
}

function post(body: unknown, method = "POST") {
  // The app sends the version of the consent the seller accepted.
  const payload = typeof body === "string"
    ? body
    : JSON.stringify({ consent: CONSENT_VERSION, ...(body as Record<string, unknown>) });
  return new Request("https://x/f", {
    method,
    body: method === "POST" ? payload : undefined,
  });
}

async function call(
  handler: typeof handleVisionRoom,
  request: Request,
  d: VisionDeps,
): Promise<[number, Body]> {
  const response = await handler(request, d);
  return [response.status, await response.json()];
}

Deno.test("imageType reads the magic bytes", () => {
  assertEquals(imageType(JPEG), "image/jpeg");
  assertEquals(imageType(PNG), "image/png");
  assertEquals(imageType(new Uint8Array([1, 2, 3, 4, 5])), null);
  assertEquals(imageType(new Uint8Array([0xff])), null);
});

Deno.test("vision-room analyses a photo and stores the result", async () => {
  const db = new FakeVisionDb();
  const bodies: Body[] = [];
  const [status, body] = await call(
    handleVisionRoom,
    post({ photo_id: PHOTO }),
    deps(db, [chat(ROOM_ANSWER)], bodies),
  );
  assertEquals(status, 200);
  assertEquals(body.cached, false);
  assertEquals(body.analysis.room_kind, "livingRoom");
  assertEquals(db.analyses.length, 1);
  assertEquals(db.requests[0], {
    kind: "room_photo",
    target: PHOTO,
    error: null,
    model: "m/room",
    tokens_in: 1500,
    tokens_out: 80,
    cost_usd: 0.0004,
    ms: db.requests[0].ms,
  });
  const sent = bodies[0];
  assertEquals(sent.model, "m/room");
  assertEquals(sent.provider, { data_collection: "deny" });
  assertEquals(sent.response_format.json_schema.name, "room_photo_analysis");
  assert(sent.messages[1].content[1].image_url.url.startsWith("data:image/jpeg;base64,"));
});

Deno.test("vision-room answers a stored analysis without calling the model", async () => {
  const db = new FakeVisionDb();
  db.photos.get(PHOTO)!.analysis = { version: 1, room_kind: "kitchen" };
  const [status, body] = await call(handleVisionRoom, post({ photo_id: PHOTO }), deps(db, []));
  assertEquals(status, 200);
  assertEquals(body, { analysis: { version: 1, room_kind: "kitchen" }, cached: true });
  assertEquals(db.requests.length, 0);
});

Deno.test("vision-room checks the request", async () => {
  const db = new FakeVisionDb();
  assertEquals((await call(handleVisionRoom, post({}, "GET"), deps(db, [])))[0], 405);
  assertEquals((await call(handleVisionRoom, post({ photo_id: PHOTO }), deps(null, [])))[0], 401);
  assertEquals((await call(handleVisionRoom, post({ photo_id: "x" }), deps(db, [])))[0], 400);
  assertEquals((await call(handleVisionRoom, post("{"), deps(db, [])))[0], 400);
  assertEquals(
    (await call(handleVisionRoom, post({ photo_id: "x".repeat(3000) }), deps(db, [])))[0],
    413,
  );
  assertEquals(
    (await call(handleVisionRoom, post({ photo_id: PLAN }), deps(db, [])))[0],
    404,
  );
  db.photos.get(PHOTO)!.property_status = "submitted";
  assertEquals(
    (await call(handleVisionRoom, post({ photo_id: PHOTO }), deps(db, [])))[1],
    { error: "locked" },
  );
});

Deno.test("the vision functions need the seller's consent", async () => {
  const db = new FakeVisionDb();
  for (const handler of [handleVisionRoom, handlePlanReader]) {
    for (
      const body of [
        JSON.stringify({ photo_id: PHOTO, document_id: PLAN }),
        JSON.stringify({ photo_id: PHOTO, document_id: PLAN, consent: "v0" }),
      ]
    ) {
      assertEquals(await call(handler, post(body), deps(db, [])), [403, {
        error: "consent_required",
      }]);
    }
  }
  assertEquals((await call(handleVisionRoom, post("[1]"), deps(db, [])))[0], 400);
  assertEquals(db.requests.length, 0);
});

Deno.test("vision-room enforces the daily quota", async () => {
  const db = new FakeVisionDb();
  db.quotaLeft = 0;
  const [status, body] = await call(handleVisionRoom, post({ photo_id: PHOTO }), deps(db, []));
  assertEquals([status, body], [429, { error: "quota" }]);
});

Deno.test("vision-room reports missing, large and unsupported files", async () => {
  for (
    const [file, status, error] of [
      ["missing", 404, "missing_file"],
      ["too_large", 413, "too_large"],
      [new Uint8Array([1, 2, 3, 4]), 415, "unsupported"],
    ] as const
  ) {
    const db = new FakeVisionDb();
    db.files.set("u/p/photos/r/1.jpg", file);
    const [code] = await call(handleVisionRoom, post({ photo_id: PHOTO }), deps(db, []));
    assertEquals(code, status);
    assertEquals(db.requests[0].error, error);
  }
});

Deno.test("vision-room retries once an unusable answer", async () => {
  const db = new FakeVisionDb();
  const [status] = await call(
    handleVisionRoom,
    post({ photo_id: PHOTO }),
    deps(db, [chat("oops", 0.0001), chat(ROOM_ANSWER)]),
  );
  assertEquals(status, 200);
  assertEquals(db.requests[0].tokens_in, 3000);
  assertEquals(db.requests[0].cost_usd, 0.0005);
});

Deno.test("vision-room gives up after two unusable answers", async () => {
  const db = new FakeVisionDb();
  const [status, body] = await call(
    handleVisionRoom,
    post({ photo_id: PHOTO }),
    deps(db, [chat("oops"), chat("{}")]),
  );
  assertEquals([status, body], [502, { error: "invalid_output" }]);
  assertEquals(db.requests[0].error, "invalid_output");
  assertEquals(db.analyses.length, 0);
});

Deno.test("vision-room reports upstream and storage failures", async () => {
  const db = new FakeVisionDb();
  const [status, body] = await call(
    handleVisionRoom,
    post({ photo_id: PHOTO }),
    deps(db, [new Response("bad", { status: 500 })]),
  );
  assertEquals([status, body], [502, { error: "upstream" }]);
  assertEquals(db.requests[0].error, "upstream");

  const failing = new FakeVisionDb();
  failing.failSave = true;
  const [code] = await call(
    handleVisionRoom,
    post({ photo_id: PHOTO }),
    deps(failing, [chat(ROOM_ANSWER)]),
  );
  assertEquals(code, 502);
  assertEquals(failing.requests[0].error, "failed");
});

Deno.test("vision-room answers 500 when the database fails", async () => {
  const db = new FakeVisionDb();
  db.photo = () => Promise.reject(new Error("db: down"));
  assertEquals((await call(handleVisionRoom, post({ photo_id: PHOTO }), deps(db, [])))[0], 500);
});

Deno.test("plan-reader reads a plan and keeps the other extracted keys", async () => {
  const db = new FakeVisionDb();
  const bodies: Body[] = [];
  const [status, body] = await call(
    handlePlanReader,
    post({ document_id: PLAN }),
    deps(db, [chat(PLAN_ANSWER)], bodies),
  );
  assertEquals(status, 200);
  assertEquals(body.cached, false);
  assertEquals(body.reading.rooms, PLAN_ANSWER.rooms);
  assertEquals(body.reading.total_matches, true);
  assertEquals(db.readings.length, 1);
  assertEquals(db.requests[0].kind, "plan");
  assertEquals(bodies[0].model, "m/plan");
  assert(bodies[0].messages[1].content[1].image_url.url.startsWith("data:image/png;base64,"));
});

Deno.test("plan-reader answers a stored reading", async () => {
  const db = new FakeVisionDb();
  db.documents.get(PLAN)!.extracted = { plan_reading: { version: 1, rooms: [] } };
  const [status, body] = await call(handlePlanReader, post({ document_id: PLAN }), deps(db, []));
  assertEquals([status, body.cached], [200, true]);
});

Deno.test("plan-reader checks the document", async () => {
  const db = new FakeVisionDb();
  assertEquals((await call(handlePlanReader, post({}, "GET"), deps(db, [])))[0], 405);
  assertEquals((await call(handlePlanReader, post({ document_id: PLAN }), deps(null, [])))[0], 401);
  assertEquals((await call(handlePlanReader, post({ photo_id: PLAN }), deps(db, [])))[0], 400);
  assertEquals((await call(handlePlanReader, post({ document_id: PHOTO }), deps(db, [])))[0], 404);
  const plan = db.documents.get(PLAN)!;
  plan.mime_type = "application/pdf";
  assertEquals((await call(handlePlanReader, post({ document_id: PLAN }), deps(db, [])))[0], 415);
  plan.kind = "titre_propriete";
  assertEquals((await call(handlePlanReader, post({ document_id: PLAN }), deps(db, [])))[0], 400);
  plan.property_status = "in_review";
  assertEquals((await call(handlePlanReader, post({ document_id: PLAN }), deps(db, [])))[0], 409);
  db.document = () => Promise.reject(new Error("db: down"));
  assertEquals((await call(handlePlanReader, post({ document_id: PLAN }), deps(db, [])))[0], 500);
});

Deno.test("plan-reader enforces the quota and reports failures", async () => {
  const db = new FakeVisionDb();
  db.quotaLeft = 0;
  assertEquals((await call(handlePlanReader, post({ document_id: PLAN }), deps(db, [])))[0], 429);
  const failing = new FakeVisionDb();
  assertEquals(
    (await call(
      handlePlanReader,
      post({ document_id: PLAN }),
      deps(failing, [chat("x"), chat("y")]),
    ))[0],
    502,
  );
});

Deno.test("vision-room does not store an analysis once the dossier is sent", async () => {
  const db = new FakeVisionDb();
  db.lockedAtWrite = true;
  const [status, body] = await call(
    handleVisionRoom,
    post({ photo_id: PHOTO }),
    deps(db, [chat(ROOM_ANSWER)]),
  );
  assertEquals([status, body], [409, { error: "locked" }]);
  assertEquals(db.analyses.length, 0);
  assertEquals(db.requests[0].error, "locked");
  assertEquals(db.requests[0].cost_usd, 0.0004);
});

Deno.test("plan-reader does not store a reading once the dossier is sent", async () => {
  const db = new FakeVisionDb();
  db.lockedAtWrite = true;
  const [status, body] = await call(
    handlePlanReader,
    post({ document_id: PLAN }),
    deps(db, [chat(PLAN_ANSWER)]),
  );
  assertEquals([status, body], [409, { error: "locked" }]);
  assertEquals(db.readings.length, 0);
  assertEquals(db.requests[0].error, "locked");
});

Deno.test("vision-room waits for the same analysis in progress", async () => {
  const db = new FakeVisionDb();
  db.busy = true;
  const waits: number[] = [];
  const sleep = (ms: number) => {
    waits.push(ms);
    // The other request stores its analysis during the third wait.
    if (waits.length === 3) db.photos.get(PHOTO)!.analysis = { version: 1, room_kind: "kitchen" };
    return Promise.resolve();
  };
  const [status, body] = await call(
    handleVisionRoom,
    post({ photo_id: PHOTO }),
    deps(db, [], [], sleep),
  );
  assertEquals([status, body], [200, {
    analysis: { version: 1, room_kind: "kitchen" },
    cached: true,
  }]);
  assertEquals(waits, [
    VISION_LIMITS.busyPollMs,
    VISION_LIMITS.busyPollMs,
    VISION_LIMITS.busyPollMs,
  ]);
  assertEquals(db.requests.length, 0);
});

Deno.test("the vision functions give up waiting for another analysis", async () => {
  for (
    const [handler, body] of [
      [handleVisionRoom, { photo_id: PHOTO }],
      [handlePlanReader, { document_id: PLAN }],
    ] as const
  ) {
    const db = new FakeVisionDb();
    db.busy = true;
    let waits = 0;
    const sleep = () => {
      waits++;
      return Promise.resolve();
    };
    assertEquals(await call(handler, post(body), deps(db, [], [], sleep)), [409, {
      error: "busy",
    }]);
    assertEquals(waits, VISION_LIMITS.busyWaitMs / VISION_LIMITS.busyPollMs);
  }
});

Deno.test("plan-reader waits for the same reading in progress", async () => {
  const db = new FakeVisionDb();
  db.busy = true;
  const sleep = () => {
    db.documents.get(PLAN)!.extracted = { other: 1, plan_reading: { version: 1, rooms: [] } };
    return Promise.resolve();
  };
  const [status, body] = await call(
    handlePlanReader,
    post({ document_id: PLAN }),
    deps(db, [], [], sleep),
  );
  assertEquals([status, body], [200, { reading: { version: 1, rooms: [] }, cached: true }]);
});

Deno.test("a vanished photo or plan is not awaited forever", async () => {
  const db = new FakeVisionDb();
  db.busy = true;
  const sleep = () => {
    db.photos.clear();
    db.documents.clear();
    return Promise.resolve();
  };
  assertEquals(
    (await call(handleVisionRoom, post({ photo_id: PHOTO }), deps(db, [], [], sleep)))[0],
    409,
  );
  const other = new FakeVisionDb();
  other.busy = true;
  const clear = () => {
    other.documents.clear();
    return Promise.resolve();
  };
  assertEquals(
    (await call(handlePlanReader, post({ document_id: PLAN }), deps(other, [], [], clear)))[0],
    409,
  );
});

Deno.test("an analysis stored just before the reservation is not redone", async () => {
  const db = new FakeVisionDb();
  db.onReserve = () => db.photos.get(PHOTO)!.analysis = { version: 1, room_kind: "bedroom" };
  const [status, body] = await call(handleVisionRoom, post({ photo_id: PHOTO }), deps(db, []));
  assertEquals([status, body], [200, {
    analysis: { version: 1, room_kind: "bedroom" },
    cached: true,
  }]);
  assertEquals(db.requests[0].error, "duplicate");
  const plans = new FakeVisionDb();
  plans.onReserve = () =>
    plans.documents.get(PLAN)!.extracted = { plan_reading: { version: 1, rooms: [] } };
  const [code, reading] = await call(
    handlePlanReader,
    post({ document_id: PLAN }),
    deps(plans, []),
  );
  assertEquals([code, reading.cached], [200, true]);
});

Deno.test("a stored analysis is returned even if the journal fails", async () => {
  const db = new FakeVisionDb();
  db.failFinish = true;
  const [status, body] = await call(
    handleVisionRoom,
    post({ photo_id: PHOTO }),
    deps(db, [chat(ROOM_ANSWER)]),
  );
  assertEquals([status, body.cached], [200, false]);
  assertEquals(db.analyses.length, 1);
});

Deno.test("a failed download closes the journal row", async () => {
  const db = new FakeVisionDb();
  db.download = () => Promise.reject(new Error("storage: down"));
  const [status] = await call(handleVisionRoom, post({ photo_id: PHOTO }), deps(db, []));
  assertEquals(status, 502);
  assertEquals(db.requests[0].error, "failed");
});
