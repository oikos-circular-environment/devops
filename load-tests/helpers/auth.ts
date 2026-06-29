import http from "k6/http";
import { check } from "k6";

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
