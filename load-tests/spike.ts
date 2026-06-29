import { sleep } from "k6";
import http from "k6/http";
import { BASE_URL, makeOptions } from "./config/base-options.ts";
import { checkOk } from "./helpers/checks.ts";

export const options = makeOptions(
  [
    { duration: "1m", target: 5 },
    { duration: "30s", target: 200 },
    { duration: "2m", target: 200 },
    { duration: "30s", target: 5 },
    { duration: "1m", target: 5 },
    { duration: "30s", target: 0 },
  ],
  {
    http_req_failed: ["rate<0.05"],
    http_req_duration: ["p(95)<5000"],
  },
);

export default function (): void {
  checkOk(
    http.get(`${BASE_URL}/v1/market?lat=-16.4757&lon=-54.6685&radius=5000&limit=5`),
    "market",
  );
  sleep(0.2);

  checkOk(http.get(`${BASE_URL}/v1/waste-categories`), "waste-categories");
  sleep(0.2);

  checkOk(http.get(`${BASE_URL}/health`), "health");
  sleep(0.1);
}
