import http from "k6/http";
import { check } from "k6";

export function registerUser(baseUrl: string, email: string, password: string): void {
  const res = http.post(
    `${baseUrl}/v1/users/register`,
    JSON.stringify({ email, password }),
    { headers: { "Content-Type": "application/json" } },
  );

  if (res.status !== 204 && res.status !== 409) {
    throw new Error(`Register failed (${res.status}): ${res.body}`);
  }
}

export function getToken(baseUrl: string, email: string, password: string): string {
  const res = http.post(
    `${baseUrl}/v1/auth/login`,
    JSON.stringify({ email, password }),
    { headers: { "Content-Type": "application/json" } },
  );

  check(res, { "login: status 200": (r) => r.status === 200 });

  if (res.status !== 200) {
    throw new Error(
      `Login falhou (${res.status}): verifique TEST_USER_EMAIL e TEST_USER_PASSWORD`,
    );
  }

  return res.json("token") as string;
}

export function authHeaders(token: string) {
  return {
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
  };
}
