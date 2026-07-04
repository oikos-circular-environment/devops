import http from "k6/http";
import { check, sleep } from "k6";
import type { Options } from "k6/options";
import { BASE_URL } from "./config/base-options.ts";
import { authHeaders, getToken, registerUser } from "./helpers/auth.ts";
import { checkOk } from "./helpers/checks.ts";
import {
  fetchCategoryIds,
  makeComplaintBody,
  randomCategoryId,
} from "./helpers/complaint-data.ts";

declare const __VU: number;

const STRESS_POOL = 20;
const SOAK_POOL = 10;
const TEST_PASSWORD = "K6Test@123";

interface SetupData {
  stressTokens: string[];
  soakTokens: string[];
  categoryIds: string[];
}

// Timeline: ver load-tests/README.md
export const options: Options = {
  scenarios: {
    smoke: {
      executor: "ramping-vus",
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
      executor: "ramping-vus",
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
    stress: {
      executor: "ramping-vus",
      stages: [
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
      startTime: "16m30s",
      exec: "stressScenario",
      gracefulRampDown: "30s",
    },
    spike: {
      executor: "ramping-vus",
      stages: [
        { duration: "1m", target: 5 },
        { duration: "30s", target: 200 },
        { duration: "2m", target: 200 },
        { duration: "30s", target: 5 },
        { duration: "1m", target: 5 },
        { duration: "30s", target: 0 },
      ],
      startTime: "40m30s",
      exec: "spikeScenario",
      gracefulRampDown: "30s",
    },
    soak: {
      executor: "ramping-vus",
      stages: [
        { duration: "5m", target: 20 },
        { duration: "30m", target: 20 },
        { duration: "5m", target: 0 },
      ],
      startTime: "47m",
      exec: "soakScenario",
      gracefulRampDown: "2m",
    },
  },
  thresholds: {
    "http_req_failed{scenario:smoke}": ["rate<0.001"],
    "http_req_duration{scenario:smoke}": ["p(95)<1000"],
    "http_req_failed{scenario:load}": ["rate<0.01"],
    "http_req_duration{scenario:load}": ["p(95)<2000"],
    "http_req_failed{scenario:stress}": ["rate<0.10"],
    "http_req_duration{scenario:stress}": ["p(95)<5000"],
    "http_req_failed{scenario:spike}": ["rate<0.05"],
    "http_req_duration{scenario:spike}": ["p(95)<5000"],
    "http_req_failed{scenario:soak}": ["rate<0.005"],
    "http_req_duration{scenario:soak}": ["p(95)<1000"],
  },
};

export function setup(): SetupData {
  const categoryIds = fetchCategoryIds();
  if (categoryIds.length === 0) {
    throw new Error("fetchCategoryIds retornou vazio — execute o seed de waste_categories no banco antes de rodar o teste");
  }
  const runId = `${Date.now()}-${Math.floor(Math.random() * 9999)}`;

  const stressTokens: string[] = [];
  for (let i = 0; i < STRESS_POOL; i++) {
    const email = `k6-suite-stress-${runId}-${i}@load.test`;
    registerUser(BASE_URL, email, TEST_PASSWORD);
    stressTokens.push(getToken(BASE_URL, email, TEST_PASSWORD));
  }

  const soakTokens: string[] = [];
  for (let i = 0; i < SOAK_POOL; i++) {
    const email = `k6-suite-soak-${runId}-${i}@load.test`;
    registerUser(BASE_URL, email, TEST_PASSWORD);
    soakTokens.push(getToken(BASE_URL, email, TEST_PASSWORD));
  }

  return { stressTokens, soakTokens, categoryIds };
}

export function smokeScenario(_data: SetupData): void {
  checkOk(http.get(`${BASE_URL}/health`), "health");
  sleep(0.3);

  const cats = http.get(`${BASE_URL}/v1/waste-categories`);
  check(cats, {
    "waste-categories: status 200": (r) => r.status === 200,
    "waste-categories: tem dados": (r) => (r.json() as unknown[]).length > 0,
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

export function loadScenario(_data: SetupData): void {
  if (Math.random() < 0.6) {
    checkOk(
      http.get(`${BASE_URL}/v1/market?lat=-16.4757&lon=-54.6685&radius=10000&limit=20`),
      "market",
    );
    sleep(1);
    checkOk(
      http.get(`${BASE_URL}/v1/complaints/map?lat=-16.4757&lon=-54.6685&radius=10000`),
      "complaints-map",
    );
    sleep(1);
  } else {
    checkOk(http.get(`${BASE_URL}/v1/waste-categories`), "waste-categories");
    sleep(1);
    checkOk(http.get(`${BASE_URL}/health`), "health");
    sleep(1);
  }
}

export function stressScenario({ stressTokens, categoryIds }: SetupData): void {
  const token = stressTokens[(__VU - 1) % stressTokens.length];
  const roll = Math.random();

  if (roll < 0.6) {
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
  } else if (roll < 0.9) {
    checkOk(
      http.get(`${BASE_URL}/v1/complaints`, authHeaders(token)),
      "complaints-list",
    );
    sleep(0.5);
    checkOk(http.get(`${BASE_URL}/health`), "health");
    sleep(0.3);
  } else {
    const id = randomCategoryId(categoryIds);
    if (id) {
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
  }
}

export function spikeScenario(_data: SetupData): void {
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

export function soakScenario({ soakTokens, categoryIds }: SetupData): void {
  const token = soakTokens[(__VU - 1) % soakTokens.length];
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
      http.post(`${BASE_URL}/v1/complaints`, makeComplaintBody(id), opts),
      "complaint-create",
    );
    sleep(2);
  }

  checkOk(http.get(`${BASE_URL}/v1/waste-categories`), "waste-categories");
  sleep(1);
  checkOk(http.get(`${BASE_URL}/health`), "health");
  sleep(1);
}

export default function (): void {}
