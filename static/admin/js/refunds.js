// Refund recording for the admin dashboard.

let membersById = {};

async function loadMemberOptions() {
  const select = document.getElementById("refund-member");
  try {
    const members = await api.get("/members");
    membersById = Object.fromEntries(members.map((m) => [m._id, m]));
    select.innerHTML = members
      .map((m) => `<option value="${m._id}">${escapeHtml(m.name)} (${m.type}) — L:${m.balances.lunch} B:${m.balances.breakfast} Br:${m.balances.brunch}</option>`)
      .join("");
  } catch (err) {
    select.innerHTML = `<option value="">Could not load members</option>`;
    showToast(err.message, true);
  }
}

async function loadRefunds() {
  const body = document.getElementById("refunds-body");
  try {
    const refunds = await api.get("/refunds");
    if (refunds.length === 0) {
      body.innerHTML = `<tr><td colspan="5" class="empty-state">No refunds recorded yet.</td></tr>`;
      return;
    }
    body.innerHTML = refunds.map((r) => {
      const member = membersById[r.member_id];
      const memberLabel = member ? escapeHtml(member.name) : r.member_id;
      return `
        <tr>
          <td>${formatDate(r.created_at)}</td>
          <td>${memberLabel}</td>
          <td>${r.lunch_units}/${r.breakfast_units}/${r.brunch_units}</td>
          <td>₹${r.refund_amount.toFixed(2)}</td>
          <td>${escapeHtml(r.reason || "—")}</td>
        </tr>`;
    }).join("");
  } catch (err) {
    body.innerHTML = `<tr><td colspan="5" class="empty-state">Could not load refunds: ${escapeHtml(err.message)}</td></tr>`;
  }
}

document.getElementById("refund-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const memberId = document.getElementById("refund-member").value;
  if (!memberId) {
    showToast("Choose a member first.", true);
    return;
  }

  try {
    await api.post("/refunds", {
      member_id: memberId,
      lunch_units: Number(document.getElementById("refund-lunch").value) || 0,
      breakfast_units: Number(document.getElementById("refund-breakfast").value) || 0,
      brunch_units: Number(document.getElementById("refund-brunch").value) || 0,
      refund_amount: Number(document.getElementById("refund-amount").value),
      reason: document.getElementById("refund-reason").value || null,
      processed_by: document.getElementById("refund-processed-by").value,
    });
    showToast("Refund recorded.");
    e.target.reset();
    await loadMemberOptions();
    loadRefunds();
  } catch (err) {
    showToast(err.message, true);
  }
});

(async function init() {
  await loadMemberOptions();
  await loadRefunds();
})();
