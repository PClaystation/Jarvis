const apiBaseInput = document.getElementById("apiBaseInput");
const tokenInput = document.getElementById("tokenInput");
const saveTokenBtn = document.getElementById("saveTokenBtn");
const testTokenBtn = document.getElementById("testTokenBtn");
const loadDevicesBtn = document.getElementById("loadDevicesBtn");
const deviceSummary = document.getElementById("deviceSummary");
const deviceCards = document.getElementById("deviceCards");
const deviceList = document.getElementById("deviceList");
const authHint = document.getElementById("authHint");
const connectionBadge = document.getElementById("connectionBadge");
const lastSuccessLabel = document.getElementById("lastSuccessLabel");
const targetInput = document.getElementById("targetInput");
const actionSelect = document.getElementById("actionSelect");
const argInput = document.getElementById("argInput");
const dangerZone = document.getElementById("dangerZone");
const composeBtn = document.getElementById("composeBtn");
const speakBtn = document.getElementById("speakBtn");
const sendBtn = document.getElementById("sendBtn");
const commandText = document.getElementById("commandText");
const resultBox = document.getElementById("resultBox");
const resultStatus = document.getElementById("resultStatus");
const resultRequestId = document.getElementById("resultRequestId");
const resultLatency = document.getElementById("resultLatency");
const resultMessage = document.getElementById("resultMessage");
const speechInfo = document.getElementById("speechInfo");
const updateTargetInput = document.getElementById("updateTargetInput");
const updateVersionInput = document.getElementById("updateVersionInput");
const updateUrlInput = document.getElementById("updateUrlInput");
const updateShaInput = document.getElementById("updateShaInput");
const updateSizeInput = document.getElementById("updateSizeInput");
const pushUpdateBtn = document.getElementById("pushUpdateBtn");

const TOKEN_KEY = "jarvis_phone_api_token";
const TARGET_KEY = "jarvis_last_target";
const API_BASE_KEY = "jarvis_api_base_url";
const UPDATE_TARGET_KEY = "jarvis_update_target";
const UPDATE_VERSION_KEY = "jarvis_update_version";
const UPDATE_URL_KEY = "jarvis_update_url";
const UPDATE_SHA_KEY = "jarvis_update_sha";
const UPDATE_SIZE_KEY = "jarvis_update_size";
const LAST_COMMAND_SUCCESS_KEY = "jarvis_last_command_success";
const BOOTSTRAP_COMMAND_KEY = "jarvis_bootstrap_command";
const BOOTSTRAP_ACTION_KEY = "jarvis_bootstrap_action";
const BOOTSTRAP_ARG_KEY = "jarvis_bootstrap_arg";

const POLL_INTERVAL_MS = 30000;
const dangerousActions = new Set(["shutdown", "restart", "sleep"]);

let pollTimer = null;

class ApiError extends Error {
  constructor(message, status) {
    super(message);
    this.name = "ApiError";
    this.status = status;
  }
}

function nowRequestId() {
  return "web-" + Date.now() + "-" + Math.random().toString(16).slice(2, 8);
}

function normalizeBase(input) {
  const value = (input || "").trim();
  if (!value) {
    return "";
  }

  const wsMapped = value.replace(/^wss?:\/\//i, (scheme) => (scheme.toLowerCase() === "wss://" ? "https://" : "http://"));
  const hasScheme = /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(wsMapped);
  const candidate = hasScheme ? wsMapped : `${window.location.protocol === "https:" ? "https://" : "http://"}${wsMapped}`;

  try {
    const url = new URL(candidate);
    return `${url.protocol}//${url.host}`;
  } catch {
    return wsMapped.replace(/\/+$/, "");
  }
}

function coerceApiBaseForContext(input) {
  const normalized = normalizeBase(input);
  if (!normalized) {
    return "";
  }

  try {
    const url = new URL(normalized);

    if (window.location.protocol === "https:" && url.protocol === "http:") {
      url.protocol = "https:";
      if (url.port === "80" || url.port === "8080") {
        url.port = "";
      }
    }

    return `${url.protocol}//${url.host}`;
  } catch {
    return normalized;
  }
}

function defaultApiBase() {
  if (window.location.hostname.endsWith("github.io")) {
    return "https://mpmc.ddns.net";
  }

  return window.location.origin;
}

function getApiBase() {
  const stored = localStorage.getItem(API_BASE_KEY);
  let resolved;

  if (stored) {
    resolved = coerceApiBaseForContext(stored);
    if (resolved && resolved !== stored) {
      localStorage.setItem(API_BASE_KEY, resolved);
    }
    return resolved;
  }

  resolved = coerceApiBaseForContext(defaultApiBase());
  if (resolved) {
    localStorage.setItem(API_BASE_KEY, resolved);
  }
  return resolved;
}

function setApiBase(value) {
  const normalized = coerceApiBaseForContext(value);
  if (!normalized) {
    localStorage.removeItem(API_BASE_KEY);
    return;
  }

  localStorage.setItem(API_BASE_KEY, normalized);
}

function apiUrl(path) {
  const base = coerceApiBaseForContext(apiBaseInput.value || getApiBase());
  if (!base) {
    return path;
  }

  return `${base}${path}`;
}

function applyBootstrapLink() {
  const hash = new URLSearchParams(window.location.hash.replace(/^#/, ""));
  const query = new URLSearchParams(window.location.search);
  const read = (key) => {
    const fromHash = hash.get(key);
    if (fromHash != null && fromHash !== "") {
      return fromHash;
    }
    const fromQuery = query.get(key);
    if (fromQuery != null && fromQuery !== "") {
      return fromQuery;
    }
    return "";
  };

  const token = read("token");
  const api = read("api");
  const target = read("target");
  const action = read("action");
  const arg = read("arg");
  const command = read("command");
  const updateTarget = read("update_target");
  const updateVersion = read("update_version");
  const updateUrl = read("update_url");
  const updateSha = read("update_sha");
  const updateSize = read("update_size");

  let applied = false;

  if (api) {
    setApiBase(api);
    applied = true;
  }

  if (token) {
    setToken(token);
    applied = true;
  }

  if (target) {
    localStorage.setItem(TARGET_KEY, target.trim().toLowerCase());
    applied = true;
  }

  if (updateTarget) {
    localStorage.setItem(UPDATE_TARGET_KEY, updateTarget.trim().toLowerCase());
    applied = true;
  } else if (target) {
    localStorage.setItem(UPDATE_TARGET_KEY, target.trim().toLowerCase());
  }

  if (updateVersion) {
    localStorage.setItem(UPDATE_VERSION_KEY, updateVersion.trim());
    applied = true;
  }

  if (updateUrl) {
    localStorage.setItem(UPDATE_URL_KEY, updateUrl.trim());
    applied = true;
  }

  if (updateSha) {
    localStorage.setItem(UPDATE_SHA_KEY, updateSha.trim().toLowerCase());
    applied = true;
  }

  if (updateSize) {
    localStorage.setItem(UPDATE_SIZE_KEY, updateSize.trim());
    applied = true;
  }

  if (command) {
    localStorage.setItem(BOOTSTRAP_COMMAND_KEY, command.trim().toLowerCase());
    applied = true;
  } else if (target && action) {
    const pairArg = arg ? ` ${arg.trim()}` : "";
    localStorage.setItem(BOOTSTRAP_COMMAND_KEY, `${target.trim().toLowerCase()} ${action.trim().toLowerCase()}${pairArg}`);
    applied = true;
  }

  if (action) {
    localStorage.setItem(BOOTSTRAP_ACTION_KEY, action.trim().toLowerCase());
    applied = true;
  }

  if (arg) {
    localStorage.setItem(BOOTSTRAP_ARG_KEY, arg.trim());
    applied = true;
  }

  if (applied) {
    const cleanPath = window.location.pathname;
    window.history.replaceState({}, document.title, cleanPath);
    setResult("Connection configured from pairing link. Fields were auto-filled.");
  }
}

function getToken() {
  return localStorage.getItem(TOKEN_KEY) || "";
}

function setToken(token) {
  localStorage.setItem(TOKEN_KEY, token);
}

function toLocalTimestamp(isoTime) {
  if (!isoTime) {
    return "never";
  }

  const date = new Date(isoTime);
  if (Number.isNaN(date.getTime())) {
    return "never";
  }

  return date.toLocaleString();
}

function setLastCommandSuccess(isoTime) {
  const value = isoTime || new Date().toISOString();
  localStorage.setItem(LAST_COMMAND_SUCCESS_KEY, value);
  lastSuccessLabel.textContent = `Last success: ${toLocalTimestamp(value)}`;
}

function loadLastCommandSuccess() {
  const value = localStorage.getItem(LAST_COMMAND_SUCCESS_KEY);
  lastSuccessLabel.textContent = `Last success: ${toLocalTimestamp(value)}`;
}

function setConnectionStatus(status) {
  connectionBadge.classList.remove("connected", "disconnected", "retrying");

  if (status === "connected") {
    connectionBadge.textContent = "Connected";
    connectionBadge.classList.add("connected");
    return;
  }

  if (status === "retrying") {
    connectionBadge.textContent = "Retrying";
    connectionBadge.classList.add("retrying");
    return;
  }

  connectionBadge.textContent = "Disconnected";
  connectionBadge.classList.add("disconnected");
}

function setAuthHint(text, isError = false) {
  authHint.textContent = text || "";
  authHint.style.color = isError ? "#ffb4b8" : "";
}

function setResult(payload, context = {}) {
  const isError = context.isError === true;
  let message = typeof payload === "string" ? payload : "";
  let requestId = context.requestId || "-";
  let statusLabel = isError ? "error" : "ok";
  let latencyLabel = context.latencyMs != null ? `${Math.round(context.latencyMs)} ms` : "-";

  if (typeof payload === "object" && payload) {
    const okValue = payload.ok;
    if (okValue === false) {
      statusLabel = "error";
    }
    if (okValue === true && !isError) {
      statusLabel = "ok";
    }

    if (!message) {
      message = payload.message || payload.error || payload.raw || JSON.stringify(payload);
    }

    if (!context.requestId) {
      requestId = payload.request_id || payload.requestId || "-";
    }
  }

  if (!message) {
    message = isError ? "Request failed." : "Done.";
  }

  resultStatus.textContent = statusLabel;
  resultStatus.className = `result-val ${statusLabel === "error" ? "error" : "ok"}`;
  resultRequestId.textContent = requestId;
  resultLatency.textContent = latencyLabel;
  resultMessage.textContent = message;
  resultBox.textContent = typeof payload === "string" ? payload : JSON.stringify(payload, null, 2);
}

function composeCommand() {
  const target = (targetInput.value || "").trim().toLowerCase();
  const action = (actionSelect.value || "").trim().toLowerCase();
  const arg = (argInput.value || "").trim();

  if (!target || !action) {
    return "";
  }

  if (action === "notify") {
    return arg ? `${target} notify ${arg}` : `${target} notify hello`;
  }

  if (arg && (action === "volume up" || action === "volume down" || action === "next" || action === "previous")) {
    return `${target} ${action} ${arg}`;
  }

  return `${target} ${action}`;
}

function updateDangerZone() {
  const action = (actionSelect.value || "").trim().toLowerCase();
  dangerZone.classList.toggle("hidden", !dangerousActions.has(action));
}

function parseApiErrorMessage(status, dataMessage) {
  if (status === 401 || status === 403) {
    return "Authentication failed. Check PHONE_API_TOKEN and save again.";
  }
  if (status === 404) {
    return "API endpoint not found. Verify API base URL.";
  }
  return dataMessage || `HTTP ${status}`;
}

async function apiRequest(path, payload, options = {}) {
  const token = getToken();
  if (!token) {
    setConnectionStatus("disconnected");
    throw new Error("Set your API token first.");
  }

  const endpoint = apiUrl(path);
  if (window.location.protocol === "https:" && endpoint.startsWith("http://")) {
    setConnectionStatus("disconnected");
    throw new Error("Mixed content blocked. Set API base URL to an HTTPS endpoint.");
  }

  const method = options.method || "POST";
  const start = performance.now();
  let response;
  try {
    response = await fetch(endpoint, {
      method,
      headers: {
        ...(payload ? { "Content-Type": "application/json" } : {}),
        Authorization: `Bearer ${token}`,
      },
      ...(payload ? { body: JSON.stringify(payload) } : {}),
    });
  } catch {
    setConnectionStatus("retrying");
    throw new Error("Cannot reach server. Connection is retrying.");
  }

  const latencyMs = performance.now() - start;
  const text = await response.text();
  let data;
  try {
    data = text ? JSON.parse(text) : { raw: text };
  } catch {
    data = { raw: text };
  }

  if (!response.ok) {
    const message = parseApiErrorMessage(response.status, data && data.message);
    if (response.status === 401 || response.status === 403) {
      setConnectionStatus("disconnected");
    } else {
      setConnectionStatus("retrying");
    }
    throw new ApiError(message, response.status);
  }

  setConnectionStatus("connected");
  return { data, latencyMs };
}

function setTarget(deviceId) {
  targetInput.value = deviceId;
  localStorage.setItem(TARGET_KEY, deviceId);
  commandText.value = composeCommand();
  if (updateTargetInput) {
    updateTargetInput.value = deviceId;
    localStorage.setItem(UPDATE_TARGET_KEY, deviceId);
  }
}

function renderDeviceCards(devices) {
  deviceCards.innerHTML = "";
  deviceList.innerHTML = "";

  if (devices.length === 0) {
    deviceSummary.textContent = "No enrolled devices";
    return;
  }

  const online = devices.filter((d) => (d.status || "").toLowerCase() === "online").length;
  deviceSummary.textContent = `${online}/${devices.length} online`;

  for (const device of devices) {
    const deviceId = String(device.device_id || "").trim();
    const status = String(device.status || "unknown").trim().toLowerCase();

    const card = document.createElement("article");
    card.className = "device-card";
    const heading = document.createElement("h3");
    heading.textContent = deviceId || "unknown-device";

    const meta = document.createElement("div");
    meta.className = "meta";

    const statusPill = document.createElement("span");
    statusPill.className = `device-status ${status === "online" ? "online" : "offline"}`;
    statusPill.textContent = status;

    const seen = document.createElement("span");
    seen.textContent = device.last_seen ? toLocalTimestamp(device.last_seen) : "no heartbeat";

    meta.appendChild(statusPill);
    meta.appendChild(seen);
    card.appendChild(heading);
    card.appendChild(meta);

    const useButton = document.createElement("button");
    useButton.type = "button";
    useButton.textContent = "Use Device";
    useButton.addEventListener("click", () => {
      if (!deviceId) {
        return;
      }
      setTarget(deviceId.toLowerCase());
      setResult(`Target set to ${deviceId}.`);
    });
    card.appendChild(useButton);
    deviceCards.appendChild(card);

    const li = document.createElement("li");
    li.textContent = `${deviceId} - ${status}`;
    deviceList.appendChild(li);
  }
}

async function loadDevices(options = {}) {
  const { data } = await apiRequest("/api/devices", null, { method: "GET" });
  if (!data.ok) {
    throw new Error(data.message || "Failed to load devices.");
  }

  renderDeviceCards(data.devices || []);
  if (!options.silent) {
    setResult("Devices loaded.");
  }
}

async function sendCommand() {
  const text = (commandText.value || "").trim();
  if (!text) {
    throw new Error("Command text is empty.");
  }

  const requestId = nowRequestId();
  const payload = {
    request_id: requestId,
    text,
    source: "pwa",
    sent_at: new Date().toISOString(),
    client_version: "pwa-v1",
  };

  const { data, latencyMs } = await apiRequest("/api/command", payload);
  setLastCommandSuccess();
  setResult(data, { requestId, latencyMs });
}

async function pushUpdate() {
  if (!updateTargetInput || !updateVersionInput || !updateUrlInput || !updateShaInput || !updateSizeInput) {
    throw new Error("Update controls are not available in this app build.");
  }

  const target = (updateTargetInput.value || "").trim().toLowerCase();
  const version = (updateVersionInput.value || "").trim();
  const packageUrl = (updateUrlInput.value || "").trim();
  const sha256 = (updateShaInput.value || "").trim().toLowerCase();
  const sizeRaw = (updateSizeInput.value || "").trim();

  if (!target) {
    throw new Error("Update target is required.");
  }

  if (!version) {
    throw new Error("Update version is required.");
  }

  if (!packageUrl) {
    throw new Error("Update package URL is required.");
  }

  let sizeBytes;
  if (sizeRaw) {
    const parsedSize = Number.parseInt(sizeRaw, 10);
    if (!Number.isFinite(parsedSize) || parsedSize <= 0) {
      throw new Error("Update size must be a positive integer.");
    }
    sizeBytes = parsedSize;
  }

  const requestId = nowRequestId();
  const payload = {
    request_id: requestId,
    source: "pwa",
    target,
    version,
    package_url: packageUrl,
    ...(sha256 ? { sha256 } : {}),
    ...(sizeBytes ? { size_bytes: sizeBytes } : {}),
  };

  const { data, latencyMs } = await apiRequest("/api/update", payload);
  setResult(data, { requestId, latencyMs });
}

async function testToken() {
  try {
    setAuthHint("Testing token...");
    await loadDevices({ silent: true });
    setAuthHint("Token valid. Device list loaded.");
    setResult("Token test passed.");
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    setAuthHint(message, true);
    setResult(message, { isError: true });
  }
}

function schedulePolling() {
  if (pollTimer) {
    window.clearInterval(pollTimer);
    pollTimer = null;
  }

  if (!getToken()) {
    return;
  }

  pollTimer = window.setInterval(async () => {
    try {
      await loadDevices({ silent: true });
    } catch (error) {
      if (!(error instanceof ApiError) || (error.status !== 401 && error.status !== 403)) {
        setConnectionStatus("retrying");
      }
    }
  }, POLL_INTERVAL_MS);
}

function setupSpeech() {
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;

  if (!SpeechRecognition) {
    speechInfo.textContent = "Speech not supported in this browser. Use keyboard dictation.";
    speakBtn.disabled = true;
    return;
  }

  speechInfo.textContent = "Speech supported.";

  const recognition = new SpeechRecognition();
  recognition.lang = "en-US";
  recognition.interimResults = false;
  recognition.maxAlternatives = 1;

  recognition.onresult = (event) => {
    const transcript = event.results[0][0].transcript || "";
    commandText.value = transcript.trim().toLowerCase();
  };

  recognition.onerror = (event) => {
    setResult(`Speech error: ${event.error || "unknown"}`, { isError: true });
  };

  speakBtn.addEventListener("click", () => {
    recognition.start();
  });
}

function init() {
  applyBootstrapLink();
  apiBaseInput.value = getApiBase();
  setApiBase(apiBaseInput.value);
  apiBaseInput.value = getApiBase();
  tokenInput.value = getToken();
  loadLastCommandSuccess();
  setConnectionStatus(getToken() ? "retrying" : "disconnected");
  updateDangerZone();

  const lastTarget = localStorage.getItem(TARGET_KEY);
  if (lastTarget) {
    targetInput.value = lastTarget;
  }

  if (updateTargetInput && updateVersionInput && updateUrlInput && updateShaInput && updateSizeInput) {
    updateTargetInput.value = localStorage.getItem(UPDATE_TARGET_KEY) || targetInput.value || "m1";
    updateVersionInput.value = localStorage.getItem(UPDATE_VERSION_KEY) || "";
    updateUrlInput.value = localStorage.getItem(UPDATE_URL_KEY) || "";
    updateShaInput.value = localStorage.getItem(UPDATE_SHA_KEY) || "";
    updateSizeInput.value = localStorage.getItem(UPDATE_SIZE_KEY) || "";
  }

  const initialCommand = composeCommand();
  if (initialCommand) {
    commandText.value = initialCommand;
  }

  const bootstrapAction = localStorage.getItem(BOOTSTRAP_ACTION_KEY);
  if (bootstrapAction && actionSelect.querySelector(`option[value="${bootstrapAction}"]`)) {
    actionSelect.value = bootstrapAction;
    updateDangerZone();
  }

  const bootstrapArg = localStorage.getItem(BOOTSTRAP_ARG_KEY);
  if (bootstrapArg) {
    argInput.value = bootstrapArg;
  }

  const bootstrapCommand = localStorage.getItem(BOOTSTRAP_COMMAND_KEY);
  if (bootstrapCommand) {
    commandText.value = bootstrapCommand;
    localStorage.removeItem(BOOTSTRAP_COMMAND_KEY);
  } else {
    commandText.value = composeCommand();
  }
  localStorage.removeItem(BOOTSTRAP_ACTION_KEY);
  localStorage.removeItem(BOOTSTRAP_ARG_KEY);

  actionSelect.addEventListener("change", () => {
    updateDangerZone();
    commandText.value = composeCommand();
  });

  targetInput.addEventListener("change", () => {
    localStorage.setItem(TARGET_KEY, targetInput.value.trim().toLowerCase());
    if (updateTargetInput && !localStorage.getItem(UPDATE_TARGET_KEY) && updateTargetInput.value.trim() === "") {
      updateTargetInput.value = targetInput.value.trim().toLowerCase();
    }
    commandText.value = composeCommand();
  });

  argInput.addEventListener("change", () => {
    commandText.value = composeCommand();
  });

  composeBtn.addEventListener("click", () => {
    commandText.value = composeCommand();
  });

  saveTokenBtn.addEventListener("click", () => {
    const token = tokenInput.value.trim();
    const apiBase = apiBaseInput.value.trim();

    if (!token) {
      setAuthHint("Token is empty.", true);
      setResult("Token is empty.", { isError: true });
      setConnectionStatus("disconnected");
      return;
    }

    setToken(token);
    setApiBase(apiBase);
    apiBaseInput.value = getApiBase();
    setAuthHint("Connection settings saved.");
    setResult("Connection settings saved on this device.");
    schedulePolling();
  });

  if (testTokenBtn) {
    testTokenBtn.addEventListener("click", async () => {
      await testToken();
    });
  }

  if (updateTargetInput && updateVersionInput && updateUrlInput && updateShaInput && updateSizeInput) {
    updateTargetInput.addEventListener("change", () => {
      localStorage.setItem(UPDATE_TARGET_KEY, updateTargetInput.value.trim().toLowerCase());
    });
    updateVersionInput.addEventListener("change", () => {
      localStorage.setItem(UPDATE_VERSION_KEY, updateVersionInput.value.trim());
    });
    updateUrlInput.addEventListener("change", () => {
      localStorage.setItem(UPDATE_URL_KEY, updateUrlInput.value.trim());
    });
    updateShaInput.addEventListener("change", () => {
      localStorage.setItem(UPDATE_SHA_KEY, updateShaInput.value.trim().toLowerCase());
    });
    updateSizeInput.addEventListener("change", () => {
      localStorage.setItem(UPDATE_SIZE_KEY, updateSizeInput.value.trim());
    });
  }

  loadDevicesBtn.addEventListener("click", async () => {
    try {
      await loadDevices();
      setAuthHint("Device list refreshed.");
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setAuthHint(message, true);
      setResult(message, { isError: true });
    }
  });

  sendBtn.addEventListener("click", async () => {
    try {
      sendBtn.disabled = true;
      sendBtn.textContent = "Sending...";
      await sendCommand();
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setAuthHint(message, true);
      setResult(message, { isError: true });
    } finally {
      sendBtn.disabled = false;
      sendBtn.textContent = "Send";
    }
  });

  if (pushUpdateBtn) {
    pushUpdateBtn.addEventListener("click", async () => {
      try {
        pushUpdateBtn.disabled = true;
        pushUpdateBtn.textContent = "Pushing...";
        await pushUpdate();
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        setAuthHint(message, true);
        setResult(message, { isError: true });
      } finally {
        pushUpdateBtn.disabled = false;
        pushUpdateBtn.textContent = "Push Update";
      }
    });
  }

  setupSpeech();
  schedulePolling();

  if ("serviceWorker" in navigator) {
    navigator.serviceWorker
      .register("sw.js", { updateViaCache: "none" })
      .then((registration) => {
        registration.update().catch(() => {
          // Ignore update errors.
        });
      })
      .catch(() => {
        // Ignore service worker errors.
      });
  }

  if (getToken()) {
    loadDevices({ silent: true })
      .then(() => {
        if (!resultBox.textContent || resultBox.textContent === "No request yet.") {
          setResult("Devices loaded.");
        }
      })
      .catch((error) => {
        const message = error instanceof Error ? error.message : String(error);
        setAuthHint(message, true);
        setResult(message, { isError: true });
      });
  }
}

init();
