// Expense logging and revenue-vs-expense summary for the admin dashboard.

document.getElementById("expense-date").valueAsDate = new Date();

async function loadExpenses() {
  const body = document.getElementById("expenses-body");
  try {
    const expenses = await api.get("/expenses");
    if (expenses.length === 0) {
      body.innerHTML = `<tr><td colspan="4" class="empty-state">No expenses logged yet.</td></tr>`;
      return;
    }
    body.innerHTML = expenses.slice().reverse().map((e) => `
      <tr>
        <td>${new Date(e.date).toLocaleDateString()}</td>
        <td>${escapeHtml(e.category)}</td>
        <td>${escapeHtml(e.description)}</td>
        <td>₹${e.amount.toFixed(2)}</td>
      </tr>`).join("");
  } catch (err) {
    body.innerHTML = `<tr><td colspan="4" class="empty-state">Could not load expenses: ${escapeHtml(err.message)}</td></tr>`;
  }
}

document.getElementById("expense-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  try {
    await api.post("/expenses", {
      category: document.getElementById("expense-category").value,
      description: document.getElementById("expense-description").value,
      amount: Number(document.getElementById("expense-amount").value),
      date: document.getElementById("expense-date").value,
      created_by: document.getElementById("expense-created-by").value,
    });
    showToast("Expense logged.");
    document.getElementById("expense-category").value = "";
    document.getElementById("expense-description").value = "";
    document.getElementById("expense-amount").value = "";
    loadExpenses();
    loadSummary();
  } catch (err) {
    showToast(err.message, true);
  }
});

async function loadSummary() {
  const start = document.getElementById("summary-start").value;
  const end = document.getElementById("summary-end").value;
  const params = new URLSearchParams();
  if (start) params.set("start", start);
  if (end) params.set("end", end);

  const statsEl = document.getElementById("summary-stats");
  try {
    const summary = await api.get(`/expenses/summary?${params.toString()}`);
    const profitClass = summary.profit >= 0 ? "badge-success" : "badge-danger";
    statsEl.innerHTML = `
      <div class="card"><strong>Revenue</strong><div style="font-size:22px">₹${summary.revenue.toFixed(2)}</div></div>
      <div class="card"><strong>Expenses</strong><div style="font-size:22px">₹${summary.expenses.toFixed(2)}</div></div>
      <div class="card"><strong>Profit</strong><div style="font-size:22px"><span class="badge ${profitClass}">₹${summary.profit.toFixed(2)}</span></div></div>`;
  } catch (err) {
    statsEl.innerHTML = `<span class="empty-state">Could not load summary: ${escapeHtml(err.message)}</span>`;
  }
}

document.getElementById("btn-run-summary").addEventListener("click", loadSummary);

(async function init() {
  await loadExpenses();
  await loadSummary();
})();
