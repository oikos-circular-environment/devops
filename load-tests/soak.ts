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

export const options = makeOptions(
  [
    { duration: "5m", target: 20 },
    { duration: "30m", target: 20 },
    { duration: "5m", target: 0 },
  ],
  {
    http_req_failed: ["rate<0.005"],
    http_req_duration: ["p(95)<1000"],
  },
);

export function setup(): { tokens: string[]; categoryIds: string[] } {
  const categoryIds = fetchCategoryIds();
  if (categoryIds.length === 0) {
    throw new Error("fetchCategoryIds retornou vazio — execute o seed de waste_categories no banco antes de rodar o teste");
  }
  const runId = `${Date.now()}-${Math.floor(Math.random() * 9999)}`;
  const tokens: string[] = [];

  for (let i = 0; i < USER_POOL_SIZE; i++) {
    const email = `k6-soak-${runId}-${i}@load.test`;
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
  const opts = authHeaders(token);

  checkOk(
    http.get(`${BASE_URL}/v1/market?lat=-16.4757&lon=-54.6685&radius=5000`),
    "market",
  );
  sleep(1);

  checkOk(
    http.get(`${BASE_URL}/v1/complaints/map?lat=-16.4757&lon=-54.6685&radius=5000`),
    "complaints-map",
  );
  sleep(1);

  checkOk(http.get(`${BASE_URL}/v1/complaints`, opts), "complaints-list");
  sleep(1);

  const id = randomCategoryId(categoryIds);
  if (id) {
    checkOk(
      http.post(
        `${BASE_URL}/v1/complaints`,
        makeComplaintBody(id),
        opts,
      ),
      "complaint-create",
    );
    sleep(2);
  }

  checkOk(http.get(`${BASE_URL}/v1/waste-categories`), "waste-categories");
  sleep(1);

  checkOk(http.get(`${BASE_URL}/health`), "health");
  sleep(1);
}
