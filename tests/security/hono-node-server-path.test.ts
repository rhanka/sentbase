// Regression test for @hono/node-server path-handling advisories fixed by 2.1.6, notably
// GHSA-rmxm-3fg6-px4f (serveStatic decodes the path a second time, so middleware mounted on a static
// prefix can be skipped) and GHSA-frvp-7c67-39w9 (encoded backslash in serve-static).
// A guard protects /static/admin/*; no crafted path (backslash, encoded backslash, dot-dot, double
// encoding) may return the protected file. Requests use node:http with the raw path, because
// fetch/URL would normalize it client-side.
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { request } from "node:http";
import type { AddressInfo } from "node:net";
import { join } from "node:path";
import { serve, type ServerType } from "@hono/node-server";
import { serveStatic } from "@hono/node-server/serve-static";
import { Hono } from "hono";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

const SECRET = "admin-secret-body";
const PROXY_SECRET = "proxy-guarded-secret";
const ROOT = join("tmp", `test-static-${process.pid}`);
let server: ServerType;
let port: number;

function rawGet(path: string): Promise<{ status: number; body: string }> {
  return new Promise((resolve, reject) => {
    const req = request({ host: "127.0.0.1", port, path, method: "GET" }, (res) => {
      let body = "";
      res.setEncoding("utf8");
      res.on("data", (chunk) => (body += chunk));
      res.on("end", () => resolve({ status: res.statusCode ?? 0, body }));
    });
    req.on("error", reject);
    req.end();
  });
}

beforeAll(async () => {
  mkdirSync(join(ROOT, "admin"), { recursive: true });
  mkdirSync(join(ROOT, "public"), { recursive: true });
  writeFileSync(join(ROOT, "admin", "secret.txt"), SECRET);
  writeFileSync(join(ROOT, "public", "index.txt"), "public-body");
  // A file whose name is only reachable if serveStatic decodes the already-decoded path again.
  writeFileSync(join(ROOT, "public", "%41.txt"), "double-decoded-body");

  const app = new Hono();
  // GHSA-jpvv-r467-5p4w: the guard for /internal/* lives at a reverse proxy, not in the app. The proxy
  // forwards "/public/..\\internal/secret" because it does not start with "/internal/"; the app must not
  // treat the backslash as a separator and route it to /internal/secret.
  app.get("/internal/secret", (c) => c.text(PROXY_SECRET));
  app.use("/static/admin/*", async (c) => c.text("forbidden", 403));
  app.use(
    "/static/*",
    serveStatic({ root: ROOT, rewriteRequestPath: (p) => p.replace(/^\/static/, "") }),
  );
  await new Promise<void>((resolve) => {
    server = serve({ fetch: app.fetch, hostname: "127.0.0.1", port: 0 }, () => resolve());
  });
  port = (server.address() as AddressInfo).port;
});

afterAll(async () => {
  await new Promise<void>((resolve) => server.close(() => resolve()));
  rmSync(ROOT, { recursive: true, force: true });
});

describe("@hono/node-server serveStatic behind a path-based guard", () => {
  it("serves public files and guards the direct admin path", async () => {
    expect((await rawGet("/static/public/index.txt")).body).toBe("public-body");
    const res = await rawGet("/static/admin/secret.txt");
    expect(res.status).toBe(403);
    expect(res.body).not.toContain(SECRET);
  });

  it("installs a patched @hono/node-server (>= 2.1.6)", () => {
    const { version } = JSON.parse(
      readFileSync(join("node_modules", "@hono", "node-server", "package.json"), "utf8"),
    ) as { version: string };
    const [major = 0, minor = 0, patch = 0] = version.split(".").map((n) => Number.parseInt(n, 10));
    expect(major * 1_000_000 + minor * 1_000 + patch).toBeGreaterThanOrEqual(2_001_006);
  });

  it("does not decode the request path a second time (GHSA-rmxm-3fg6-px4f root cause)", async () => {
    // Hono decodes once while protecting "%25", so routing sees ".../%2541.txt". A second decode in
    // serveStatic would resolve ".../%41.txt" and serve the file literally named "%41.txt".
    const res = await rawGet("/static/public/%2541.txt");
    expect(res.body).not.toContain("double-decoded-body");
  });

  it.each([
    "/public/..\\internal/secret",
    "/public\\..\\internal/secret",
    "/public/..%5Cinternal/secret",
    "/public/%2e%2e%5Cinternal/secret",
    "\\internal/secret",
  ])("does not route a proxy-allowed path to the proxy-guarded route for %s (GHSA-jpvv-r467-5p4w)", async (path) => {
    const res = await rawGet(path);
    expect(res.body).not.toContain(PROXY_SECRET);
  });

  it.each([
    "/static/public/..\\admin/secret.txt",
    "/static/public/..%5Cadmin/secret.txt",
    "/static/public/..%5cadmin/secret.txt",
    "/static/public/%2e%2e%5Cadmin/secret.txt",
    "/static/public/%2E%2E%5cadmin/secret.txt",
    "/static/public/%252e%252e%255Cadmin/secret.txt",
    "/static/%2561dmin/secret.txt",
    "/static/%2561%2564min/secret.txt",
    "/static/admin%252fsecret.txt",
    "/static/%252561dmin/secret.txt",
    "/static\\admin\\secret.txt",
    "/static/admin%5Csecret.txt",
  ])("never serves the guarded file for %s", async (path) => {
    const res = await rawGet(path);
    expect(res.body).not.toContain(SECRET);
  });
});
