import http from "k6/http";
import { sleep } from "k6";
import { BASE_URL, testPassword, makeOptions } from "./config/base-options.ts";
import { authHeaders, getToken, registerUser } from "./helpers/auth.ts";
import { checkOk } from "./helpers/checks.ts";
import {
  fetchCategoryIds,
  makeComplaintBody,
  randomCategoryId,
} from "./helpers/complaint-data.ts";

declare const __VU: number;

const USER_POOL_SIZE = 20;

export const options = makeOptions(
  [
    { duration: "3m", target: 50 },
    { duration: "2m", target: 50 },
    { duration: "3m", target: 100 },
    { duration: "2m", target: 100 },
    { duration: "3m", target: 150 },
    { duration: "2m", target: 150 },
    { duration: "3m", target: 200 },
    { duration: "3m", target: 200 },
    { duration: "2m", target: 0 },
  ],
  {
    http_req_failed: ["rate<0.10"],
    http_req_duration: ["p(95)<5000"],
  },
);

export function setup(): { tokens: string[]; categoryIds: string[] } {
  const categoryIds = fetchCategoryIds();
  const runId = `${Date.now()}-${Math.floor(Math.random() * 9999)}`;
  const password = testPassword();
  const tokens: string[] = [];

  for (let i = 0; i < USER_POOL_SIZE; i++) {
    const email = `k6-stress-${runId}-${i}@load.test`;
    registerUser(BASE_URL, email, password);
    tokens.push(getToken(BASE_URL, email, password));
  }

  return { tokens, categoryIds };
}

export default function ({
  tokens,
  categoryIds,
}: {
  tokens: string[];
  categoryIds: string[];
}): void {
  const token = tokens[(__VU - 1) % tokens.length];
  const roll = Math.random();

  if (roll < 0.6) {
    publicBrowse();
  } else if (roll < 0.9) {
    authenticatedRead(token);
  } else {
    authenticatedWrite(token, categoryIds);
  }
}

function publicBrowse(): void {
  checkOk(
    http.get(`${BASE_URL}/v1/market?lat=-16.4757&lon=-54.6685&radius=5000`),
    "market",
  );
  sleep(0.5);

  checkOk(
    http.get(`${BASE_URL}/v1/complaints/map?lat=-16.4757&lon=-54.6685&radius=5000`),
    "complaints-map",
  );
  sleep(0.5);

  checkOk(http.get(`${BASE_URL}/v1/waste-categories`), "waste-categories");
  sleep(0.3);

  checkOk(http.get(`${BASE_URL}/health`), "health");
  sleep(0.2);
}

function authenticatedRead(token: string): void {
  const opts = authHeaders(token);

  checkOk(http.get(`${BASE_URL}/v1/complaints`, opts), "complaints-list");
  sleep(0.5);

  checkOk(http.get(`${BASE_URL}/health`), "health");
  sleep(0.3);
}

function authenticatedWrite(token: string, categoryIds: string[]): void {
  const id = randomCategoryId(categoryIds);
  if (!id) return;

  checkOk(
    http.post(
      `${BASE_URL}/v1/complaints`,
      makeComplaintBody(id),
      authHeaders(token),
    ),
    "complaint-create",
  );
  sleep(1);
}
