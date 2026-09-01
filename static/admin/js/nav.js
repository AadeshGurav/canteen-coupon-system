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
    <span class="nav-user">
      <span class="nav-role-badge">${escapeHtml(auth.role)}</span>
      ${escapeHtml(auth.username)}
      <button type="button" class="secondary" id="nav-logout" style="min-height:36px;padding:6px 14px">Log out</button>
    </span>
  `;

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

document.addEventListener("DOMContentLoaded", renderNav);
