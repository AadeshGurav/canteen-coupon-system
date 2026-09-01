// Shared fetch wrapper + toast helper for the admin dashboard pages.
// Same-origin API calls only (this app is local-network only, no auth yet —
// see docs/PRD.md §9, admin auth is explicitly deferred pre-handoff).

const API_BASE = "";

async function apiRequest(path, options = {}) {
  const res = await fetch(`${API_BASE}${path}`, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });

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
