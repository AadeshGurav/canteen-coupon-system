// Scan history and reversal for the admin dashboard. Only accepted scans are
// ever recorded (rejections aren't stored — see app/services/scan_service.py),
// so every row here is either accepted, or accepted-and-reversed.

let membersById = {};
let reversalWindowMinutes = 10;

const reversedByInput = document.getElementById("reversed-by");
reversedByInput.value = localStorage.getItem("canteen_admin_name") || "";
reversedByInput.addEventListener("input", () => {
  localStorage.setItem("canteen_admin_name", reversedByInput.value);
});

function canReverse(scan) {
  if (scan.reversed) return false;
  const scannedAt = new Date(scan.scanned_at);
  const minutesElapsed = (Date.now() - scannedAt.getTime()) / 60000;
  return minutesElapsed <= reversalWindowMinutes;
}

function renderScanRow(scan) {
  const member = membersById[scan.member_id];
  const memberLabel = member ? escapeHtml(member.name) : scan.member_id;
  const graceBadge = scan.via_grace ? '<span class="badge badge-warning">GRACE</span>' : "—";
  const statusBadge = scan.reversed
    ? '<span class="badge badge-neutral">Reversed</span>'
    : '<span class="badge badge-success">Accepted</span>';

  const reverseBtn = canReverse(scan)
    ? `<button class="secondary btn-reverse" data-id="${scan._id}">Reverse</button>`
    : "";

  return `
    <tr>
      <td>${formatDate(scan.scanned_at)}</td>
      <td>${memberLabel}</td>
      <td>${scan.meal_type}</td>
      <td>${statusBadge}</td>
      <td>${graceBadge}</td>
      <td class="actions">${reverseBtn}</td>
    </tr>`;
}

async function loadScans() {
  const body = document.getElementById("scans-body");
  try {
    const [scans, members] = await Promise.all([api.get("/scan"), api.get("/members")]);
    membersById = Object.fromEntries(members.map((m) => [m._id, m]));

    if (scans.length === 0) {
      body.innerHTML = `<tr><td colspan="6" class="empty-state">No scans recorded yet.</td></tr>`;
      return;
    }
    body.innerHTML = scans.map(renderScanRow).join("");
  } catch (err) {
    body.innerHTML = `<tr><td colspan="6" class="empty-state">Could not load scans: ${escapeHtml(err.message)}</td></tr>`;
  }
}

document.getElementById("scans-body").addEventListener("click", async (e) => {
  if (!e.target.classList.contains("btn-reverse")) return;

  const reversedBy = reversedByInput.value.trim();
  if (!reversedBy) {
    showToast("Enter your name before reversing a scan.", true);
    reversedByInput.focus();
    return;
  }

  const scanId = e.target.dataset.id;
  try {
    const result = await api.post("/scan/reverse", { scan_id: scanId, reversed_by: reversedBy });
    if (result.success) {
      showToast(result.message);
      loadScans();
    } else {
      showToast(result.message, true);
    }
  } catch (err) {
    showToast(err.message, true);
  }
});

(async function init() {
  try {
    const settings = await api.get("/settings");
    reversalWindowMinutes = settings.reversal_window_minutes;
    document.getElementById("reversal-window-note").textContent =
      `Scans can be reversed within ${reversalWindowMinutes} minutes of being made.`;
  } catch (_) {
    // fall back to the default; loadScans() will still work
  }
  await loadScans();
})();
