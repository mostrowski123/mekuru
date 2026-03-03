import { randomUUID } from "node:crypto";

import * as admin from "firebase-admin";
import express, { NextFunction, Request, Response } from "express";
import * as logger from "firebase-functions/logger";
import { onRequest } from "firebase-functions/v2/https";
import { onMessagePublished } from "firebase-functions/v2/pubsub";
import { GoogleAuth } from "google-auth-library";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const firebaseAuth = admin.auth();
const playAuth = new GoogleAuth({
  scopes: ["https://www.googleapis.com/auth/androidpublisher"],
});

const REGION = "us-central1";
const PROJECT_ID = process.env.GCLOUD_PROJECT ?? process.env.PROJECT_ID ?? "mekuru-12c8f";
const BILLING_SERVICE_ACCOUNT =
  process.env.BILLING_FUNCTIONS_SERVICE_ACCOUNT ?? `${PROJECT_ID}@appspot.gserviceaccount.com`;
const ANDROID_PACKAGE_NAME =
  process.env.ANDROID_PACKAGE_NAME ?? "moe.matthew.mekuru";
const OCR_JOB_TTL_HOURS = asInt(process.env.OCR_JOB_TTL_HOURS ?? "24");

const PRO_UNLOCK_PRODUCT_ID = "pro_unlock_v1";
const OCR_UNLOCK_STARTER_CREDITS = 150;
const OCR_CREDIT_PRODUCTS: Record<string, number> = {
  ocr_pages_500: 500,
  ocr_pages_1500: 1500,
  ocr_pages_4000: 4000,
};

type BillingErrorBody = {
  code: string;
  message: string;
  requiredCredits?: number;
  availableCredits?: number;
};

type BillingErrorDetail = string | BillingErrorBody;

type UserState = {
  ocrUnlocked: boolean;
  creditBalance: number;
};

type PurchaseGrant = {
  grantType: "unlock" | "credits";
  grantedCredits: number;
};

type PurchaseGrantResult = UserState & {
  grantedCredits: number;
};

type OcrJobReservation = {
  jobId: string;
  reservedPages: number;
  expiresAt: Date;
  creditBalance: number;
};

type OcrJobFinalization = {
  completedPages: number;
  refundedPages: number;
  creditBalance: number;
};

type GooglePlayProductPurchase = {
  orderId?: string;
  purchaseState?: unknown;
  acknowledgementState?: unknown;
  consumptionState?: unknown;
};

type AuthedRequest = Request & {
  requestId?: string;
  user: admin.auth.DecodedIdToken;
};

class BillingHttpError extends Error {
  readonly statusCode: number;
  readonly detail: BillingErrorDetail;

  constructor(statusCode: number, detail: BillingErrorDetail) {
    const message =
      typeof detail === "string" ? detail : detail.message ?? "Billing request failed.";
    super(message);
    this.statusCode = statusCode;
    this.detail = detail;
  }
}

function asInt(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value);
  }

  if (typeof value === "string" && value.trim().length > 0) {
    return Number.parseInt(value, 10);
  }

  return Number.NaN;
}

function now(): Date {
  return new Date();
}

function jobExpiry(at: Date): Date {
  return new Date(at.getTime() + OCR_JOB_TTL_HOURS * 60 * 60 * 1000);
}

function defaultUserDoc(at: Date) {
  return {
    ocrUnlocked: false,
    creditBalance: 0,
    createdAt: at,
    updatedAt: at,
  };
}

function userRef(uid: string) {
  return db.collection("users").doc(uid);
}

function purchaseLedgerRef(purchaseToken: string) {
  return db.collection("purchase_ledger").doc(`android_${purchaseToken}`);
}

function jobRef(jobId: string) {
  return db.collection("ocr_jobs").doc(jobId);
}

function requestIdOf(req?: Request): string | undefined {
  return (req as AuthedRequest | undefined)?.requestId;
}

function sendBillingError(req: Request | undefined, res: Response, error: unknown): void {
  const requestId = requestIdOf(req);

  if (error instanceof BillingHttpError) {
    logger.error("Billing request failed", {
      requestId,
      statusCode: error.statusCode,
      detail: error.detail,
    });
    res.status(error.statusCode).json({ detail: error.detail });
    return;
  }

  const detail: BillingErrorBody = {
    code: "internal_error",
    message:
      error instanceof Error && error.message
        ? error.message
        : "Billing request failed.",
  };
  logger.error("Billing request failed with unexpected error", {
    requestId,
    error,
  });
  res.status(500).json({ detail });
}

function asSingleString(value: unknown): string {
  if (Array.isArray(value)) {
    return typeof value[0] === "string" ? value[0] : "";
  }
  return typeof value === "string" ? value : "";
}

function parseBearerToken(req: Request): string {
  const authHeader = req.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    throw new BillingHttpError(401, {
      code: "auth_required",
      message: "A Firebase ID token is required.",
    });
  }

  return authHeader.slice("Bearer ".length).trim();
}

async function authenticate(
  req: Request,
  res: Response,
  next: NextFunction,
): Promise<void> {
  try {
    const token = parseBearerToken(req);
    (req as AuthedRequest).user = await firebaseAuth.verifyIdToken(token);
    logger.info("Billing request authenticated", {
      requestId: requestIdOf(req),
      uid: (req as AuthedRequest).user.uid,
      path: req.path,
    });
    next();
  } catch (error) {
    sendBillingError(req, res, error);
  }
}

function coerceDate(value: unknown): Date {
  if (
    typeof value === "object" &&
    value !== null &&
    "toDate" in value &&
    typeof (value as { toDate: () => Date }).toDate === "function"
  ) {
    return (value as { toDate: () => Date }).toDate();
  }

  if (value instanceof Date) {
    return value;
  }

  const parsed = new Date(String(value));
  if (!Number.isNaN(parsed.getTime())) {
    return parsed;
  }

  throw new BillingHttpError(500, {
    code: "billing_state_invalid",
    message: "Stored OCR billing data is invalid.",
  });
}

async function readUserState(uid: string): Promise<UserState> {
  const ref = userRef(uid);
  const snapshot = await ref.get();
  if (!snapshot.exists) {
    await ref.set(defaultUserDoc(now()));
    return {
      ocrUnlocked: false,
      creditBalance: 0,
    };
  }

  const data = snapshot.data() ?? {};
  return {
    ocrUnlocked: Boolean(data.ocrUnlocked),
    creditBalance: asInt(data.creditBalance ?? 0),
  };
}

async function applyLegacyUnlockTopUpIfNeeded(input: {
  uid: string;
  ledger: admin.firestore.DocumentReference;
  user: admin.firestore.DocumentReference;
}): Promise<PurchaseGrantResult | null> {
  const { uid, ledger, user } = input;

  return db.runTransaction<PurchaseGrantResult | null>(async (transaction) => {
    const [ledgerSnapshot, userSnapshot] = await Promise.all([
      transaction.get(ledger),
      transaction.get(user),
    ]);

    if (!ledgerSnapshot.exists) {
      return null;
    }

    const ledgerData = ledgerSnapshot.data() ?? {};
    const existingUid = typeof ledgerData.uid === "string" ? ledgerData.uid : uid;
    if (existingUid !== uid) {
      throw new BillingHttpError(409, {
        code: "purchase_uid_mismatch",
        message:
          "This purchase is already linked to a different account. Sign in with the original Google-linked account and restore purchases there.",
      });
    }

    const existingGrantedCredits = asInt(ledgerData.grantedCredits ?? 0);
    if (existingGrantedCredits >= OCR_UNLOCK_STARTER_CREDITS) {
      const userData = userSnapshot.exists
        ? userSnapshot.data() ?? {}
        : defaultUserDoc(now());
      return {
        ocrUnlocked: Boolean(userData.ocrUnlocked),
        creditBalance: asInt(userData.creditBalance ?? 0),
        grantedCredits: existingGrantedCredits,
      };
    }

    const current = now();
    const delta = OCR_UNLOCK_STARTER_CREDITS - existingGrantedCredits;
    const userData = userSnapshot.exists
      ? userSnapshot.data() ?? {}
      : defaultUserDoc(current);
    const creditBalance = asInt(userData.creditBalance ?? 0) + delta;

    if (!userSnapshot.exists) {
      transaction.set(user, defaultUserDoc(current));
    }

    transaction.set(
      user,
      {
        ocrUnlocked: true,
        creditBalance,
        updatedAt: current,
      },
      { merge: true },
    );
    transaction.set(
      ledger,
      {
        grantedCredits: OCR_UNLOCK_STARTER_CREDITS,
        updatedAt: current,
      },
      { merge: true },
    );

    logger.info("Applied legacy OCR unlock top-up", {
      uid,
      additionalCredits: delta,
      updatedGrantCredits: OCR_UNLOCK_STARTER_CREDITS,
      creditBalance,
    });

    return {
      ocrUnlocked: true,
      creditBalance,
      grantedCredits: OCR_UNLOCK_STARTER_CREDITS,
    };
  });
}

function grantForProduct(productId: string): PurchaseGrant {
  if (productId === PRO_UNLOCK_PRODUCT_ID) {
    return {
      grantType: "unlock",
      grantedCredits: OCR_UNLOCK_STARTER_CREDITS,
    };
  }

  const grantedCredits = OCR_CREDIT_PRODUCTS[productId];
  if (!grantedCredits) {
    throw new BillingHttpError(422, {
      code: "unsupported_product",
      message: `Unsupported product: ${productId}`,
    });
  }

  return {
    grantType: "credits",
    grantedCredits,
  };
}

async function googlePlayRequest(
  url: string,
  options: { method?: "GET" | "POST"; data?: unknown } = {},
): Promise<Record<string, unknown>> {
  let client;
  try {
    client = await playAuth.getClient();
  } catch (_) {
    throw new BillingHttpError(503, {
      code: "billing_unavailable",
      message: "Google Play billing credentials are not configured.",
    });
  }

  try {
    const response = await client.request<Record<string, unknown>>({
      url,
      ...options,
    });
    return response.data ?? {};
  } catch (error) {
    const errorData =
      typeof error === "object" &&
      error !== null &&
      "response" in error &&
      typeof (error as { response?: { data?: unknown } }).response?.data !== "undefined"
        ? (error as { response: { data?: unknown } }).response.data
        : undefined;
    const errorMessage =
      error instanceof Error
        ? error.message
        : typeof error === "object" &&
            error !== null &&
            "message" in error &&
            typeof (error as { message?: unknown }).message === "string"
          ? (error as { message: string }).message
          : undefined;

    const statusCode =
      typeof error === "object" &&
      error !== null &&
      "response" in error &&
      typeof (error as { response?: { status?: number } }).response?.status === "number"
        ? (error as { response: { status: number } }).response.status
        : undefined;

    if (statusCode === 404) {
      throw new BillingHttpError(422, {
        code: "purchase_not_found",
        message: "The Google Play purchase token was not found.",
      });
    }

    logger.error("Google Play API request failed", {
      url,
      statusCode,
      errorMessage,
      errorData,
      error,
    });

    if (statusCode === 401 || statusCode === 403) {
      throw new BillingHttpError(502, {
        code: "play_api_unauthorized",
        message:
          `Google Play purchase verification is not authorized. Grant ${BILLING_SERVICE_ACCOUNT} Android Publisher access in Play Console.`,
      });
    }

    throw new BillingHttpError(502, {
      code: "play_api_error",
      message: "Google Play purchase verification failed.",
    });
  }
}

async function verifyGooglePlayPurchase(input: {
  productId: string;
  purchaseToken: string;
  packageName: string;
}): Promise<GooglePlayProductPurchase> {
  const { productId, purchaseToken, packageName } = input;

  if (packageName !== ANDROID_PACKAGE_NAME) {
    throw new BillingHttpError(422, {
      code: "package_name_mismatch",
      message: "The purchase package name does not match this app.",
    });
  }

  const url =
    "https://androidpublisher.googleapis.com/androidpublisher/v3/" +
    `applications/${packageName}/purchases/products/${productId}/` +
    `tokens/${purchaseToken}`;
  const data = (await googlePlayRequest(url)) as GooglePlayProductPurchase;

  const purchaseState = asInt(data.purchaseState ?? -1);
  if (purchaseState === 0) {
    return data;
  }
  if (purchaseState === 2) {
    throw new BillingHttpError(409, {
      code: "purchase_pending",
      message: "The purchase is still pending in Google Play.",
    });
  }

  throw new BillingHttpError(422, {
    code: "purchase_not_completed",
    message: "The purchase is not in a completed state.",
  });
}

async function acknowledgeGooglePlayPurchase(input: {
  productId: string;
  purchaseToken: string;
  packageName: string;
}): Promise<void> {
  const { productId, purchaseToken, packageName } = input;
  const url =
    "https://androidpublisher.googleapis.com/androidpublisher/v3/" +
    `applications/${packageName}/purchases/products/${productId}/` +
    `tokens/${purchaseToken}:acknowledge`;
  await googlePlayRequest(url, {
    method: "POST",
    data: {},
  });
}

async function consumeGooglePlayPurchase(input: {
  productId: string;
  purchaseToken: string;
  packageName: string;
}): Promise<void> {
  const { productId, purchaseToken, packageName } = input;
  const url =
    "https://androidpublisher.googleapis.com/androidpublisher/v3/" +
    `applications/${packageName}/purchases/products/${productId}/` +
    `tokens/${purchaseToken}:consume`;
  await googlePlayRequest(url, {
    method: "POST",
    data: {},
  });
}

async function expireStaleJobs(uid: string): Promise<void> {
  const snapshot = await db.collection("ocr_jobs").where("uid", "==", uid).get();
  const current = now();

  for (const document of snapshot.docs) {
    const data = document.data() ?? {};
    if (data.status !== "active") {
      continue;
    }

    const expiresAt = coerceDate(data.expiresAt);
    if (expiresAt <= current) {
      await finalizeOcrJob({
        uid,
        jobId: document.id,
        status: "expired",
      });
    }
  }
}

async function applyPurchaseGrant(input: {
  uid: string;
  productId: string;
  purchaseToken: string;
  packageName: string;
  isRestore?: boolean;
}): Promise<PurchaseGrantResult> {
  const { uid, productId, purchaseToken, packageName, isRestore } = input;
  logger.info("Applying purchase grant", {
    uid,
    productId,
    packageName,
    isRestore: Boolean(isRestore),
    purchaseTokenSuffix:
      purchaseToken.length <= 8
        ? purchaseToken
        : purchaseToken.slice(purchaseToken.length - 8),
  });
  const grant = grantForProduct(productId);
  const ledger = purchaseLedgerRef(purchaseToken);
  const ref = userRef(uid);
  const current = now();

  const existingLedger = await ledger.get();
  if (existingLedger.exists) {
    const existing = existingLedger.data() ?? {};
    const existingUid = typeof existing.uid === "string" ? existing.uid : uid;
    const existingGrantedCredits = asInt(existing.grantedCredits ?? 0);

    if (existingUid !== uid) {
      if (!isRestore) {
        throw new BillingHttpError(409, {
          code: "purchase_uid_mismatch",
          message:
            "This purchase is already linked to a different account. Sign in with the original Google-linked account and restore purchases there.",
        });
      }

      // On restore, migrate the purchase to the current UID.  The purchase
      // token was already verified with Google Play during the original
      // purchase, and the restore flow only provides tokens owned by the
      // signed-in Google Play account, so this is safe.
      logger.info("Migrating purchase to new UID on restore", {
        previousUid: existingUid,
        newUid: uid,
        productId,
      });

      await db.runTransaction(async (transaction) => {
        const userSnapshot = await transaction.get(ref);
        const userData = userSnapshot.exists
          ? userSnapshot.data() ?? {}
          : defaultUserDoc(current);

        const creditBalance =
          asInt(userData.creditBalance ?? 0) +
          (existingGrantedCredits > 0 ? 0 : grant.grantedCredits);
        const ocrUnlocked =
          grant.grantType === "unlock" ? true : Boolean(userData.ocrUnlocked);

        if (!userSnapshot.exists) {
          transaction.set(ref, defaultUserDoc(current));
        }

        transaction.set(
          ref,
          { ocrUnlocked, creditBalance, updatedAt: current },
          { merge: true },
        );
        transaction.set(
          ledger,
          { uid, updatedAt: current },
          { merge: true },
        );
      });

      const status = await readUserState(uid);
      return {
        ocrUnlocked: status.ocrUnlocked,
        creditBalance: status.creditBalance,
        grantedCredits: existingGrantedCredits,
      };
    }

    if (
      productId === PRO_UNLOCK_PRODUCT_ID &&
      existingGrantedCredits < OCR_UNLOCK_STARTER_CREDITS
    ) {
      const toppedUp = await applyLegacyUnlockTopUpIfNeeded({
        uid,
        ledger,
        user: ref,
      });
      if (toppedUp != null) {
        return toppedUp;
      }
    }

    const status = await readUserState(uid);
    logger.info("Purchase already present in ledger", {
      uid,
      productId,
      grantedCredits: existingGrantedCredits,
      ocrUnlocked: status.ocrUnlocked,
      creditBalance: status.creditBalance,
    });
    return {
      ocrUnlocked: status.ocrUnlocked,
      creditBalance: status.creditBalance,
      grantedCredits: existingGrantedCredits,
    };
  }

  const verifiedPurchase = await verifyGooglePlayPurchase({
    productId,
    purchaseToken,
    packageName,
  });

  const result = await db.runTransaction<PurchaseGrantResult>(async (transaction) => {
    const [ledgerSnapshot, userSnapshot] = await Promise.all([
      transaction.get(ledger),
      transaction.get(ref),
    ]);

    if (ledgerSnapshot.exists) {
      const userData = userSnapshot.exists
        ? userSnapshot.data() ?? {}
        : defaultUserDoc(current);
      const existing = ledgerSnapshot.data() ?? {};
      return {
        ocrUnlocked: Boolean(userData.ocrUnlocked),
        creditBalance: asInt(userData.creditBalance ?? 0),
        grantedCredits: asInt(existing.grantedCredits ?? 0),
      };
    }

    const userData = userSnapshot.exists
      ? userSnapshot.data() ?? {}
      : defaultUserDoc(current);

    const creditBalance = asInt(userData.creditBalance ?? 0) + grant.grantedCredits;
    const ocrUnlocked =
      grant.grantType === "unlock" ? true : Boolean(userData.ocrUnlocked);

    if (!userSnapshot.exists) {
      transaction.set(ref, defaultUserDoc(current));
    }

    transaction.set(
      ref,
      {
        ocrUnlocked,
        creditBalance,
        updatedAt: current,
      },
      { merge: true },
    );
    transaction.set(ledger, {
      uid,
      productId,
      purchaseToken,
      orderId: verifiedPurchase.orderId ?? null,
      grantType: grant.grantType,
      grantedCredits: grant.grantedCredits,
      applied: true,
      revoked: false,
      createdAt: current,
      updatedAt: current,
    });

    return {
      ocrUnlocked,
      creditBalance,
      grantedCredits: grant.grantedCredits,
    };
  });

  try {
    const acknowledgementState = asInt(verifiedPurchase.acknowledgementState ?? 0);
    const consumptionState = asInt(verifiedPurchase.consumptionState ?? 0);

    if (grant.grantType === "unlock" && acknowledgementState !== 1) {
      await acknowledgeGooglePlayPurchase({
        productId,
        purchaseToken,
        packageName,
      });
    }

    if (grant.grantType === "credits" && consumptionState !== 1) {
      await consumeGooglePlayPurchase({
        productId,
        purchaseToken,
        packageName,
      });
    }
  } catch (error) {
    logger.error("Google Play post-grant action failed", {
      productId,
      purchaseToken,
      error,
    });
  }

  logger.info("Purchase grant applied", {
    uid,
    productId,
    grantType: grant.grantType,
    grantedCredits: result.grantedCredits,
    ocrUnlocked: result.ocrUnlocked,
    creditBalance: result.creditBalance,
  });
  return result;
}

async function reserveOcrJob(input: {
  uid: string;
  requestedPages: number;
  bookId: number;
}): Promise<OcrJobReservation> {
  const { uid, requestedPages, bookId } = input;
  await expireStaleJobs(uid);

  if (!Number.isInteger(requestedPages) || requestedPages <= 0) {
    throw new BillingHttpError(422, {
      code: "invalid_requested_pages",
      message: "requestedPages must be greater than zero.",
    });
  }

  const current = now();
  const expiresAt = jobExpiry(current);
  const id = randomUUID();
  const ref = userRef(uid);
  const targetJob = jobRef(id);

  return db.runTransaction<OcrJobReservation>(async (transaction) => {
    const userSnapshot = await transaction.get(ref);
    const userData = userSnapshot.exists
      ? userSnapshot.data() ?? {}
      : defaultUserDoc(current);

    if (!userSnapshot.exists) {
      transaction.set(ref, defaultUserDoc(current));
    }

    if (!Boolean(userData.ocrUnlocked)) {
      throw new BillingHttpError(402, {
        code: "unlock_required",
        message: "OCR unlock is required before creating OCR jobs.",
      });
    }

    const creditBalance = asInt(userData.creditBalance ?? 0);
    if (creditBalance < requestedPages) {
      throw new BillingHttpError(402, {
        code: "insufficient_credits",
        message: "Not enough OCR credits for this job.",
        requiredCredits: requestedPages,
        availableCredits: creditBalance,
      });
    }

    const nextBalance = creditBalance - requestedPages;
    transaction.set(
      ref,
      {
        creditBalance: nextBalance,
        updatedAt: current,
      },
      { merge: true },
    );
    transaction.set(targetJob, {
      uid,
      bookId,
      reservedPages: requestedPages,
      completedPages: 0,
      refundedPages: 0,
      status: "active",
      expiresAt,
      createdAt: current,
      updatedAt: current,
    });

    return {
      jobId: id,
      reservedPages: requestedPages,
      expiresAt,
      creditBalance: nextBalance,
    };
  });
}

async function finalizeOcrJob(input: {
  uid: string;
  jobId: string;
  status: string;
}): Promise<OcrJobFinalization> {
  const { uid, jobId, status } = input;

  if (!["completed", "cancelled", "failed", "expired"].includes(status)) {
    throw new BillingHttpError(422, {
      code: "invalid_final_status",
      message: `Unsupported OCR job status: ${status}`,
    });
  }

  const ref = userRef(uid);
  const targetJob = jobRef(jobId);
  const current = now();

  return db.runTransaction<OcrJobFinalization>(async (transaction) => {
    const [jobSnapshot, userSnapshot] = await Promise.all([
      transaction.get(targetJob),
      transaction.get(ref),
    ]);

    if (!jobSnapshot.exists) {
      throw new BillingHttpError(404, {
        code: "job_not_found",
        message: "The requested OCR job was not found.",
      });
    }

    const jobData = jobSnapshot.data() ?? {};
    if (jobData.uid !== uid) {
      throw new BillingHttpError(403, {
        code: "job_forbidden",
        message: "This OCR job belongs to a different user.",
      });
    }

    const userData = userSnapshot.exists
      ? userSnapshot.data() ?? {}
      : defaultUserDoc(current);
    if (!userSnapshot.exists) {
      transaction.set(ref, defaultUserDoc(current));
    }

    const currentBalance = asInt(userData.creditBalance ?? 0);
    const completedPages = asInt(jobData.completedPages ?? 0);

    if (jobData.status !== "active") {
      return {
        completedPages,
        refundedPages: asInt(jobData.refundedPages ?? 0),
        creditBalance: currentBalance,
      };
    }

    const reservedPages = asInt(jobData.reservedPages ?? 0);
    const refundedPages = Math.max(0, reservedPages - completedPages);
    const nextBalance = currentBalance + refundedPages;

    transaction.set(
      ref,
      {
        creditBalance: nextBalance,
        updatedAt: current,
      },
      { merge: true },
    );
    transaction.set(
      targetJob,
      {
        status,
        refundedPages,
        updatedAt: current,
      },
      { merge: true },
    );

    return {
      completedPages,
      refundedPages,
      creditBalance: nextBalance,
    };
  });
}

const app = express();
app.disable("x-powered-by");
app.use(express.json({ limit: "1mb" }));
app.use((req: Request, res: Response, next: NextFunction) => {
  const requestId = randomUUID();
  (req as AuthedRequest).requestId = requestId;
  res.setHeader("x-request-id", requestId);
  logger.info("Billing request start", {
    requestId,
    method: req.method,
    path: req.path,
  });
  next();
});
app.use(authenticate);

app.get("/billing/status", async (req: Request, res: Response) => {
  try {
    const { uid } = (req as AuthedRequest).user;
    await expireStaleJobs(uid);
    const status = await readUserState(uid);
    res.json(status);
  } catch (error) {
    sendBillingError(req, res, error);
  }
});

app.post("/billing/purchases/android/verify", async (req: Request, res: Response) => {
  try {
    const { uid } = (req as AuthedRequest).user;
    const body = (req.body ?? {}) as Record<string, unknown>;
    const productId = String(body.productId ?? "");
    const purchaseToken = String(body.purchaseToken ?? "");
    const packageName = String(body.packageName ?? ANDROID_PACKAGE_NAME);
    const isRestore = Boolean(body.isRestore);
    const orderId = typeof body.orderId === "string" ? body.orderId : undefined;

    if (!productId || !purchaseToken) {
      throw new BillingHttpError(422, {
        code: "invalid_request",
        message: "productId and purchaseToken are required.",
      });
    }

    logger.info("Verify purchase request", {
      requestId: requestIdOf(req),
      uid,
      productId,
      isRestore,
      orderId,
      packageName,
      purchaseTokenSuffix:
        purchaseToken.length <= 8
          ? purchaseToken
          : purchaseToken.slice(purchaseToken.length - 8),
    });

    const result = await applyPurchaseGrant({
      uid,
      productId,
      purchaseToken,
      packageName,
      isRestore,
    });
    res.json(result);
  } catch (error) {
    sendBillingError(req, res, error);
  }
});

app.post("/ocr/jobs", async (req: Request, res: Response) => {
  try {
    const { uid } = (req as AuthedRequest).user;
    const body = (req.body ?? {}) as Record<string, unknown>;
    const requestedPages = asInt(body.requestedPages);
    const bookId = asInt(body.bookId);
    const result = await reserveOcrJob({
      uid,
      requestedPages,
      bookId,
    });
    res.json(result);
  } catch (error) {
    sendBillingError(req, res, error);
  }
});

app.post("/ocr/jobs/:jobId/finalize", async (req: Request, res: Response) => {
  try {
    const { uid } = (req as AuthedRequest).user;
    const body = (req.body ?? {}) as Record<string, unknown>;
    const result = await finalizeOcrJob({
      uid,
      jobId: asSingleString(req.params.jobId),
      status: String(body.status ?? ""),
    });
    res.json(result);
  } catch (error) {
    sendBillingError(req, res, error);
  }
});

export const billingApiV2 = onRequest(
  {
    region: REGION,
    timeoutSeconds: 60,
    memory: "256MiB",
    serviceAccount: BILLING_SERVICE_ACCOUNT,
  },
  app,
);

// ---------------------------------------------------------------------------
// RTDN – Google Play Real-Time Developer Notifications
// ---------------------------------------------------------------------------

const PLAY_RTDN_TOPIC =
  process.env.PLAY_RTDN_TOPIC ?? "play-rtdn";

// OneTimeProductNotification.notificationType values we care about:
//   2 = ONE_TIME_PRODUCT_CANCELED  (refund)
//   5 = ONE_TIME_PRODUCT_REVOKED   (voided / chargedback)
const REVOKE_NOTIFICATION_TYPES = new Set([2, 5]);

/**
 * Revoke a single purchase identified by its token.
 *
 * - Marks the purchase_ledger entry as `revoked: true`.
 * - If the grant was an unlock: re-checks whether the user still has any
 *   non-revoked unlock purchase.  If not, sets `ocrUnlocked = false`.
 * - If the grant was credits: deducts `grantedCredits` from the user's
 *   balance (floor at 0).
 */
async function revokePurchase(purchaseToken: string): Promise<void> {
  const ledger = purchaseLedgerRef(purchaseToken);
  const ledgerSnap = await ledger.get();

  if (!ledgerSnap.exists) {
    logger.warn("revokePurchase: ledger entry not found", { purchaseToken: purchaseToken.slice(-8) });
    return;
  }

  const data = ledgerSnap.data() ?? {};
  if (data.revoked === true) {
    logger.info("revokePurchase: already revoked", { purchaseToken: purchaseToken.slice(-8) });
    return;
  }

  const uid = String(data.uid ?? "");
  const grantType = String(data.grantType ?? "");
  const grantedCredits = asInt(data.grantedCredits ?? 0);
  const current = now();

  // Mark ledger entry revoked.
  await ledger.set({ revoked: true, updatedAt: current }, { merge: true });

  const ref = userRef(uid);

  if (grantType === "unlock") {
    // Check whether the user still has ANY non-revoked unlock purchase.
    const otherUnlocks = await db
      .collection("purchase_ledger")
      .where("uid", "==", uid)
      .where("grantType", "==", "unlock")
      .where("revoked", "==", false)
      .limit(1)
      .get();

    if (otherUnlocks.empty) {
      await ref.set({ ocrUnlocked: false, updatedAt: current }, { merge: true });
      logger.info("revokePurchase: unlock revoked, user no longer Pro", { uid });
    } else {
      logger.info("revokePurchase: unlock revoked, user still has another unlock", { uid });
    }
  }

  if (grantType === "credits") {
    await db.runTransaction(async (transaction) => {
      const userSnap = await transaction.get(ref);
      const userData = userSnap.exists ? userSnap.data() ?? {} : defaultUserDoc(current);
      const newBalance = Math.max(0, asInt(userData.creditBalance ?? 0) - grantedCredits);

      transaction.set(ref, { creditBalance: newBalance, updatedAt: current }, { merge: true });
    });
    logger.info("revokePurchase: credits deducted", { uid, grantedCredits });
  }
}

/**
 * Cloud Function triggered by Google Play RTDN via Pub/Sub.
 *
 * Message data (base64-decoded) is a JSON object:
 * {
 *   "version": "1.0",
 *   "packageName": "moe.matthew.mekuru",
 *   "eventTimeMillis": "...",
 *   "oneTimeProductNotification": {
 *     "version": "1.0",
 *     "notificationType": 2,   // or 5
 *     "purchaseToken": "...",
 *     "sku": "pro_unlock_v1"
 *   }
 * }
 */
export const handlePlayNotification = onMessagePublished(
  {
    topic: PLAY_RTDN_TOPIC,
    region: REGION,
    serviceAccount: BILLING_SERVICE_ACCOUNT,
  },
  async (event) => {
    const message = event.data?.message;
    const raw =
      typeof message?.json === "object" && message.json != null
        ? message.json
        : (() => {
            try {
              return JSON.parse(
                Buffer.from(message?.data ?? "", "base64").toString("utf-8"),
              );
            } catch {
              return null;
            }
          })();

    if (raw == null) {
      logger.warn("handlePlayNotification: unreadable message", { data: message?.data });
      return;
    }

    const notification = raw.oneTimeProductNotification;
    if (notification == null) {
      // Subscription or test notification — ignore.
      logger.info("handlePlayNotification: not a one-time product notification, ignoring");
      return;
    }

    const notificationType = asInt(notification.notificationType ?? 0);
    if (!REVOKE_NOTIFICATION_TYPES.has(notificationType)) {
      logger.info("handlePlayNotification: ignoring notification type", { notificationType });
      return;
    }

    const purchaseToken = String(notification.purchaseToken ?? "");
    if (!purchaseToken) {
      logger.warn("handlePlayNotification: missing purchaseToken");
      return;
    }

    logger.info("handlePlayNotification: revoking purchase", {
      notificationType,
      sku: notification.sku,
      purchaseTokenSuffix: purchaseToken.slice(-8),
    });

    await revokePurchase(purchaseToken);
  },
);
