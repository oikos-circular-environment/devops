import { sleep } from "k6";
import http from "k6/http";
import { BASE_URL, makeOptions } from "./config/base-options.ts";
import { authHeaders, getToken } from "./helpers/auth.ts";
import { checkOk } from "./helpers/checks.ts";

declare const __ENV: Record<string, string>;

export const options = makeOptions(
  [
    { duration: "5m", target: 20 },
    { duration: "60m", target: 20 },
    { duration: "5m", target: 0 },
  ],
  {
    http_req_failed: ["rate<0.005"],
    http_req_duration: ["p(95)<1000"],
  },
);

export function setup(): { token: string | null } {
  const email = __ENV.TEST_USER_EMAIL;
  const password = __ENV.TEST_USER_PASSWORD;
  if (!email || !password) return { token: null };
  return { token: getToken(BASE_URL, email, password) };
}

export default function ({ token }: { token: string | null }): void {
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

  if (token) {
    const opts = authHeaders(token);
    checkOk(http.get(`${BASE_URL}/v1/complaints`, opts), "complaints-list");
    sleep(1);
  }

  checkOk(http.get(`${BASE_URL}/v1/waste-categories`), "waste-categories");
  sleep(1);

  checkOk(http.get(`${BASE_URL}/health`), "health");
  sleep(1);
}
