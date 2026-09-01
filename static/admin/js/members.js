// Member CRUD, credit adjustments, and QR reprinting for the admin dashboard.
// Read-only for the counter role (they can look members up for a top-up,
// but everything that changes a member is admin-only — same boundary the
// API itself enforces, mirrored here so the UI doesn't offer a button that
// would just come back as a 403).

let allMembers = [];
let globalSettings = null;
const isAdmin = getAuth()?.role === "admin";

const membersBody = document.getElementById("members-body");
const filterType = document.getElementById("filter-type");
const filterStatus = document.getElementById("filter-status");
const filterSearch = document.getElementById("filter-search");

if (!isAdmin) {
  document.getElementById("btn-new-member").style.display = "none";
}

async function loadMembers() {
  const params = new URLSearchParams();
  if (filterType.value) params.set("type", filterType.value);
  if (filterStatus.value) params.set("status", filterStatus.value);

  try {
    allMembers = await api.get(`/members?${params.toString()}`);
    renderMembers();
  } catch (err) {
    membersBody.innerHTML = `<tr><td colspan="9" class="empty-state">Could not load members: ${escapeHtml(err.message)}</td></tr>`;
  }
}

// Grace units remaining per meal type — grace lets a balance go to
// -graceUnits before a scan is rejected, so "remaining" is how much further
// negative that meal's balance could still go.
function graceLeft(member, mealType) {
  if (!globalSettings) return null;
  const override = member.grace_allowance_override;
  const grace = override ?? (globalSettings.grace_allowance_enabled ? globalSettings.grace_allowance_units : 0);
  if (grace === 0) return 0;
  const balance = member.balances[mealType];
  const used = balance < 0 ? -balance : 0;
  return Math.max(0, grace - used);
}

function renderGraceCell(member) {
  if (!globalSettings) return "—";
  const override = member.grace_allowance_override;
  const graceActive = override != null || globalSettings.grace_allowance_enabled;
  if (!graceActive) return '<span class="empty-state">off</span>';

  const l = graceLeft(member, "lunch");
  const b = graceLeft(member, "breakfast");
  const br = graceLeft(member, "brunch");
  return `<span title="Lunch / Breakfast / Brunch">L:${l} B:${b} Br:${br}</span>`;
}

function renderMembers() {
  const search = filterSearch.value.trim().toLowerCase();
  const rows = allMembers.filter((m) => !search || m.name.toLowerCase().includes(search));

  if (rows.length === 0) {
    membersBody.innerHTML = `<tr><td colspan="9" class="empty-state">No members match.</td></tr>`;
    return;
  }

  membersBody.innerHTML = rows
    .map((m) => {
      const details =
        m.type === "student"
          ? [m.class_name, m.roll_number].filter(Boolean).join(" / ") || "—"
          : m.staff_id || "—";
      const statusBadge =
        m.status === "active"
          ? '<span class="badge badge-success">Active</span>'
          : '<span class="badge badge-neutral">Inactive</span>';

      const actions = isAdmin
        ? `<button class="secondary btn-edit">Edit</button>
           <button class="secondary btn-credit">Credit</button>
           <button class="secondary btn-reprint">QR</button>
           <button class="secondary btn-toggle-status">${m.status === "active" ? "Deactivate" : "Activate"}</button>`
        : `<span class="empty-state">view only</span>`;

      return `
      <tr data-id="${m._id}">
        <td>${escapeHtml(m.name)}</td>
        <td>${m.type}</td>
        <td>${escapeHtml(details)}</td>
        <td>${m.balances.lunch}</td>
        <td>${m.balances.breakfast}</td>
        <td>${m.balances.brunch}</td>
        <td>${renderGraceCell(m)}</td>
        <td>${statusBadge}</td>
        <td class="actions">${actions}</td>
      </tr>`;
    })
    .join("");
}

function findMember(id) {
  return allMembers.find((m) => m._id === id);
}

// --- Add/edit member dialog ---

const memberDialog = document.getElementById("member-dialog");
const memberForm = document.getElementById("member-form");
const memberDialogTitle = document.getElementById("member-dialog-title");
const memberTypeInput = document.getElementById("member-type");
const fieldStatus = document.getElementById("field-status");

function toggleTypeFields() {
  const isStudent = memberTypeInput.value === "student";
  document.getElementById("field-class-name").style.display = isStudent ? "" : "none";
  document.getElementById("field-roll-number").style.display = isStudent ? "" : "none";
  document.getElementById("field-staff-id").style.display = isStudent ? "none" : "";
}
memberTypeInput.addEventListener("change", toggleTypeFields);

function openMemberDialog(member) {
  memberForm.reset();
  document.getElementById("member-id").value = member?._id || "";
  memberDialogTitle.textContent = member ? "Edit member" : "Add member";
  fieldStatus.style.display = member ? "" : "none";

  memberTypeInput.value = member?.type || "student";
  memberTypeInput.disabled = Boolean(member); // type isn't editable after creation
  document.getElementById("member-name").value = member?.name || "";
  document.getElementById("member-class").value = member?.class_name || "";
  document.getElementById("member-roll").value = member?.roll_number || "";
  document.getElementById("member-staff-id").value = member?.staff_id || "";
  document.getElementById("member-grace").value = member?.grace_allowance_override ?? "";
  document.getElementById("member-status").value = member?.status || "active";

  toggleTypeFields();
  memberDialog.showModal();
}

document.getElementById("btn-new-member").addEventListener("click", () => openMemberDialog(null));
document.getElementById("btn-cancel-member").addEventListener("click", () => memberDialog.close());

memberForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  const id = document.getElementById("member-id").value;
  const grace = document.getElementById("member-grace").value;

  try {
    if (id) {
      await api.patch(`/members/${id}`, {
        name: document.getElementById("member-name").value,
        class_name: document.getElementById("member-class").value || null,
        roll_number: document.getElementById("member-roll").value || null,
        staff_id: document.getElementById("member-staff-id").value || null,
        status: document.getElementById("member-status").value,
        grace_allowance_override: grace === "" ? null : Number(grace),
      });
      showToast("Member updated.");
    } else {
      await api.post("/members", {
        type: memberTypeInput.value,
        name: document.getElementById("member-name").value,
        class_name: document.getElementById("member-class").value || null,
        roll_number: document.getElementById("member-roll").value || null,
        staff_id: document.getElementById("member-staff-id").value || null,
        grace_allowance_override: grace === "" ? null : Number(grace),
      });
      showToast("Member added.");
    }
    memberDialog.close();
    loadMembers();
  } catch (err) {
    showToast(err.message, true);
  }
});

// --- Credit dialog ---

const creditDialog = document.getElementById("credit-dialog");
const creditForm = document.getElementById("credit-form");

function openCreditDialog(member) {
  document.getElementById("credit-member-id").value = member._id;
  document.getElementById("credit-member-name").textContent = `${member.name} (${member.type})`;
  document.getElementById("credit-lunch").value = 0;
  document.getElementById("credit-breakfast").value = 0;
  document.getElementById("credit-brunch").value = 0;
  creditDialog.showModal();
}

document.getElementById("btn-cancel-credit").addEventListener("click", () => creditDialog.close());

creditForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  const id = document.getElementById("credit-member-id").value;
  try {
    await api.post(`/members/${id}/credit`, {
      lunch_units: Number(document.getElementById("credit-lunch").value) || 0,
      breakfast_units: Number(document.getElementById("credit-breakfast").value) || 0,
      brunch_units: Number(document.getElementById("credit-brunch").value) || 0,
    });
    showToast("Balance credited.");
    creditDialog.close();
    loadMembers();
  } catch (err) {
    showToast(err.message, true);
  }
});

// --- Row actions (edit / credit / reprint QR / toggle status) ---

membersBody.addEventListener("click", async (e) => {
  const row = e.target.closest("tr[data-id]");
  if (!row) return;
  const member = findMember(row.dataset.id);
  if (!member) return;

  if (e.target.classList.contains("btn-edit")) {
    openMemberDialog(member);
  } else if (e.target.classList.contains("btn-credit")) {
    openCreditDialog(member);
  } else if (e.target.classList.contains("btn-reprint")) {
    await reprintQr(member);
  } else if (e.target.classList.contains("btn-toggle-status")) {
    await toggleStatus(member);
  }
});

async function reprintQr(member) {
  try {
    const auth = getAuth();
    const res = await fetch(`/members/${member._id}/reprint-qr`, {
      method: "POST",
      headers: { Authorization: `Bearer ${auth.token}` },
    });
    if (!res.ok) throw new Error("Could not generate QR image.");
    const blob = await res.blob();
    const url = URL.createObjectURL(blob);
    window.open(url, "_blank");
    showToast(`QR ready for ${member.name}.`);
  } catch (err) {
    showToast(err.message, true);
  }
}

async function toggleStatus(member) {
  const nextStatus = member.status === "active" ? "inactive" : "active";
  try {
    await api.patch(`/members/${member._id}`, { status: nextStatus });
    showToast(`${member.name} is now ${nextStatus}.`);
    loadMembers();
  } catch (err) {
    showToast(err.message, true);
  }
}

filterType.addEventListener("change", loadMembers);
filterStatus.addEventListener("change", loadMembers);
filterSearch.addEventListener("input", renderMembers);

(async function init() {
  try {
    globalSettings = await api.get("/settings");
  } catch (_) {
    // counter role or a transient error — grace column just shows "—"
  }
  await loadMembers();
})();
