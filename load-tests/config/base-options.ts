declare const __ENV: Record<string, string>;

export interface Stage {
  duration: string;
  target: number;
}

export interface Thresholds {
  [metric: string]: string[];
}

export function makeOptions(stages: Stage[], thresholds: Thresholds = {}) {
  return {
    stages,
    thresholds: {
      http_req_failed: ["rate<0.01"],
      http_req_duration: ["p(95)<2000"],
      ...thresholds,
    },
  };
}

export const BASE_URL: string = __ENV.BASE_URL || "http://localhost:3333";
