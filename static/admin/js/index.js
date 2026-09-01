// Dashboard home: at-a-glance stats, quick links, and recent scan activity.
// Some of this (expense summary, scan history) is admin-only — a counter
// user sees the rest of the page fine, just without those two sections,
// rather than the whole dashboard failing on one 403.

const auth = getAuth();

function renderQuickLinks() {
  const container = document.getElementById("quick-links");
  const linkStyles = { "index.html": null }; // skip linking to the page we're already on
  const items = NAV_LINKS.filter((l) => l.roles.includes(auth.role) && l.href !== "index.html");
  container.innerHTML = items
    .map((l, i) => `<a class="btn${i === 0 ? "" : " secondary"}" href="${l.href}">${l.label}</a>`)
    .join("");
}

function monthStartIso() {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), 1).toISOString().slice(0, 10);
}

async function loadStats() {
  try {
    const members = await api.get("/members?status=active");
    document.getElementById("stat-members").textContent = members.length;
  } catch (err) {
    document.getElementById("stat-members").textContent = "—";
  }

  try {
    const topups = await api.get("/topups");
    document.getElementById("stat-pending").textContent = topups.filter((t) => t.payment_status === "pending").length;
  } catch (err) {
    document.getElementById("stat-pending").textContent = "—";
  }

  try {
    const summary = await api.get(`/expenses/summary?start=${monthStartIso()}`);
    document.getElementById("stat-revenue").textContent = `₹${summary.revenue.toFixed(2)}`;
    document.getElementById("stat-profit").textContent = `₹${summary.profit.toFixed(2)}`;
  } catch (err) {
    // admin-only — hide rather than show a broken/blank stat to a counter user
    document.getElementById("stat-revenue-card").style.display = "none";
    document.getElementById("stat-profit-card").style.display = "none";
  }
}

async function loadRecentScans() {
  const card = document.getElementById("recent-activity-card");
  const body = document.getElementById("recent-scans-body");
  try {
    const [scans, members] = await Promise.all([api.get("/scan?limit=25"), api.get("/members")]);
    const membersById = Object.fromEntries(members.map((m) => [m._id, m]));

    if (scans.length === 0) {
      body.innerHTML = `<tr><td colspan="4" class="empty-state">No scans yet.</td></tr>`;
      return;
    }

    body.innerHTML = scans
      .map((s) => {
        const member = membersById[s.member_id];
        const memberLabel = member ? escapeHtml(member.name) : s.member_id;
        const resultBadge = s.reversed
          ? '<span class="badge badge-neutral">Reversed</span>'
          : s.via_grace
            ? '<span class="badge badge-warning">Accepted (grace)</span>'
            : '<span class="badge badge-success">Accepted</span>';
        return `<tr><td>${formatDate(s.scanned_at)}</td><td>${memberLabel}</td><td>${s.meal_type}</td><td>${resultBadge}</td></tr>`;
      })
      .join("");
  } catch (err) {
    // admin-only (GET /scan) — hide the whole section for a counter user
    // rather than show an error for something they were never meant to see.
    card.style.display = "none";
  }
}

renderQuickLinks();
loadStats();
loadRecentScans();
