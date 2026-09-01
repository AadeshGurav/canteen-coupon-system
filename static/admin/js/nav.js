// Renders the shared admin nav bar into #admin-nav on every page — current
// page highlighted, links filtered to what the logged-in role can actually
// use, user/role + logout on the right, and the brand name kept in sync
// with the admin-editable app_name setting.

const NAV_LINKS = [
  { href: "index.html", label: "Dashboard", roles: ["admin", "counter"] },
  { href: "members.html", label: "Members", roles: ["admin", "counter"] },
  { href: "topups.html", label: "Top-ups & Billing", roles: ["admin", "counter"] },
  { href: "scan-log.html", label: "Scan Log", roles: ["admin"] },
  { href: "menu.html", label: "Menu Planning", roles: ["admin"] },
  { href: "ingredients.html", label: "Ingredients & Purchasing", roles: ["admin", "counter"] },
  { href: "expenses.html", label: "Expenses", roles: ["admin"] },
  { href: "refunds.html", label: "Refunds", roles: ["admin"] },
  { href: "settings.html", label: "Settings", roles: ["admin"] },
  { href: "users.html", label: "Users", roles: ["admin"] },
];

async function renderNav() {
  const nav = document.getElementById("admin-nav");
  if (!nav) return;

  const auth = requireAuthOrRedirect();
  if (!auth) return; // already redirecting to login

  const currentPage = window.location.pathname.split("/").pop() || "index.html";
  const visibleLinks = NAV_LINKS.filter((link) => link.roles.includes(auth.role));

  const linksHtml = visibleLinks
    .map((link) => {
      const isCurrent = link.href === currentPage;
      return `<a class="nav-link" href="${link.href}"${isCurrent ? ' aria-current="page"' : ""}>${link.label}</a>`;
    })
    .join("");

  nav.innerHTML = `
    <span class="brand" id="nav-brand">Canteen Admin</span>
    ${linksHtml}
    <span class="nav-spacer"></span>
    <span class="notif-bell-wrap">
      <button type="button" class="notif-bell" id="notif-bell" aria-label="Notifications" aria-haspopup="true">🔔</button>
      <div class="notif-dropdown" id="notif-dropdown" hidden></div>
    </span>
    <span class="nav-user">
      <span class="nav-role-badge">${escapeHtml(auth.role)}</span>
      ${escapeHtml(auth.username)}
      <button type="button" class="secondary" id="nav-logout" style="min-height:36px;padding:6px 14px">Log out</button>
    </span>
  `;

  initNotifications();

  document.getElementById("nav-logout").addEventListener("click", async () => {
    try {
      await api.post("/auth/logout", {});
    } catch (_) {
      // session may already be gone server-side — log out locally regardless
    }
    clearAuth();
    window.location.href = "login.html";
  });

  // Best-effort branding sync — a fetch failure here shouldn't block the
  // page just to rename the nav bar.
  try {
    const settings = await api.get("/settings");
    const appName = settings.app_name || "Canteen Admin";
    document.getElementById("nav-brand").textContent = appName;
    const pageLabel = visibleLinks.find((l) => l.href === currentPage)?.label;
    document.title = pageLabel ? `${pageLabel} — ${appName}` : appName;
  } catch (_) {
    // keep the default brand text
  }
}

// --- Notification bell: persistent, in-app reminders (prep/purchase due) ---
// Polled rather than pushed — no new server infrastructure (websockets,
// SSE) for what's a low-frequency, non-urgent reminder feed (CLAUDE.md §10).

const NOTIF_POLL_INTERVAL_MS = 45000;

function renderNotifDropdown(items) {
  const dropdown = document.getElementById("notif-dropdown");
  if (!dropdown) return;

  if (items.length === 0) {
    dropdown.innerHTML = '<div class="notif-empty">Nothing to see here.</div>';
    return;
  }

  dropdown.innerHTML = items
    .map(
      (n) => `
    <div class="notif-item" data-id="${n._id}">
      <div>
        <div class="notif-item-title">${escapeHtml(n.title)}</div>
        <div class="notif-item-message">${escapeHtml(n.message)}</div>
      </div>
      <button type="button" class="notif-dismiss" data-id="${n._id}" aria-label="Dismiss">×</button>
    </div>`
    )
    .join("");
}

async function pollNotifications() {
  const bell = document.getElementById("notif-bell");
  if (!bell) return;
  try {
    const items = await api.get("/notifications");
    let badge = bell.querySelector(".notif-badge");
    if (items.length > 0) {
      if (!badge) {
        badge = document.createElement("span");
        badge.className = "notif-badge";
        bell.appendChild(badge);
      }
      badge.textContent = items.length > 9 ? "9+" : String(items.length);
    } else if (badge) {
      badge.remove();
    }
    renderNotifDropdown(items);
  } catch (_) {
    // a failed poll shouldn't be visible — just try again next interval
  }
}

function initNotifications() {
  const bell = document.getElementById("notif-bell");
  const dropdown = document.getElementById("notif-dropdown");
  if (!bell || !dropdown) return;

  bell.addEventListener("click", (e) => {
    e.stopPropagation();
    dropdown.hidden = !dropdown.hidden;
  });
  document.addEventListener("click", (e) => {
    if (!dropdown.hidden && !dropdown.contains(e.target) && e.target !== bell) {
      dropdown.hidden = true;
    }
  });
  dropdown.addEventListener("click", async (e) => {
    if (!e.target.classList.contains("notif-dismiss")) return;
    try {
      await api.post(`/notifications/${e.target.dataset.id}/dismiss`, {});
      pollNotifications();
    } catch (_) {
      // leave it visible — the user can try dismissing again
    }
  });

  pollNotifications();
  setInterval(pollNotifications, NOTIF_POLL_INTERVAL_MS);
}

document.addEventListener("DOMContentLoaded", renderNav);
