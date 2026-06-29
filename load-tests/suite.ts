import http from "k6/http";
import { check, sleep } from "k6";

declare const __ENV: Record<string, string>;

const BASE_URL: string = __ENV.BASE_URL || "http://localhost:3333";

export const options = {
  scenarios: {
    smoke: {
      executor: "ramping-vus" as const,
      stages: [
        { duration: "30s", target: 2 },
        { duration: "1m", target: 2 },
        { duration: "30s", target: 0 },
      ],
      startTime: "0s",
      exec: "smokeScenario",
      gracefulRampDown: "10s",
    },
    load: {
      executor: "ramping-vus" as const,
      stages: [
        { duration: "2m", target: 10 },
        { duration: "2m", target: 10 },
        { duration: "3m", target: 50 },
        { duration: "4m", target: 50 },
        { duration: "2m", target: 0 },
      ],
      startTime: "2m30s",
      exec: "loadScenario",
      gracefulRampDown: "30s",
    },
  },
  thresholds: {
    "http_req_failed{scenario:smoke}": ["rate<0.001"],
    "http_req_duration{scenario:smoke}": ["p(95)<1000"],
    "http_req_failed{scenario:load}": ["rate<0.01"],
    "http_req_duration{scenario:load}": ["p(95)<2000"],
  },
};

export function smokeScenario(): void {
  check(http.get(`${BASE_URL}/health`), {
    "health: 200": (r) => r.status === 200,
  });
  sleep(0.3);

  const cats = http.get(`${BASE_URL}/v1/waste-categories`);
  check(cats, {
    "waste-categories: 200": (r) => r.status === 200,
  });
  sleep(0.3);

  check(
    http.get(`${BASE_URL}/v1/market?lat=-16.4757&lon=-54.6685&radius=5000`),
    { "market: 200": (r) => r.status === 200 },
  );
  sleep(0.3);

  check(
    http.get(`${BASE_URL}/v1/complaints/map?lat=-16.4757&lon=-54.6685&radius=5000`),
    { "complaints-map: 200": (r) => r.status === 200 },
  );
  sleep(0.5);
}

export function loadScenario(): void {
  const roll = Math.random();

  if (roll < 0.6) {
    publicBrowse();
  } else {
    readCategories();
  }
}

function publicBrowse(): void {
  check(
    http.get(`${BASE_URL}/v1/market?lat=-16.4757&lon=-54.6685&radius=10000&limit=20`),
    { "market: 200": (r) => r.status === 200 },
  );
  sleep(1);

  check(
    http.get(`${BASE_URL}/v1/complaints/map?lat=-16.4757&lon=-54.6685&radius=10000`),
    { "complaints-map: 200": (r) => r.status === 200 },
  );
  sleep(1);
}

function readCategories(): void {
  check(http.get(`${BASE_URL}/v1/waste-categories`), {
    "waste-categories: 200": (r) => r.status === 200,
  });
  sleep(1);

  check(http.get(`${BASE_URL}/health`), {
    "health: 200": (r) => r.status === 200,
  });
  sleep(1);
}

export default function (): void {}
