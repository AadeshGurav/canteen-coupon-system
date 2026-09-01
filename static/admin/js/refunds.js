// Refund recording for the admin dashboard. Unit inputs pre-fill with the
// selected member's actual current balance (capped there via `max`, so a
// mistyped refund larger than what they have is caught before submit, not
// after) and the amount is computed from unit prices, never typed by hand.

let membersById = {};
let unitPrices = { lunch: 0, breakfast: 0, brunch: 0 };

const memberSelect = document.getElementById("refund-member");
const lunchInput = document.getElementById("refund-lunch");
const breakfastInput = document.getElementById("refund-breakfast");
const brunchInput = document.getElementById("refund-brunch");
const amountPreview = document.getElementById("refund-amount-preview");
const balanceHint = document.getElementById("refund-balance-hint");
const submitBtn = document.getElementById("refund-submit");

function currentUnits() {
  return {
    lunch: Number(lunchInput.value) || 0,
    breakfast: Number(breakfastInput.value) || 0,
    brunch: Number(brunchInput.value) || 0,
  };
}

function updateAmountPreview() {
  const units = currentUnits();
  const amount =
    units.lunch * unitPrices.lunch + units.breakfast * unitPrices.breakfast + units.brunch * unitPrices.brunch;
  amountPreview.textContent = `₹${amount.toFixed(2)}`;

  const hasUnits = units.lunch > 0 || units.breakfast > 0 || units.brunch > 0;
  submitBtn.disabled = !hasUnits;
  submitBtn.title = hasUnits ? "" : "Add at least one unit before recording a refund.";
}

function applyMemberBalance(member) {
  const b = member.balances;
  for (const [input, meal] of [
    [lunchInput, "lunch"],
    [breakfastInput, "breakfast"],
    [brunchInput, "brunch"],
  ]) {
    const balance = Math.max(0, b[meal]); // a negative (grace) balance has nothing left to refund
    input.max = balance;
    input.value = balance;
  }
  balanceHint.textContent = `${member.name}'s current balance: L:${b.lunch} B:${b.breakfast} Br:${b.brunch}`;
  updateAmountPreview();
}

memberSelect.addEventListener("change", () => {
  const member = membersById[memberSelect.value];
  if (member) applyMemberBalance(member);
});

[lunchInput, breakfastInput, brunchInput].forEach((input) => input.addEventListener("input", updateAmountPreview));

async function loadMemberOptions() {
  try {
    const members = await api.get("/members");
    membersById = Object.fromEntries(members.map((m) => [m._id, m]));
    memberSelect.innerHTML = members
      .map((m) => `<option value="${m._id}">${escapeHtml(m.name)} (${m.type})</option>`)
      .join("");
    if (members.length > 0) applyMemberBalance(members[0]);
  } catch (err) {
    memberSelect.innerHTML = `<option value="">Could not load members</option>`;
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
    body.innerHTML = refunds
      .map((r) => {
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
      })
      .join("");
  } catch (err) {
    body.innerHTML = `<tr><td colspan="5" class="empty-state">Could not load refunds: ${escapeHtml(err.message)}</td></tr>`;
  }
}

document.getElementById("refund-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const memberId = memberSelect.value;
  if (!memberId) {
    showToast("Choose a member first.", true);
    return;
  }

  const units = currentUnits();
  try {
    await api.post("/refunds", {
      member_id: memberId,
      lunch_units: units.lunch,
      breakfast_units: units.breakfast,
      brunch_units: units.brunch,
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
  const auth = getAuth();
  document.getElementById("refund-processed-by").value = auth?.username || "";

  try {
    const settings = await api.get("/settings");
    unitPrices = settings.unit_prices;
  } catch (_) {
    // preview just stays ₹0.00 until the server computes the real amount
  }

  await loadMemberOptions();
  await loadRefunds();
})();
