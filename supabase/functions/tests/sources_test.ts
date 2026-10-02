import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import {
  communesAround,
  communesWithin,
  departmentCommunes,
  departmentOf,
  downloadCommuneCsv,
  geoDvfUrl,
  hasDvfCoverage,
  monthlyStats,
  samplePoints,
} from "../_shared/dvf/sources.ts";

Deno.test("départements and coverage", () => {
  assertEquals(departmentOf("69043"), "69");
  assertEquals(departmentOf("97105"), "971");
  assertEquals(departmentOf("2A004"), "2A");
  assertEquals(hasDvfCoverage("69043"), true);
  assertEquals(hasDvfCoverage("67482"), false);
  assertEquals(hasDvfCoverage("97611"), false);
  assertEquals(
    geoDvfUrl("69043", 2025),
    "https://files.data.gouv.fr/geo-dvf/latest/csv/2025/communes/69/69043.csv",
  );
});

Deno.test("downloadCommuneCsv statuses", async () => {
  const seen: (HeadersInit | undefined)[] = [];
  const respond = (response: Response) => (_url: string, init?: RequestInit) => {
    seen.push(init?.headers);
    return Promise.resolve(response);
  };
  assertEquals(
    await downloadCommuneCsv(
      respond(
        new Response("a,b", {
          headers: { etag: '"e1"', "last-modified": "Mon, 18 May 2026 13:10:01 GMT" },
        }),
      ),
      "69043",
      2025,
      null,
    ),
    { status: "ok", text: "a,b", etag: '"e1"', lastModified: "Mon, 18 May 2026 13:10:01 GMT" },
  );
  assertEquals(
    await downloadCommuneCsv(respond(new Response(null, { status: 304 })), "69043", 2025, '"e1"'),
    { status: "not_modified" },
  );
  assertEquals(seen[1], { "If-None-Match": '"e1"' });
  assertEquals(
    await downloadCommuneCsv(respond(new Response("no", { status: 404 })), "69043", 2026, null),
    { status: "missing" },
  );
  await assertRejects(() =>
    downloadCommuneCsv(respond(new Response("x", { status: 500 })), "69043", 2025, null)
  );
});

Deno.test("samplePoints", () => {
  const points = samplePoints(45, 4, 1000, 4);
  assertEquals(points.length, 5);
  assertEquals(points[0], [45, 4]);
});

Deno.test("communesAround resolves Paris / Lyon / Marseille arrondissements", async () => {
  const urls: string[] = [];
  const codes = await communesAround(
    (url) => {
      urls.push(url);
      const body = url.includes("arrondissement")
        ? [{ code: "69381" }]
        : urls.length % 2 === 0
        ? [{ code: "69123" }]
        : [{ code: "69043" }];
      return Promise.resolve(new Response(JSON.stringify(body)));
    },
    45.7104,
    4.7469,
  );
  assertEquals(codes, ["69043", "69381"]);
  await assertRejects(() =>
    communesAround(() => Promise.resolve(new Response("x", { status: 503 })), 45, 4)
  );
});

Deno.test("monthlyStats reads the tabular API", async () => {
  const stats = await monthlyStats(
    (url) => {
      assertEquals(url.includes("code_geo__exact=69043"), true);
      return Promise.resolve(
        new Response(JSON.stringify({
          data: [
            {
              annee_mois: "2025-12",
              code_parent: "200046977",
              nb_ventes_maison: 3,
              med_prix_m2_maison: 4240,
            },
            {
              annee_mois: "2025-11",
              code_parent: "200046977",
              nb_ventes_maison: null,
              med_prix_m2_maison: null,
            },
          ],
        })),
      );
    },
    "69043",
    "maison",
  );
  assertEquals(stats, {
    parent: "200046977",
    stats: [
      { month: "2025-12", count: 3, medianM2: 4240 },
      { month: "2025-11", count: 0, medianM2: 0 },
    ],
  });
  assertEquals(
    (await monthlyStats(() => Promise.resolve(new Response("{}")), "x", "maison")).parent,
    null,
  );
  await assertRejects(() =>
    monthlyStats(() => Promise.resolve(new Response("x", { status: 500 })), "x", "maison")
  );
});

Deno.test("departmentCommunes adds the arrondissements of Paris / Lyon / Marseille", async () => {
  const urls: string[] = [];
  const communes = await departmentCommunes((url) => {
    urls.push(url);
    const body = url.includes("arrondissement")
      ? [{ code: "75115", centre: { coordinates: [2.29, 48.84] } }]
      : [{ code: "75056", centre: { coordinates: [2.34, 48.85] } }];
    return Promise.resolve(new Response(JSON.stringify(body)));
  }, "75");
  assertEquals(communes, [{ code: "75115", lat: 48.84, lng: 2.29 }]);
  assertEquals(urls.length, 2);
});

Deno.test("communesWithin: sampled points up to 2 km, département lists beyond", async () => {
  const fetcher = (url: string) => {
    const body = url.includes("codeDepartement=23")
      ? [
        { code: "23001", centre: { coordinates: [4.7469, 45.7104] } },
        { code: "23002", centre: { coordinates: [4.7469, 45.7104 + 7 / 111.32] } },
        { code: "23003", centre: { coordinates: [4.7469, 45.7104 + 30 / 111.32] } },
      ]
      : url.includes("fields=codeDepartement")
      ? [{ codeDepartement: "23" }]
      : [{ code: "23001" }];
    return Promise.resolve(new Response(JSON.stringify(body)));
  };
  const cache = new Map();
  assertEquals(await communesWithin(fetcher, 45.7104, 4.7469, 2000, cache), ["23001"]);
  assertEquals(await communesWithin(fetcher, 45.7104, 4.7469, 5000, cache), ["23001", "23002"]);
  assertEquals(cache.size, 1);
  await assertRejects(() =>
    communesWithin(
      () => Promise.resolve(new Response("x", { status: 500 })),
      45,
      4,
      5000,
      new Map(),
    )
  );
});
