import crypto from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import http from "node:http";
import path from "node:path";
import { fileURLToPath } from "node:url";

const APP_DIR = path.dirname(fileURLToPath(import.meta.url));
const DATA_DIR = path.join(APP_DIR, "data");
const PUBLIC_DIR = path.join(APP_DIR, "public");
const SESSION_FILE = path.join(DATA_DIR, "session.json");
const CREDENTIALS_FILE = path.join(DATA_DIR, "credentials.json");
const CONFIG_FILE = path.join(APP_DIR, "config.json");

const STATIC_TYPES = {
  ".css": "text/css; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".txt": "text/plain; charset=utf-8"
};

const LIVE_STRUCTURE = {
  extractedAt: "2026-03-11",
  sourceUrl: "https://gmn.chuangzuoli.com/subscriptions",
  framework: "Vue SPA",
  apiBase: "/api/v1",
  localStorageKeys: [
    "auth_token",
    "refresh_token",
    "token_expires_at",
    "auth_user"
  ],
  authEndpoints: {
    login: "POST /api/v1/auth/login",
    login2FA: "POST /api/v1/auth/login/2fa",
    refresh: "POST /api/v1/auth/refresh",
    me: "GET /api/v1/auth/me",
    logout: "POST /api/v1/auth/logout"
  },
  subscriptionEndpoints: {
    list: "GET /api/v1/subscriptions",
    active: "GET /api/v1/subscriptions/active",
    progress: "GET /api/v1/subscriptions/progress",
    summary: "GET /api/v1/subscriptions/summary",
    itemProgress: "GET /api/v1/subscriptions/:id/progress"
  },
  currentPageFields: [
    "id",
    "group_id",
    "group.name",
    "group.description",
    "status",
    "expires_at",
    "group.daily_limit_usd",
    "daily_usage_usd",
    "daily_window_start",
    "group.weekly_limit_usd",
    "weekly_usage_usd",
    "weekly_window_start",
    "group.monthly_limit_usd",
    "monthly_usage_usd",
    "monthly_window_start"
  ]
};

class ApiError extends Error {
  constructor(message, details = {}) {
    super(message);
    this.name = "ApiError";
    this.status = details.status ?? 500;
    this.code = details.code ?? null;
    this.payload = details.payload ?? null;
    this.cause = details.cause;
  }
}

class AuthenticationRequiredError extends Error {
  constructor(message = "登录态已失效，需要重新登录。") {
    super(message);
    this.name = "AuthenticationRequiredError";
    this.status = 401;
    this.code = "AUTH_REQUIRED";
  }
}

class TwoFactorRequiredError extends Error {
  constructor(tempToken, userEmailMasked) {
    super("需要输入 2FA 验证码。");
    this.name = "TwoFactorRequiredError";
    this.status = 202;
    this.code = "TWO_FACTOR_REQUIRED";
    this.tempToken = tempToken;
    this.userEmailMasked = userEmailMasked ?? "";
  }
}

function detectTimezone() {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
  } catch {
    return "UTC";
  }
}

function toNumber(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function normalizeSecret(value) {
  if (!value || typeof value !== "string") {
    return "";
  }
  const trimmed = value.trim();
  if (!trimmed) {
    return "";
  }
  if (trimmed.startsWith("otpauth://")) {
    try {
      const url = new URL(trimmed);
      return (url.searchParams.get("secret") || "").trim().toUpperCase();
    } catch {
      return "";
    }
  }
  return trimmed.replace(/\s+/g, "").toUpperCase();
}

function normalizeCredentials(value) {
  if (!value || typeof value !== "object") {
    return null;
  }
  const email = String(value.email || "").trim();
  const password = String(value.password || "");
  const totpSecret = normalizeSecret(value.totpSecret || "");
  if (!email || !password) {
    return null;
  }
  return { email, password, totpSecret };
}

async function readJson(filePath, fallback = null) {
  try {
    const raw = await readFile(filePath, "utf8");
    return JSON.parse(raw);
  } catch (error) {
    if (error && error.code === "ENOENT") {
      return fallback;
    }
    throw error;
  }
}

async function writeJson(filePath, value) {
  await mkdir(path.dirname(filePath), { recursive: true });
  const content = `${JSON.stringify(value, null, 2)}\n`;
  await writeFile(filePath, content, { mode: 0o600 });
}

function serializeError(error) {
  return {
    name: error?.name || "Error",
    message: error?.message || "Unknown error",
    code: error?.code || null,
    status: error?.status || 500,
    at: new Date().toISOString()
  };
}

function sendJson(res, statusCode, payload) {
  res.writeHead(statusCode, {
    "Cache-Control": "no-store",
    "Content-Type": "application/json; charset=utf-8"
  });
  res.end(`${JSON.stringify(payload)}\n`);
}

function sendError(res, error) {
  if (error instanceof TwoFactorRequiredError) {
    sendJson(res, 202, {
      ok: false,
      twoFactorRequired: true,
      data: {
        tempToken: error.tempToken,
        userEmailMasked: error.userEmailMasked
      }
    });
    return;
  }
  const status = error?.status || 500;
  sendJson(res, status, {
    ok: false,
    message: error?.message || "Internal server error",
    code: error?.code || null,
    status
  });
}

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(chunk);
  }
  if (chunks.length === 0) {
    return {};
  }
  const raw = Buffer.concat(chunks).toString("utf8");
  try {
    return JSON.parse(raw);
  } catch {
    throw new ApiError("请求体不是合法 JSON。", {
      status: 400,
      code: "BAD_JSON"
    });
  }
}

function decodeBase32(input) {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  const clean = normalizeSecret(input).replace(/=+$/, "");
  let bits = "";
  for (const char of clean) {
    const index = alphabet.indexOf(char);
    if (index === -1) {
      throw new ApiError("TOTP Secret 不是合法的 Base32。", {
        status: 400,
        code: "BAD_TOTP_SECRET"
      });
    }
    bits += index.toString(2).padStart(5, "0");
  }
  const bytes = [];
  for (let index = 0; index + 8 <= bits.length; index += 8) {
    bytes.push(Number.parseInt(bits.slice(index, index + 8), 2));
  }
  return Buffer.from(bytes);
}

function generateTotp(secret, now = Date.now()) {
  const key = decodeBase32(secret);
  const counter = Math.floor(now / 1000 / 30);
  const message = Buffer.alloc(8);
  message.writeBigUInt64BE(BigInt(counter));
  const hash = crypto.createHmac("sha1", key).update(message).digest();
  const offset = hash[hash.length - 1] & 0x0f;
  const code = (
    ((hash[offset] & 0x7f) << 24) |
    ((hash[offset + 1] & 0xff) << 16) |
    ((hash[offset + 2] & 0xff) << 8) |
    (hash[offset + 3] & 0xff)
  ) % 1000000;
  return String(code).padStart(6, "0");
}

function buildUsageWindow(limit, used, windowStart, hours) {
  if (!Number.isFinite(Number(limit)) || Number(limit) <= 0) {
    return null;
  }
  const limitUsd = Number(limit);
  const usedUsd = Number(used || 0);
  const percent = Math.min((usedUsd / limitUsd) * 100, 100);
  let resetAt = null;
  let resetInMs = null;
  if (windowStart) {
    const start = new Date(windowStart);
    if (!Number.isNaN(start.getTime())) {
      const expiresAtMs = start.getTime() + hours * 60 * 60 * 1000;
      resetAt = new Date(expiresAtMs).toISOString();
      resetInMs = expiresAtMs - Date.now();
    }
  }
  return {
    limitUsd,
    usedUsd,
    remainingUsd: Math.max(0, limitUsd - usedUsd),
    percent,
    resetAt,
    resetInMs
  };
}

function enrichSubscription(item) {
  const expiresAt = item.expires_at ? new Date(item.expires_at) : null;
  const expiresAtMs = expiresAt && !Number.isNaN(expiresAt.getTime()) ? expiresAt.getTime() : null;
  return {
    ...item,
    groupName: item.group?.name || `Group #${item.group_id || "Unknown"}`,
    groupDescription: item.group?.description || "",
    expiresAtIso: expiresAtMs ? new Date(expiresAtMs).toISOString() : null,
    expiresInDays: expiresAtMs ? Math.ceil((expiresAtMs - Date.now()) / (24 * 60 * 60 * 1000)) : null,
    unlimited:
      !item.group?.daily_limit_usd &&
      !item.group?.weekly_limit_usd &&
      !item.group?.monthly_limit_usd,
    usage: {
      daily: buildUsageWindow(item.group?.daily_limit_usd, item.daily_usage_usd, item.daily_window_start, 24),
      weekly: buildUsageWindow(item.group?.weekly_limit_usd, item.weekly_usage_usd, item.weekly_window_start, 168),
      monthly: buildUsageWindow(item.group?.monthly_limit_usd, item.monthly_usage_usd, item.monthly_window_start, 720)
    }
  };
}

function buildRuntimeConfig(fileConfig) {
  const merged = {
    port: toNumber(process.env.PORT || fileConfig.port, 3210),
    baseUrl: String(process.env.GMN_BASE_URL || fileConfig.baseUrl || "https://gmn.chuangzuoli.com").replace(/\/+$/, ""),
    apiPrefix: "/api/v1",
    locale: String(process.env.GMN_LOCALE || fileConfig.locale || "zh"),
    timezone: String(process.env.GMN_TIMEZONE || fileConfig.timezone || detectTimezone()),
    uiRefreshMs: toNumber(process.env.GMN_UI_REFRESH_MS || fileConfig.uiRefreshMs, 15000),
    cacheTtlMs: toNumber(process.env.GMN_CACHE_TTL_MS || fileConfig.cacheTtlMs, 5000),
    requestTimeoutMs: toNumber(process.env.GMN_REQUEST_TIMEOUT_MS || fileConfig.requestTimeoutMs, 30000),
    authRefreshLeadMs: toNumber(process.env.GMN_AUTH_REFRESH_LEAD_MS || fileConfig.authRefreshLeadMs, 60000)
  };
  return {
    ...merged,
    inlineCredentials: normalizeCredentials({
      email: process.env.GMN_EMAIL || fileConfig.email,
      password: process.env.GMN_PASSWORD || fileConfig.password,
      totpSecret: process.env.GMN_TOTP_SECRET || fileConfig.totpSecret
    })
  };
}

class GmnMonitor {
  constructor(config) {
    this.config = config;
    this.session = {
      authToken: null,
      refreshToken: null,
      tokenExpiresAt: null,
      user: null,
      updatedAt: null
    };
    this.savedCredentials = null;
    this.publicSettings = null;
    this.pending2FA = null;
    this.refreshPromise = null;
    this.lastSubscriptions = [];
    this.lastFetchedAt = 0;
    this.lastError = null;
  }

  async init() {
    await mkdir(DATA_DIR, { recursive: true });
    const storedSession = await readJson(SESSION_FILE, null);
    if (storedSession) {
      this.session = {
        authToken: storedSession.authToken || null,
        refreshToken: storedSession.refreshToken || null,
        tokenExpiresAt: storedSession.tokenExpiresAt || null,
        user: storedSession.user || null,
        updatedAt: storedSession.updatedAt || null
      };
    }
    this.savedCredentials = normalizeCredentials(await readJson(CREDENTIALS_FILE, null));
    try {
      this.publicSettings = await this.request("/settings/public", {
        auth: false,
        includeTimezone: false
      });
    } catch (error) {
      this.recordError(error);
    }
  }

  getEffectiveCredentials() {
    if (this.config.inlineCredentials) {
      return {
        source: "config",
        credentials: this.config.inlineCredentials
      };
    }
    if (this.savedCredentials) {
      return {
        source: "saved",
        credentials: this.savedCredentials
      };
    }
    return null;
  }

  async request(endpoint, options = {}) {
    const method = options.method || "GET";
    const includeTimezone = options.includeTimezone ?? method === "GET";
    const url = new URL(`${this.config.apiPrefix}${endpoint}`, this.config.baseUrl);
    if (includeTimezone) {
      url.searchParams.set("timezone", this.config.timezone);
    }
    const headers = {
      "Accept-Language": this.config.locale
    };
    if (options.body !== undefined) {
      headers["Content-Type"] = "application/json";
    }
    if (options.auth !== false && this.session.authToken) {
      headers.Authorization = `Bearer ${this.session.authToken}`;
    }

    let response;
    try {
      response = await fetch(url, {
        method,
        headers,
        body: options.body === undefined ? undefined : JSON.stringify(options.body),
        signal: AbortSignal.timeout(this.config.requestTimeoutMs)
      });
    } catch (error) {
      throw new ApiError("网络请求失败。", {
        status: 502,
        code: "NETWORK_ERROR",
        cause: error
      });
    }

    const rawText = await response.text();
    let payload = null;
    if (rawText) {
      try {
        payload = JSON.parse(rawText);
      } catch {
        payload = rawText;
      }
    }

    if (payload && typeof payload === "object" && "code" in payload) {
      if (payload.code !== 0) {
        throw new ApiError(payload.message || payload.detail || "请求失败。", {
          status: response.status,
          code: payload.code,
          payload
        });
      }
      return payload.data;
    }

    if (!response.ok) {
      const message =
        payload && typeof payload === "object"
          ? payload.message || payload.detail || response.statusText
          : response.statusText || "请求失败。";
      throw new ApiError(message, {
        status: response.status,
        code: payload?.code || null,
        payload
      });
    }

    return payload;
  }

  recordError(error) {
    this.lastError = serializeError(error);
  }

  clearError() {
    this.lastError = null;
  }

  async persistSession() {
    await writeJson(SESSION_FILE, this.session);
  }

  async clearSession() {
    this.session = {
      authToken: null,
      refreshToken: null,
      tokenExpiresAt: null,
      user: null,
      updatedAt: null
    };
    this.pending2FA = null;
    await rm(SESSION_FILE, { force: true });
  }

  async saveCredentials(credentials) {
    const normalized = normalizeCredentials(credentials);
    if (!normalized) {
      return;
    }
    this.savedCredentials = normalized;
    await writeJson(CREDENTIALS_FILE, normalized);
  }

  async clearCredentials() {
    this.savedCredentials = null;
    await rm(CREDENTIALS_FILE, { force: true });
  }

  applySession(authData) {
    this.session = {
      authToken: authData.access_token || null,
      refreshToken: authData.refresh_token || null,
      tokenExpiresAt: authData.expires_in
        ? Date.now() + Number(authData.expires_in) * 1000
        : null,
      user: authData.user || this.session.user || null,
      updatedAt: new Date().toISOString()
    };
    this.pending2FA = null;
    this.clearError();
    return this.persistSession();
  }

  async refreshSession() {
    if (!this.session.refreshToken) {
      throw new AuthenticationRequiredError();
    }
    if (this.refreshPromise) {
      return this.refreshPromise;
    }
    this.refreshPromise = (async () => {
      const data = await this.request("/auth/refresh", {
        method: "POST",
        auth: false,
        includeTimezone: false,
        body: {
          refresh_token: this.session.refreshToken
        }
      });
      await this.applySession(data);
      return data;
    })();
    try {
      return await this.refreshPromise;
    } finally {
      this.refreshPromise = null;
    }
  }

  async login(credentials, options = {}) {
    if (this.publicSettings?.turnstile_enabled) {
      throw new ApiError("当前站点已启用 Turnstile，自动重登需要人工介入。", {
        status: 400,
        code: "TURNSTILE_ENABLED"
      });
    }
    const normalized = normalizeCredentials(credentials);
    if (!normalized) {
      throw new ApiError("缺少账号或密码。", {
        status: 400,
        code: "MISSING_CREDENTIALS"
      });
    }
    const data = await this.request("/auth/login", {
      method: "POST",
      auth: false,
      includeTimezone: false,
      body: {
        email: normalized.email,
        password: normalized.password
      }
    });
    if (data?.temp_token && !data?.access_token) {
      if (normalized.totpSecret) {
        return this.completeTwoFactor(data.temp_token, generateTotp(normalized.totpSecret), {
          rememberCredentials: Boolean(options.rememberCredentials),
          credentials: normalized
        });
      }
      this.pending2FA = {
        tempToken: data.temp_token,
        userEmailMasked: data.user_email_masked || "",
        credentials: normalized
      };
      throw new TwoFactorRequiredError(data.temp_token, data.user_email_masked);
    }
    await this.applySession(data);
    if (options.rememberCredentials) {
      await this.saveCredentials(normalized);
    }
    return data;
  }

  async completeTwoFactor(tempToken, totpCode, options = {}) {
    if (!tempToken || !totpCode) {
      throw new ApiError("缺少 2FA 参数。", {
        status: 400,
        code: "MISSING_2FA"
      });
    }
    const credentialsToPersist = options.credentials || this.pending2FA?.credentials;
    const data = await this.request("/auth/login/2fa", {
      method: "POST",
      auth: false,
      includeTimezone: false,
      body: {
        temp_token: tempToken,
        totp_code: totpCode
      }
    });
    await this.applySession(data);
    if (options.rememberCredentials && credentialsToPersist) {
      await this.saveCredentials(credentialsToPersist);
    }
    return data;
  }

  async ensureAuthenticated() {
    const now = Date.now();
    if (
      this.session.authToken &&
      this.session.tokenExpiresAt &&
      now < this.session.tokenExpiresAt - this.config.authRefreshLeadMs
    ) {
      return;
    }
    if (this.session.refreshToken) {
      try {
        await this.refreshSession();
        return;
      } catch {
        await this.clearSession();
      }
    }
    const effectiveCredentials = this.getEffectiveCredentials();
    if (effectiveCredentials) {
      await this.login(effectiveCredentials.credentials, {
        rememberCredentials: effectiveCredentials.source === "saved"
      });
      return;
    }
    throw new AuthenticationRequiredError();
  }

  async fetchSubscriptions(force = false) {
    if (!force && this.lastFetchedAt && Date.now() - this.lastFetchedAt < this.config.cacheTtlMs) {
      return this.lastSubscriptions;
    }
    try {
      await this.ensureAuthenticated();
      let subscriptions;
      try {
        subscriptions = await this.request("/subscriptions");
      } catch (error) {
        if (error.status === 401) {
          await this.ensureAuthenticated();
          subscriptions = await this.request("/subscriptions");
        } else {
          throw error;
        }
      }
      this.lastSubscriptions = Array.isArray(subscriptions)
        ? subscriptions.map(enrichSubscription)
        : [];
      this.lastFetchedAt = Date.now();
      this.clearError();
      return this.lastSubscriptions;
    } catch (error) {
      this.recordError(error);
      throw error;
    }
  }

  async logout() {
    try {
      if (this.session.refreshToken) {
        await this.request("/auth/logout", {
          method: "POST",
          auth: false,
          includeTimezone: false,
          body: {
            refresh_token: this.session.refreshToken
          }
        });
      }
    } catch {
      // Ignore remote logout failures and clear local state anyway.
    }
    await this.clearSession();
  }

  getStatus() {
    const effectiveCredentials = this.getEffectiveCredentials();
    const expiresInSeconds = this.session.tokenExpiresAt
      ? Math.max(0, Math.floor((this.session.tokenExpiresAt - Date.now()) / 1000))
      : null;
    return {
      authenticated: Boolean(this.session.authToken),
      hasRefreshToken: Boolean(this.session.refreshToken),
      hasSavedCredentials: Boolean(this.savedCredentials),
      credentialsSource: effectiveCredentials?.source || null,
      expiresAt: this.session.tokenExpiresAt
        ? new Date(this.session.tokenExpiresAt).toISOString()
        : null,
      expiresInSeconds,
      user: this.session.user
        ? {
            email: this.session.user.email || "",
            nickname: this.session.user.nickname || "",
            role: this.session.user.role || ""
          }
        : null,
      pendingTwoFactor: this.pending2FA
        ? {
            tempToken: this.pending2FA.tempToken,
            userEmailMasked: this.pending2FA.userEmailMasked
          }
        : null,
      publicSettings: this.publicSettings
        ? {
            siteName: this.publicSettings.site_name || "GMN",
            turnstileEnabled: Boolean(this.publicSettings.turnstile_enabled),
            purchaseEnabled: Boolean(this.publicSettings.purchase_subscription_enabled)
          }
        : null,
      lastFetchedAt: this.lastFetchedAt ? new Date(this.lastFetchedAt).toISOString() : null,
      lastError: this.lastError,
      uiRefreshMs: this.config.uiRefreshMs
    };
  }
}

async function serveStatic(url, res) {
  const requestedPath = url.pathname === "/" ? "/index.html" : url.pathname;
  const normalizedPath = path
    .normalize(requestedPath)
    .replace(/^(\.\.(\/|\\|$))+/, "")
    .replace(/^[/\\]+/, "");
  const filePath = path.join(PUBLIC_DIR, normalizedPath);
  if (!filePath.startsWith(PUBLIC_DIR)) {
    sendJson(res, 403, {
      ok: false,
      message: "Forbidden"
    });
    return;
  }
  if (!existsSync(filePath)) {
    sendJson(res, 404, {
      ok: false,
      message: "Not Found"
    });
    return;
  }
  const ext = path.extname(filePath);
  const contentType = STATIC_TYPES[ext] || "application/octet-stream";
  const content = await readFile(filePath);
  res.writeHead(200, {
    "Cache-Control": "no-store",
    "Content-Type": contentType
  });
  res.end(content);
}

async function main() {
  const fileConfig = (await readJson(CONFIG_FILE, {})) || {};
  const config = buildRuntimeConfig(fileConfig);
  const monitor = new GmnMonitor(config);
  await monitor.init();

  const server = http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url || "/", `http://${req.headers.host || "127.0.0.1"}`);

      if (url.pathname === "/api/health") {
        sendJson(res, 200, {
          ok: true,
          data: {
            status: "ok"
          }
        });
        return;
      }

      if (url.pathname === "/api/structure" && req.method === "GET") {
        sendJson(res, 200, {
          ok: true,
          data: LIVE_STRUCTURE
        });
        return;
      }

      if (url.pathname === "/api/status" && req.method === "GET") {
        sendJson(res, 200, {
          ok: true,
          data: monitor.getStatus()
        });
        return;
      }

      if (url.pathname === "/api/subscriptions" && req.method === "GET") {
        const force = url.searchParams.get("force") === "1";
        const data = await monitor.fetchSubscriptions(force);
        sendJson(res, 200, {
          ok: true,
          data,
          meta: {
            fetchedAt: new Date().toISOString(),
            status: monitor.getStatus()
          }
        });
        return;
      }

      if (url.pathname === "/api/login" && req.method === "POST") {
        const body = await readBody(req);
        try {
          await monitor.login(body, {
            rememberCredentials: Boolean(body.rememberCredentials)
          });
          sendJson(res, 200, {
            ok: true,
            data: monitor.getStatus()
          });
        } catch (error) {
          sendError(res, error);
        }
        return;
      }

      if (url.pathname === "/api/login/2fa" && req.method === "POST") {
        const body = await readBody(req);
        await monitor.completeTwoFactor(body.tempToken, body.totpCode, {
          rememberCredentials: Boolean(body.rememberCredentials)
        });
        sendJson(res, 200, {
          ok: true,
          data: monitor.getStatus()
        });
        return;
      }

      if (url.pathname === "/api/logout" && req.method === "POST") {
        await monitor.logout();
        sendJson(res, 200, {
          ok: true,
          data: monitor.getStatus()
        });
        return;
      }

      if (url.pathname === "/api/credentials" && req.method === "DELETE") {
        await monitor.clearCredentials();
        sendJson(res, 200, {
          ok: true,
          data: monitor.getStatus()
        });
        return;
      }

      await serveStatic(url, res);
    } catch (error) {
      sendError(res, error);
    }
  });

  server.listen(config.port, "127.0.0.1", () => {
    console.log(
      `GMN Usage Monitor is listening at http://127.0.0.1:${config.port}`
    );
  });
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
