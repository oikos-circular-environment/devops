import http from "k6/http";
import { sleep, check } from "k6";
import { makeOptions, BASE_URL } from "./config/base-options.ts";
import { checkOk } from "./helpers/checks.ts";

export const options = makeOptions(
  [{ duration: "1m", target: 2 }],
  {
    http_req_failed: ["rate<0.001"],
    http_req_duration: ["p(95)<1000"],
  },
);

export default function (): void {
  checkOk(http.get(`${BASE_URL}/health`), "health");
  sleep(0.3);

  const cats = http.get(`${BASE_URL}/v1/waste-categories`);
  check(cats, {
    "waste-categories: status 200": (r) => r.status === 200,
    "waste-categories: tem dados": (r) => (r.json("categories") as unknown[]).length > 0,
  });
  sleep(0.3);

  checkOk(
    http.get(`${BASE_URL}/v1/market?lat=-16.4757&lon=-54.6685&radius=5000`),
    "market",
  );
  sleep(0.3);

  checkOk(
    http.get(`${BASE_URL}/v1/complaints/map?lat=-16.4757&lon=-54.6685&radius=5000`),
    "complaints-map",
  );
  sleep(0.5);
}
