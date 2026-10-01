/**
 * @jest-environment node
 */
/**
 * The API only ever sees this app.
 *
 * Every browser request reaches it through here, so unless the browser's address
 * is carried along, per-client rate limits collapse into one bucket for the
 * whole world — `5/minute` on login meant five logins a minute across all users,
 * and a person testing collected 429s somebody else had earned.
 */
import { CLIENT_IP_HEADER, clientIpHeaders, clientIpOf } from "../upstream";

const requestWith = (headers: Record<string, string>) =>
  new Request("https://app.test/api/auth/login", { headers });

it("takes the browser from the front of the forwarded chain", () => {
  // The platform appends its own hops, so later entries are proxies, not people.
  const request = requestWith({
    "x-forwarded-for": "203.0.113.9, 10.0.0.4, 10.0.0.5",
  });

  expect(clientIpOf(request)).toBe("203.0.113.9");
});

it("tolerates a chain written with spaces", () => {
  expect(clientIpOf(requestWith({ "x-forwarded-for": "  203.0.113.9 " }))).toBe(
    "203.0.113.9"
  );
});

it("falls back to x-real-ip", () => {
  expect(clientIpOf(requestWith({ "x-real-ip": "203.0.113.10" }))).toBe(
    "203.0.113.10"
  );
});

it("returns null when the address is unknowable", () => {
  // So the caller omits the header and the API keys on the connecting address,
  // rather than counting every unknown caller as one shared client.
  expect(clientIpOf(requestWith({}))).toBeNull();
});

it("builds the header the API reads", () => {
  expect(clientIpHeaders(requestWith({ "x-forwarded-for": "203.0.113.9" }))).toEqual({
    [CLIENT_IP_HEADER]: "203.0.113.9",
  });
});

it("builds no header at all when there is nothing to say", () => {
  expect(clientIpHeaders(requestWith({}))).toEqual({});
});
