// Dashboard home: at-a-glance stats and recent scan activity.

function monthStartIso() {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), 1).toISOString().slice(0, 10);
}

async function loadStats() {
  try {
    const [members, topups, summary] = await Promise.all([
      api.get("/members?status=active"),
      api.get("/topups"),
      api.get(`/expenses/summary?start=${monthStartIso()}`),
    ]);

    document.getElementById("stat-members").textContent = members.length;
    document.getElementById("stat-pending").textContent = topups.filter((t) => t.payment_status === "pending").length;
    document.getElementById("stat-revenue").textContent = `₹${summary.revenue.toFixed(2)}`;
    document.getElementById("stat-profit").textContent = `₹${summary.profit.toFixed(2)}`;
  } catch (err) {
    showToast(`Could not load dashboard stats: ${err.message}`, true);
  }
}

async function loadRecentScans() {
  const body = document.getElementById("recent-scans-body");
  try {
    const [scans, members] = await Promise.all([api.get("/scan?limit=25"), api.get("/members")]);
    const membersById = Object.fromEntries(members.map((m) => [m._id, m]));

    if (scans.length === 0) {
      body.innerHTML = `<tr><td colspan="4" class="empty-state">No scans yet.</td></tr>`;
      return;
    }

    body.innerHTML = scans.map((s) => {
      const member = membersById[s.member_id];
      const memberLabel = member ? escapeHtml(member.name) : s.member_id;
      const resultBadge = s.reversed
        ? '<span class="badge badge-neutral">Reversed</span>'
        : s.via_grace
          ? '<span class="badge badge-warning">Accepted (grace)</span>'
          : '<span class="badge badge-success">Accepted</span>';
      return `<tr><td>${formatDate(s.scanned_at)}</td><td>${memberLabel}</td><td>${s.meal_type}</td><td>${resultBadge}</td></tr>`;
    }).join("");
  } catch (err) {
    body.innerHTML = `<tr><td colspan="4" class="empty-state">Could not load recent scans: ${escapeHtml(err.message)}</td></tr>`;
  }
}

loadStats();
loadRecentScans();
