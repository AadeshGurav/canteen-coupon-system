// Top-up creation and recent top-up/billing history for the admin dashboard.

let membersById = {};

async function loadMemberOptions() {
  const select = document.getElementById("topup-member");
  try {
    const members = await api.get("/members?status=active");
    membersById = Object.fromEntries(members.map((m) => [m._id, m]));
    select.innerHTML = members
      .map((m) => `<option value="${m._id}">${escapeHtml(m.name)} (${m.type})</option>`)
      .join("");
  } catch (err) {
    select.innerHTML = `<option value="">Could not load members</option>`;
    showToast(err.message, true);
  }
}

async function loadTopups() {
  const body = document.getElementById("topups-body");
  try {
    const rows = await api.get("/topups");
    if (rows.length === 0) {
      body.innerHTML = `<tr><td colspan="7" class="empty-state">No top-ups recorded yet.</td></tr>`;
      return;
    }
    body.innerHTML = rows.map(renderTopupRow).join("");
  } catch (err) {
    body.innerHTML = `<tr><td colspan="7" class="empty-state">Could not load top-ups: ${escapeHtml(err.message)}</td></tr>`;
  }
}

function renderTopupRow(t) {
  const member = membersById[t.member_id];
  const memberLabel = member ? escapeHtml(member.name) : t.member_id;
  const units = `${t.lunch_units}/${t.breakfast_units}/${t.brunch_units}`;
  const statusBadge = t.payment_status === "confirmed"
    ? '<span class="badge badge-success">Confirmed</span>'
    : '<span class="badge badge-warning">Pending</span>';

  const confirmBtn = t.payment_status === "pending"
    ? `<button class="secondary btn-confirm" data-id="${t._id}">Confirm payment</button>`
    : "";
  const billBtn = t.bill_pdf_path
    ? `<a class="btn secondary" href="/topups/${t._id}/bill" target="_blank">Bill</a>`
    : "";

  return `
    <tr>
      <td>${formatDate(t.created_at)}</td>
      <td>${memberLabel}</td>
      <td>${units}</td>
      <td>₹${t.amount.toFixed(2)}</td>
      <td>${t.payment_method.toUpperCase()}</td>
      <td>${statusBadge}</td>
      <td class="actions">${confirmBtn}${billBtn}</td>
    </tr>`;
}

document.getElementById("topups-body").addEventListener("click", async (e) => {
  if (!e.target.classList.contains("btn-confirm")) return;
  const id = e.target.dataset.id;
  try {
    await api.post(`/topups/${id}/confirm-payment`, {});
    showToast("Payment confirmed.");
    loadTopups();
  } catch (err) {
    showToast(err.message, true);
  }
});

document.getElementById("topup-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const memberId = document.getElementById("topup-member").value;
  if (!memberId) {
    showToast("Choose a member first.", true);
    return;
  }

  try {
    await api.post("/topups", {
      member_id: memberId,
      lunch_units: Number(document.getElementById("topup-lunch").value) || 0,
      breakfast_units: Number(document.getElementById("topup-breakfast").value) || 0,
      brunch_units: Number(document.getElementById("topup-brunch").value) || 0,
      amount: Number(document.getElementById("topup-amount").value),
      payment_method: document.getElementById("topup-method").value,
      created_by: document.getElementById("topup-created-by").value,
    });
    showToast("Top-up recorded and bill generated.");
    e.target.reset();
    loadTopups();
  } catch (err) {
    showToast(err.message, true);
  }
});

(async function init() {
  await loadMemberOptions();
  await loadTopups();
})();
