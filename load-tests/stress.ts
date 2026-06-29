import http from "k6/http";
import { sleep } from "k6";
import { makeOptions, BASE_URL } from "./config/base-options.ts";
import { checkOk } from "./helpers/checks.ts";

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

export default function (): void {
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
