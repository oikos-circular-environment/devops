import { sleep } from "k6";
import http from "k6/http";
import { BASE_URL, makeOptions } from "./config/base-options.ts";
import { authHeaders, getToken } from "./helpers/auth.ts";
import { checkOk } from "./helpers/checks.ts";

declare const __ENV: Record<string, string>;

export const options = makeOptions([
  { duration: "2m", target: 10 },
  { duration: "2m", target: 10 },
  { duration: "3m", target: 50 },
  { duration: "4m", target: 50 },
  { duration: "2m", target: 0 },
]);

export function setup(): { token: string | null } {
  const email = __ENV.TEST_USER_EMAIL;
  const password = __ENV.TEST_USER_PASSWORD;
  if (!email || !password) return { token: null };
  return { token: getToken(BASE_URL, email, password) };
}

export default function ({ token }: { token: string | null }): void {
  const roll = Math.random();

  if (roll < 0.6) {
    publicBrowse();
  } else if (roll < 0.9) {
    if (token) authenticatedRead(token);
    else publicBrowse();
  } else {
    if (token) authenticatedWrite(token);
    else publicBrowse();
  }
}

function publicBrowse(): void {
  checkOk(
    http.get(`${BASE_URL}/v1/market?lat=-16.4757&lon=-54.6685&radius=5000&limit=10`),
    "market",
  );
  sleep(1);

  checkOk(
    http.get(`${BASE_URL}/v1/complaints/map?lat=-16.4757&lon=-54.6685&radius=5000`),
    "complaints-map",
  );
  sleep(1);

  checkOk(http.get(`${BASE_URL}/v1/waste-categories`), "waste-categories");
  sleep(1);
}

function authenticatedRead(token: string): void {
  const opts = authHeaders(token);

  checkOk(http.get(`${BASE_URL}/v1/complaints`, opts), "complaints-list");
  sleep(1);

  checkOk(http.get(`${BASE_URL}/health`), "health");
  sleep(1);
}

function authenticatedWrite(token: string): void {
  const opts = authHeaders(token);

  const list = http.get(`${BASE_URL}/v1/complaints`, opts);
  if (list.status !== 200) return;

  const data = list.json("data") as Array<{ id: string }> | null;
  if (data && data.length > 0) {
    checkOk(
      http.get(`${BASE_URL}/v1/complaints/${data[0].id}`, opts),
      "complaint-detail",
    );
  }
  sleep(2);
}
