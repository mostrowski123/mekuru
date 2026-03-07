import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import { afterEach, describe, it } from "node:test";

import type { NextFunction, Request, Response } from "express";

import { createBillingApp } from "./index";

type TestDependencies = Parameters<typeof createBillingApp>[0];

async function startTestServer(
  overrides: Partial<TestDependencies> = {},
): Promise<{
  baseUrl: string;
  calls: { expireStaleJobs: number; reserveOcrJob: number };
  close: () => Promise<void>;
}> {
  const calls = {
    expireStaleJobs: 0,
    reserveOcrJob: 0,
  };

  const app = createBillingApp({
    enableOcrJobApi: true,
    verifyAppCheck: (_req: Request, _res: Response, next: NextFunction) => {
      next();
    },
    authenticate: (req: Request, _res: Response, next: NextFunction) => {
      (req as Request & { user: { uid: string } }).user = { uid: "user-123" };
      next();
    },
    expireStaleJobs: async () => {
      calls.expireStaleJobs += 1;
    },
    readUserState: async () => ({
      ocrUnlocked: true,
      creditBalance: 150,
    }),
    applyPurchaseGrant: async () => ({
      ocrUnlocked: true,
      creditBalance: 150,
      grantedCredits: 50,
    }),
    reserveOcrJob: async (input) => {
      calls.reserveOcrJob += 1;
      return {
        jobId: "job-1",
        reservedPages: input.requestedPages,
        expiresAt: new Date("2026-01-01T00:00:00.000Z"),
        creditBalance: 99,
      };
    },
    finalizeOcrJob: async () => ({
      completedPages: 5,
      refundedPages: 0,
      creditBalance: 94,
    }),
    ...overrides,
  });

  const server = app.listen(0);
  await new Promise<void>((resolve) => {
    server.once("listening", () => resolve());
  });

  const address = server.address() as AddressInfo;
  const baseUrl = `http://127.0.0.1:${address.port}`;

  return {
    baseUrl,
    calls,
    close: async () => {
      await new Promise<void>((resolve, reject) => {
        server.close((error) => {
          if (error != null) {
            reject(error);
            return;
          }
          resolve();
        });
      });
    },
  };
}

const openServers: Array<() => Promise<void>> = [];

afterEach(async () => {
  while (openServers.length > 0) {
    const close = openServers.pop();
    if (close != null) {
      await close();
    }
  }
});

describe("createBillingApp", () => {
  it("returns structured validation errors for missing purchase fields", async () => {
    const server = await startTestServer();
    openServers.push(server.close);

    const response = await fetch(
      `${server.baseUrl}/billing/purchases/android/verify`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({}),
      },
    );

    assert.equal(response.status, 422);
    assert.ok(response.headers.get("x-request-id"));
    assert.deepEqual(await response.json(), {
      detail: {
        code: "invalid_request",
        message: "productId and purchaseToken are required.",
      },
    });
  });

  it("rejects invalid OCR job input before invoking the reservation handler", async () => {
    const server = await startTestServer();
    openServers.push(server.close);

    const response = await fetch(`${server.baseUrl}/ocr/jobs`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        requestedPages: 12,
        bookId: 0,
      }),
    });

    assert.equal(response.status, 422);
    assert.equal(server.calls.reserveOcrJob, 0);
    assert.deepEqual(await response.json(), {
      detail: {
        code: "invalid_book_id",
        message: "bookId must be a positive integer.",
      },
    });
  });

  it("wraps unexpected handler failures in the generic internal error envelope", async () => {
    const server = await startTestServer({
      reserveOcrJob: async () => {
        throw new Error("database connection lost");
      },
    });
    openServers.push(server.close);

    const response = await fetch(`${server.baseUrl}/ocr/jobs`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        requestedPages: 12,
        bookId: 42,
      }),
    });

    assert.equal(response.status, 500);
    assert.deepEqual(await response.json(), {
      detail: {
        code: "internal_error",
        message: "An unexpected server error occurred.",
      },
    });
  });

  it("returns billing status and expires stale jobs when the OCR job API is enabled", async () => {
    const server = await startTestServer({
      readUserState: async () => ({
        ocrUnlocked: false,
        creditBalance: 7,
      }),
    });
    openServers.push(server.close);

    const response = await fetch(`${server.baseUrl}/billing/status`);

    assert.equal(response.status, 200);
    assert.equal(server.calls.expireStaleJobs, 1);
    assert.deepEqual(await response.json(), {
      ocrUnlocked: false,
      creditBalance: 7,
    });
  });
});
