// Shared fetch wrapper + toast helper for the admin dashboard pages.
// Same-origin API calls only (this app is local-network only).

const API_BASE = "";
const AUTH_STORAGE_KEY = "canteen_auth";

function getAuth() {
  try {
    return JSON.parse(localStorage.getItem(AUTH_STORAGE_KEY) || "null");
  } catch (_) {
    return null;
  }
}

function setAuth(auth) {
  localStorage.setItem(AUTH_STORAGE_KEY, JSON.stringify(auth));
}

function clearAuth() {
  localStorage.removeItem(AUTH_STORAGE_KEY);
}

// Every admin page (except login.html) calls this immediately — no token,
// no page. Kept out of api.js's own request logic so a 401 *during* a call
// (an expired session mid-session) can redirect the same way.
function requireAuthOrRedirect() {
  const auth = getAuth();
  if (!auth || !auth.token) {
    window.location.href = "login.html";
    return null;
  }
  return auth;
}

async function apiRequest(path, options = {}) {
  const auth = getAuth();
  const headers = { "Content-Type": "application/json" };
  if (auth && auth.token) headers["Authorization"] = `Bearer ${auth.token}`;

  const res = await fetch(`${API_BASE}${path}`, { headers, ...options });

  if (res.status === 401) {
    clearAuth();
    window.location.href = "login.html";
    // Never resolves — the redirect above is already underway, and nothing
    // waiting on this call should try to render with no session.
    return new Promise(() => {});
  }

  if (!res.ok) {
    let detail = `Request failed (${res.status})`;
    try {
      const body = await res.json();
      detail = body.detail || detail;
    } catch (_) {
      // response wasn't JSON — keep the generic status message
    }
    throw new Error(detail);
  }

  const contentType = res.headers.get("content-type") || "";
  return contentType.includes("application/json") ? res.json() : res;
}

const api = {
  get: (path) => apiRequest(path),
  post: (path, body) => apiRequest(path, { method: "POST", body: JSON.stringify(body) }),
  patch: (path, body) => apiRequest(path, { method: "PATCH", body: JSON.stringify(body) }),
  delete: (path) => apiRequest(path, { method: "DELETE" }),
};

function showToast(message, isError = false) {
  const existing = document.querySelector(".toast");
  if (existing) existing.remove();

  const toast = document.createElement("div");
  toast.className = isError ? "toast error" : "toast";
  toast.textContent = message;
  toast.setAttribute("role", "status");
  toast.setAttribute("aria-live", "polite");
  document.body.appendChild(toast);
  setTimeout(() => toast.remove(), 4000);
}

function formatDate(isoString) {
  if (!isoString) return "—";
  const d = new Date(isoString);
  return d.toLocaleString(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  });
}

function escapeHtml(value) {
  const div = document.createElement("div");
  div.textContent = value ?? "";
  return div.innerHTML;
}
