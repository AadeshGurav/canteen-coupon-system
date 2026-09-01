// Top-up creation and recent top-up/billing history for the admin dashboard.
// The amount is never typed in — it's computed live from the unit prices
// set on the Settings page, the same computation the server repeats
// authoritatively when the form is actually submitted.

let membersById = {};
let unitPrices = { lunch: 0, breakfast: 0, brunch: 0 };

const lunchInput = document.getElementById("topup-lunch");
const breakfastInput = document.getElementById("topup-breakfast");
const brunchInput = document.getElementById("topup-brunch");
const amountPreview = document.getElementById("topup-amount-preview");
const submitBtn = document.getElementById("topup-submit");

function currentUnits() {
  return {
    lunch: Number(lunchInput.value) || 0,
    breakfast: Number(breakfastInput.value) || 0,
    brunch: Number(brunchInput.value) || 0,
  };
}

function updateAmountPreview() {
  const units = currentUnits();
  const amount = units.lunch * unitPrices.lunch + units.breakfast * unitPrices.breakfast + units.brunch * unitPrices.brunch;
  amountPreview.textContent = `₹${amount.toFixed(2)}`;

  // A top-up that credits nothing is never valid — disable rather than let
  // the admin discover that only after submitting (Nielsen #5: error prevention).
  const hasUnits = units.lunch > 0 || units.breakfast > 0 || units.brunch > 0;
  submitBtn.disabled = !hasUnits;
  submitBtn.title = hasUnits ? "" : "Add at least one unit before recording a top-up.";
}

[lunchInput, breakfastInput, brunchInput].forEach((input) => input.addEventListener("input", updateAmountPreview));

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
  const statusBadge =
    t.payment_status === "confirmed"
      ? '<span class="badge badge-success">Confirmed</span>'
      : '<span class="badge badge-warning">Pending</span>';

  const confirmBtn =
    t.payment_status === "pending"
      ? `<button class="secondary btn-confirm" data-id="${t._id}">Confirm payment</button>`
      : "";
  const qrBtn = t.upi_qr_path
    ? `<button class="secondary btn-show-qr" data-id="${t._id}" data-amount="${t.amount}">Show QR</button>`
    : "";
  const billBtn = t.bill_pdf_path ? `<a class="btn secondary" href="/topups/${t._id}/bill" target="_blank">Bill</a>` : "";

  return `
    <tr>
      <td>${formatDate(t.created_at)}</td>
      <td>${memberLabel}</td>
      <td>${units}</td>
      <td>₹${t.amount.toFixed(2)}</td>
      <td>${t.payment_method.toUpperCase()}</td>
      <td>${statusBadge}</td>
      <td class="actions">${confirmBtn}${qrBtn}${billBtn}</td>
    </tr>`;
}

document.getElementById("topups-body").addEventListener("click", async (e) => {
  if (e.target.classList.contains("btn-confirm")) {
    try {
      await api.post(`/topups/${e.target.dataset.id}/confirm-payment`, {});
      showToast("Payment confirmed.");
      loadTopups();
    } catch (err) {
      showToast(err.message, true);
    }
  } else if (e.target.classList.contains("btn-show-qr")) {
    await showUpiQr(e.target.dataset.id, e.target.dataset.amount);
  }
});

// The bill PDF never embeds the UPI QR (it's shown here, at the moment of
// payment, instead — a bill is a lasting record and outlives that moment).
const qrDialog = document.getElementById("upi-qr-dialog");
const qrImage = document.getElementById("upi-qr-image");

async function showUpiQr(topupId, amount) {
  try {
    const auth = getAuth();
    const res = await fetch(`/topups/${topupId}/upi-qr`, { headers: { Authorization: `Bearer ${auth.token}` } });
    if (!res.ok) throw new Error("Could not load the UPI QR for this top-up.");
    const blob = await res.blob();
    qrImage.src = URL.createObjectURL(blob);
    document.getElementById("upi-qr-amount").textContent = `Amount: ₹${Number(amount).toFixed(2)}`;
    qrDialog.showModal();
  } catch (err) {
    showToast(err.message, true);
  }
}

document.getElementById("btn-close-qr").addEventListener("click", () => qrDialog.close());

document.getElementById("topup-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const memberId = document.getElementById("topup-member").value;
  if (!memberId) {
    showToast("Choose a member first.", true);
    return;
  }

  const units = currentUnits();
  const paymentMethod = document.getElementById("topup-method").value;

  try {
    const topup = await api.post("/topups", {
      member_id: memberId,
      lunch_units: units.lunch,
      breakfast_units: units.breakfast,
      brunch_units: units.brunch,
      payment_method: paymentMethod,
      created_by: document.getElementById("topup-created-by").value,
    });
    showToast("Top-up recorded and bill generated.");
    e.target.reset();
    updateAmountPreview();
    loadTopups();

    if (paymentMethod === "upi" && topup.upi_qr_path) {
      await showUpiQr(topup._id, topup.amount);
    }
  } catch (err) {
    showToast(err.message, true);
  }
});

(async function init() {
  const auth = getAuth();
  document.getElementById("topup-created-by").value = auth?.username || "";

  try {
    const settings = await api.get("/settings");
    unitPrices = settings.unit_prices;
  } catch (_) {
    // A transient error here just means the preview stays ₹0.00 until the
    // server computes the real (authoritative) amount on submit.
  }
  updateAmountPreview();

  await loadMemberOptions();
  await loadTopups();
})();
