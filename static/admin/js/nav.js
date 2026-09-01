// Renders the shared admin nav bar into #admin-nav on every page, marking the
// current page so it doesn't have to be duplicated (and kept in sync) per file.

const NAV_LINKS = [
  { href: "index.html", label: "Dashboard" },
  { href: "members.html", label: "Members" },
  { href: "topups.html", label: "Top-ups & Billing" },
  { href: "scan-log.html", label: "Scan Log" },
  { href: "menu.html", label: "Menu Planning" },
  { href: "expenses.html", label: "Expenses" },
  { href: "refunds.html", label: "Refunds" },
  { href: "settings.html", label: "Settings" },
];

function renderNav() {
  const nav = document.getElementById("admin-nav");
  if (!nav) return;

  const currentPage = window.location.pathname.split("/").pop() || "index.html";
  const linksHtml = NAV_LINKS.map((link) => {
    const isCurrent = link.href === currentPage;
    return `<a href="${link.href}"${isCurrent ? ' aria-current="page"' : ""}>${link.label}</a>`;
  }).join("");

  nav.innerHTML = `<span class="brand">Canteen Admin</span>${linksHtml}`;
}

document.addEventListener("DOMContentLoaded", renderNav);
