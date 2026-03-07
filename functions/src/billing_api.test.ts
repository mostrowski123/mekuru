import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import { afterEach, describe, it } from "node:test";

import type { NextFunction, Request, Response as ExpressResponse } from "express";

import { createBillingApp } from "./index";

type TestDependencies = Parameters<typeof createBillingApp>[0];

async function startTestServer(
  overrides: Partial<TestDependencies> = {},
): Promise<{
  baseUrl: string;
  calls: {
    expireStaleJobs: number;
    reserveOcrJob: number;
    verifyAppCheck: number;
  };
  close: () => Promise<void>;
}> {
  const calls = {
    expireStaleJobs: 0,
    reserveOcrJob: 0,
    verifyAppCheck: 0,
  };

  const app = createBillingApp({
    enableOcrJobApi: true,
    verifyAppCheck: (_req: Request, _res: ExpressResponse, next: NextFunction) => {
      calls.verifyAppCheck += 1;
      next();
    },
    authenticate: (req: Request, _res: ExpressResponse, next: NextFunction) => {
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

  it("does not require App Check for purchase verification", async () => {
    let verifyAppCheckCalls = 0;
    const server = await startTestServer({
      verifyAppCheck: (
        _req: Request,
        res: ExpressResponse,
        _next: NextFunction,
      ) => {
        verifyAppCheckCalls += 1;
        res.status(401).json({
          detail: {
            code: "app_check_invalid",
            message: "App Check should not run for purchase verification.",
          },
        });
      },
    });
    openServers.push(server.close);

    const response = await fetch(
      `${server.baseUrl}/billing/purchases/android/verify`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          productId: "pro_unlock_v1",
          purchaseToken: "purchase-token-123",
          packageName: "moe.matthew.mekuru",
        }),
      },
    );

    assert.equal(response.status, 200);
    assert.equal(verifyAppCheckCalls, 0);
  });

  it("requires App Check for OCR job requests when hosted OCR is enabled", async () => {
    const server = await startTestServer({
      verifyAppCheck: (
        _req: Request,
        res: ExpressResponse,
        _next: NextFunction,
      ) => {
        res.status(401).json({
          detail: {
            code: "app_check_invalid",
            message: "The Firebase App Check token is invalid.",
          },
        });
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

    assert.equal(response.status, 401);
  });

  it("skips App Check for disabled OCR job routes so they still return 410", async () => {
    let verifyAppCheckCalls = 0;
    const server = await startTestServer({
      enableOcrJobApi: false,
      verifyAppCheck: (
        _req: Request,
        res: ExpressResponse,
        _next: NextFunction,
      ) => {
        verifyAppCheckCalls += 1;
        res.status(401).json({
          detail: {
            code: "app_check_invalid",
            message: "App Check should not run while OCR jobs are disabled.",
          },
        });
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

    assert.equal(response.status, 410);
    assert.equal(verifyAppCheckCalls, 0);
    assert.deepEqual(await response.json(), {
      detail: {
        code: "ocr_job_api_disabled",
        message: "Hosted OCR jobs are currently disabled.",
      },
    });
  });

  it("rate limits repeated purchase verification attempts", async () => {
    const server = await startTestServer();
    openServers.push(server.close);

    let lastResponse: globalThis.Response | undefined;
    for (let index = 0; index < 13; index += 1) {
      lastResponse = await fetch(
        `${server.baseUrl}/billing/purchases/android/verify`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            productId: "pro_unlock_v1",
            purchaseToken: `purchase-token-${index}`,
            packageName: "moe.matthew.mekuru",
          }),
        },
      );
    }

    assert.ok(lastResponse);
    assert.equal(lastResponse.status, 429);
    assert.equal(lastResponse.headers.get("retry-after"), "60");
    assert.deepEqual(await lastResponse.json(), {
      detail: {
        code: "rate_limited",
        message:
          "Too many purchase verification attempts. Please wait a moment and try again.",
      },
    });
  });
});
