const elements = {
  chipRow: document.querySelector("#chip-row"),
  clearCredentialsButton: document.querySelector("#clear-credentials-button"),
  cards: document.querySelector("#cards"),
  emailInput: document.querySelector("#email-input"),
  emptyState: document.querySelector("#empty-state"),
  loginForm: document.querySelector("#login-form"),
  logoutButton: document.querySelector("#logout-button"),
  messageBar: document.querySelector("#message-bar"),
  passwordInput: document.querySelector("#password-input"),
  refreshButton: document.querySelector("#refresh-button"),
  rememberInput: document.querySelector("#remember-input"),
  statusLine: document.querySelector("#status-line"),
  structureOutput: document.querySelector("#structure-output"),
  totpButton: document.querySelector("#totp-button"),
  totpCodeInput: document.querySelector("#totp-code-input"),
  totpForm: document.querySelector("#totp-form"),
  totpSecretInput: document.querySelector("#totp-secret-input"),
  twoFactorHint: document.querySelector("#two-factor-hint")
};

const state = {
  nextRefreshAt: 0,
  pendingTwoFactor: null,
  status: null,
  structure: null,
  subscriptions: []
};

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

async function api(path, options = {}) {
  const init = {
    method: options.method || "GET",
    headers: {}
  };
  if (options.body !== undefined) {
    init.headers["Content-Type"] = "application/json";
    init.body = JSON.stringify(options.body);
  }
  const response = await fetch(path, init);
  const payload = await response.json().catch(() => ({
    message: "服务端没有返回 JSON。"
  }));
  if (!response.ok) {
    const error = new Error(payload.message || "请求失败。");
    error.status = response.status;
    error.code = payload.code || null;
    throw error;
  }
  return payload;
}

function setMessage(message, tone = "info") {
  if (!message) {
    elements.messageBar.textContent = "";
    elements.messageBar.className = "message-bar is-hidden";
    return;
  }
  elements.messageBar.textContent = message;
  elements.messageBar.className = `message-bar is-${tone}`;
}

function formatCurrency(value) {
  return `$${Number(value || 0).toFixed(2)}`;
}

function formatDateTime(iso) {
  if (!iso) {
    return "未设置";
  }
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) {
    return "未设置";
  }
  return new Intl.DateTimeFormat("zh-CN", {
    dateStyle: "medium",
    timeStyle: "short"
  }).format(date);
}

function formatDuration(ms) {
  if (!Number.isFinite(ms) || ms <= 0) {
    return "已到期";
  }
  const totalMinutes = Math.floor(ms / 60000);
  const days = Math.floor(totalMinutes / 1440);
  const hours = Math.floor((totalMinutes % 1440) / 60);
  const minutes = totalMinutes % 60;
  if (days > 0) {
    return `${days} 天 ${hours} 小时`;
  }
  if (hours > 0) {
    return `${hours} 小时 ${minutes} 分钟`;
  }
  return `${minutes} 分钟`;
}

function formatExpires(item) {
  if (!item.expiresAtIso) {
    return "无到期时间";
  }
  if (item.expiresInDays === null) {
    return formatDateTime(item.expiresAtIso);
  }
  if (item.expiresInDays < 0) {
    return `${formatDateTime(item.expiresAtIso)} · 已过期`;
  }
  if (item.expiresInDays === 0) {
    return `${formatDateTime(item.expiresAtIso)} · 今天到期`;
  }
  if (item.expiresInDays === 1) {
    return `${formatDateTime(item.expiresAtIso)} · 明天到期`;
  }
  return `${formatDateTime(item.expiresAtIso)} · 还剩 ${item.expiresInDays} 天`;
}

function metricTone(metric) {
  if (!metric) {
    return "";
  }
  if (metric.percent >= 90) {
    return "is-danger";
  }
  if (metric.percent >= 70) {
    return "is-warn";
  }
  return "";
}

function renderMetric(label, metric) {
  if (!metric) {
    return "";
  }
  return `
    <section class="metric">
      <div class="metric-head">
        <div>
          <strong>${escapeHtml(label)}</strong>
          <span>${escapeHtml(formatCurrency(metric.usedUsd))} / ${escapeHtml(formatCurrency(metric.limitUsd))}</span>
        </div>
        <div>
          <strong>${escapeHtml(formatCurrency(metric.remainingUsd))}</strong>
          <span>剩余</span>
        </div>
      </div>
      <div class="progress-track">
        <div class="progress-fill ${metricTone(metric)}" style="width: ${Math.min(metric.percent, 100).toFixed(2)}%"></div>
      </div>
      <div class="metric-foot">
        ${metric.resetInMs && metric.resetInMs > 0 ? `${escapeHtml(formatDuration(metric.resetInMs))} 后重置` : "窗口未激活"}
      </div>
    </section>
  `;
}

function renderCards() {
  if (!state.subscriptions.length) {
    elements.cards.innerHTML = "";
    elements.emptyState.classList.remove("is-hidden");
    elements.emptyState.textContent = state.status?.authenticated
      ? "当前没有活跃订阅，或者订阅接口还没有返回数据。"
      : "尚未登录，登录后这里会展示真实订阅卡片。";
    return;
  }
  elements.emptyState.classList.add("is-hidden");
  elements.cards.innerHTML = state.subscriptions
    .map((item) => {
      return `
        <article class="usage-card status-${escapeHtml(item.status || "unknown")}">
          <div class="usage-card-head">
            <div>
              <h3>${escapeHtml(item.groupName)}</h3>
              <p>${escapeHtml(item.groupDescription || "无分组描述")}</p>
            </div>
            <span class="badge status-${escapeHtml(item.status || "unknown")}">${escapeHtml(item.status || "unknown")}</span>
          </div>

          <dl class="meta-row">
            <dt>到期</dt>
            <dd>${escapeHtml(formatExpires(item))}</dd>
          </dl>

          ${renderMetric("每日", item.usage?.daily)}
          ${renderMetric("每周", item.usage?.weekly)}
          ${renderMetric("每月", item.usage?.monthly)}

          ${
            item.unlimited
              ? `
                <div class="unlimited-box">
                  <strong>无限额度</strong>
                  <span>当前分组没有日 / 周 / 月 USD 上限。</span>
                </div>
              `
              : ""
          }
        </article>
      `;
    })
    .join("");
}

function renderStructure() {
  if (!state.structure) {
    elements.structureOutput.textContent = "结构摘要尚未加载。";
    return;
  }
  elements.structureOutput.textContent = JSON.stringify(state.structure, null, 2);
}

function renderChips() {
  const status = state.status;
  if (!status) {
    elements.chipRow.innerHTML = "";
    return;
  }
  const chips = [
    `<span class="chip"><strong>认证</strong>${status.authenticated ? "已登录" : "未登录"}</span>`,
    `<span class="chip"><strong>自动重登</strong>${status.credentialsSource === "config" ? "来自配置文件" : status.hasSavedCredentials ? "已保存凭据" : "未配置"}</span>`,
    `<span class="chip"><strong>站点</strong>${escapeHtml(status.publicSettings?.siteName || "GMN")}</span>`,
    `<span class="chip"><strong>Turnstile</strong>${status.publicSettings?.turnstileEnabled ? "已开启" : "未开启"}</span>`
  ];
  if (status.expiresInSeconds !== null) {
    chips.push(
      `<span class="chip"><strong>Token</strong>${escapeHtml(formatDuration(status.expiresInSeconds * 1000))} 后续期</span>`
    );
  }
  if (status.lastFetchedAt) {
    chips.push(
      `<span class="chip"><strong>上次同步</strong>${escapeHtml(formatDateTime(status.lastFetchedAt))}</span>`
    );
  }
  elements.chipRow.innerHTML = chips.join("");
}

function syncPendingTwoFactor() {
  if (state.pendingTwoFactor?.tempToken) {
    elements.totpForm.classList.remove("is-hidden");
    elements.twoFactorHint.textContent = state.pendingTwoFactor.userEmailMasked
      ? `账号 ${state.pendingTwoFactor.userEmailMasked} 需要输入 2FA 验证码。`
      : "请填入当前 TOTP 验证码。";
  } else {
    elements.totpForm.classList.add("is-hidden");
    elements.totpCodeInput.value = "";
  }
}

function renderStatusLine() {
  if (!state.status) {
    elements.statusLine.textContent = "正在连接本地代理…";
    return;
  }
  const parts = [
    state.status.authenticated ? "已登录" : "未登录"
  ];
  if (state.status.user?.email) {
    parts.push(state.status.user.email);
  }
  if (state.nextRefreshAt > Date.now()) {
    parts.push(`下次刷新 ${formatDuration(state.nextRefreshAt - Date.now())}`);
  }
  if (state.status.lastError?.message) {
    parts.push(`最近错误：${state.status.lastError.message}`);
  }
  elements.statusLine.textContent = parts.join(" · ");
}

function renderAll() {
  renderStatusLine();
  renderChips();
  renderCards();
  renderStructure();
  syncPendingTwoFactor();
}

async function refreshStatus() {
  const response = await api("/api/status");
  state.status = response.data;
  state.pendingTwoFactor = response.data.pendingTwoFactor;
}

async function refreshStructure() {
  if (state.structure) {
    return;
  }
  const response = await api("/api/structure");
  state.structure = response.data;
}

async function refreshSubscriptions(force = false) {
  const suffix = force ? "?force=1" : "";
  const response = await api(`/api/subscriptions${suffix}`);
  state.subscriptions = response.data || [];
  if (response.meta?.status) {
    state.status = response.meta.status;
    state.pendingTwoFactor = response.meta.status.pendingTwoFactor;
  }
}

async function refreshAll(force = false) {
  try {
    await refreshStatus();
    await refreshStructure();
    if (state.status?.authenticated || state.status?.hasRefreshToken || state.status?.hasSavedCredentials) {
      await refreshSubscriptions(force);
    } else {
      state.subscriptions = [];
    }
    setMessage("数据已同步。", "success");
  } catch (error) {
    setMessage(error.message, "error");
    try {
      await refreshStatus();
    } catch {
      // Ignore secondary status errors.
    }
  } finally {
    state.nextRefreshAt = Date.now() + (state.status?.uiRefreshMs || 15000);
    renderAll();
  }
}

async function handleLogin(event) {
  event.preventDefault();
  try {
    const payload = {
      email: elements.emailInput.value.trim(),
      password: elements.passwordInput.value,
      totpSecret: elements.totpSecretInput.value.trim(),
      rememberCredentials: elements.rememberInput.checked
    };
    const response = await api("/api/login", {
      method: "POST",
      body: payload
    });
    if (response.twoFactorRequired) {
      state.pendingTwoFactor = response.data;
      setMessage("登录成功进入 2FA 阶段，请补验证码。", "warning");
    } else {
      state.pendingTwoFactor = null;
      setMessage("登录成功。", "success");
    }
    await refreshAll(true);
  } catch (error) {
    setMessage(error.message, "error");
    renderAll();
  }
}

async function handleTwoFactor(event) {
  event.preventDefault();
  if (!state.pendingTwoFactor?.tempToken) {
    setMessage("当前没有待完成的 2FA 登录。", "warning");
    return;
  }
  try {
    await api("/api/login/2fa", {
      method: "POST",
      body: {
        tempToken: state.pendingTwoFactor.tempToken,
        totpCode: elements.totpCodeInput.value.trim(),
        rememberCredentials: elements.rememberInput.checked
      }
    });
    state.pendingTwoFactor = null;
    elements.totpCodeInput.value = "";
    setMessage("2FA 登录完成。", "success");
    await refreshAll(true);
  } catch (error) {
    setMessage(error.message, "error");
  }
}

async function handleLogout() {
  try {
    await api("/api/logout", {
      method: "POST"
    });
    state.subscriptions = [];
    state.pendingTwoFactor = null;
    setMessage("已退出当前会话。", "info");
    await refreshAll(true);
  } catch (error) {
    setMessage(error.message, "error");
  }
}

async function handleClearCredentials() {
  try {
    await api("/api/credentials", {
      method: "DELETE"
    });
    setMessage("已清除本地保存的自动重登凭据。", "info");
    await refreshAll(true);
  } catch (error) {
    setMessage(error.message, "error");
  }
}

elements.loginForm.addEventListener("submit", handleLogin);
elements.totpForm.addEventListener("submit", handleTwoFactor);
elements.refreshButton.addEventListener("click", () => refreshAll(true));
elements.logoutButton.addEventListener("click", handleLogout);
elements.clearCredentialsButton.addEventListener("click", handleClearCredentials);

setInterval(() => {
  renderStatusLine();
}, 1000);

refreshAll(true);
