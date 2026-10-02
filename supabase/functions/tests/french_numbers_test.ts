import { assert, assertEquals } from "jsr:@std/assert@1";
import { numberInQuote, numbersIn } from "../_shared/agent/french_numbers.ts";

function has(text: string, value: number) {
  assert(numberInQuote(value, text), `${value} in « ${text} » (${numbersIn(text)})`);
}

function hasNot(text: string, value: number) {
  assert(!numberInQuote(value, text), `${value} not in « ${text} » (${numbersIn(text)})`);
}

Deno.test("digits, decimals and thousands groups", () => {
  has("fait 38 m²", 38);
  has("38,5 mètres carrés", 38.5);
  has("38.5", 38.5);
  has("acheté 320 000 €", 320000);
  has("acheté 320 000 euros", 320000);
  has("1 250 000", 1250000);
  has("320 k€", 320000);
  has("320k", 320000);
  has("en 2012", 2012);
  has("38m²", 38);
  hasNot("fait 38 m²", 83);
});

Deno.test("numbers in words", () => {
  has("trente-huit mètres carrés", 38);
  has("deux mille douze", 2012);
  has("en mille neuf cent quatre-vingt-dix-huit", 1998);
  has("dix-neuf cent quatre-vingt-dix-huit", 1998);
  has("trois cent vingt mille euros", 320000);
  has("quatre-vingts", 80);
  has("soixante et onze", 71);
  has("soixante-dix-sept", 77);
  has("cent douze", 112);
  has("deux cents", 200);
  has("un million deux cent mille", 1200000);
  has("1,2 million", 1200000);
  has("320 mille", 320000);
  has("douze", 12);
  hasNot("quatre-vingts", 4);
});

Deno.test("separate numbers stay separate", () => {
  const text = "trois chambres de 12, 11 et 10 m²";
  for (const n of [3, 12, 11, 10]) has(text, n);
  hasNot(text, 33);
  for (const n of [12, 11, 10]) has("douze onze et dix", n);
  hasNot("douze onze et dix", 33);
});

Deno.test("halves, decimal commas and heights", () => {
  has("douze et demi", 12.5);
  has("12 et demi", 12.5);
  has("trente-huit virgule cinq", 38.5);
  has("2 m 50 sous plafond", 2.5);
  has("deux mètres cinquante", 2.5);
  has("2,50 m", 2.5);
});

Deno.test("text without numbers", () => {
  assertEquals(numbersIn("le séjour au rez-de-chaussée"), [1, 1].slice(0, 0));
  assertEquals(numbersIn(""), []);
  hasNot("mille", 2);
  has("mille", 1000);
});
