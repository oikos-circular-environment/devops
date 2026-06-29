import { check } from "k6";
import { Counter } from "k6/metrics";
import type { RefinedResponse, ResponseType } from "k6/http";

export const rateLimitedRequests = new Counter("rate_limited_requests");

export function checkOk(res: RefinedResponse<ResponseType>, name: string): boolean {
  if (res.status === 429) {
    rateLimitedRequests.add(1);
    return true;
  }
  return check(res, {
    [`${name}: status 200`]: (r) => r.status === 200,
  });
}

export function checkCreated(res: RefinedResponse<ResponseType>, name: string): boolean {
  return check(res, {
    [`${name}: status 201`]: (r) => r.status === 201,
  });
}

export function checkNoContent(res: RefinedResponse<ResponseType>, name: string): boolean {
  return check(res, {
    [`${name}: status 204`]: (r) => r.status === 204,
  });
}
