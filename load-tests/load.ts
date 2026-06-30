import { sleep } from "k6";
import http from "k6/http";
import { BASE_URL, makeOptions } from "./config/base-options.ts";
import { authHeaders, getToken, registerUser } from "./helpers/auth.ts";
import { checkOk } from "./helpers/checks.ts";
import {
  fetchCategoryIds,
  makeComplaintBody,
  randomCategoryId,
} from "./helpers/complaint-data.ts";

declare const __VU: number;

const USER_POOL_SIZE = 10;
const TEST_PASSWORD = "K6Test@123";

export const options = makeOptions([
  { duration: "2m", target: 10 },
  { duration: "2m", target: 10 },
  { duration: "3m", target: 50 },
  { duration: "4m", target: 50 },
  { duration: "2m", target: 0 },
]);

export function setup(): { tokens: string[]; categoryIds: string[] } {
  const categoryIds = fetchCategoryIds();
  const runId = `${Date.now()}-${Math.floor(Math.random() * 9999)}`;
  const tokens: string[] = [];

  for (let i = 0; i < USER_POOL_SIZE; i++) {
    const email = `k6-load-${runId}-${i}@load.test`;
    registerUser(BASE_URL, email, TEST_PASSWORD);
    tokens.push(getToken(BASE_URL, email, TEST_PASSWORD));
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
  sleep(2);
}
