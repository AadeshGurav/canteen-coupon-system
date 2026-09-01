// Admin-only user management: add/edit role/reset password/deactivate/delete.

const currentAuth = getAuth();

async function loadUsers() {
  const body = document.getElementById("users-body");
  try {
    const users = await api.get("/users");
    if (users.length === 0) {
      body.innerHTML = `<tr><td colspan="5" class="empty-state">No users yet.</td></tr>`;
      return;
    }
    body.innerHTML = users.map(renderUserRow).join("");
  } catch (err) {
    body.innerHTML = `<tr><td colspan="5" class="empty-state">Could not load users: ${escapeHtml(err.message)}</td></tr>`;
  }
}

function renderUserRow(user) {
  const isSelf = currentAuth && currentAuth.username === user.username;
  const statusBadge =
    user.status === "active"
      ? '<span class="badge badge-success">Active</span>'
      : '<span class="badge badge-neutral">Inactive</span>';

  const roleOptions = ["admin", "counter", "scanner"]
    .map((r) => `<option value="${r}" ${r === user.role ? "selected" : ""}>${r}</option>`)
    .join("");

  return `
    <tr data-id="${user._id}" data-username="${escapeHtml(user.username)}">
      <td>${escapeHtml(user.username)}${isSelf ? ' <span class="badge badge-neutral">you</span>' : ""}</td>
      <td><select class="role-select" style="width:auto" ${isSelf ? "disabled" : ""}>${roleOptions}</select></td>
      <td>${statusBadge}</td>
      <td>${formatDate(user.created_at)}</td>
      <td class="actions">
        <button class="secondary btn-reset-password">Reset password</button>
        <button class="secondary btn-toggle-status" ${isSelf ? "disabled" : ""}>${user.status === "active" ? "Deactivate" : "Activate"}</button>
        <button class="danger btn-delete" ${isSelf ? "disabled" : ""}>Delete</button>
      </td>
    </tr>`;
}

document.getElementById("user-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  try {
    await api.post("/users", {
      username: document.getElementById("new-username").value,
      password: document.getElementById("new-password").value,
      role: document.getElementById("new-role").value,
    });
    showToast("User added.");
    e.target.reset();
    loadUsers();
  } catch (err) {
    showToast(err.message, true);
  }
});

document.getElementById("users-body").addEventListener("change", async (e) => {
  if (!e.target.classList.contains("role-select")) return;
  const row = e.target.closest("tr");
  try {
    await api.patch(`/users/${row.dataset.id}`, { role: e.target.value });
    showToast(`${row.dataset.username}'s role updated.`);
  } catch (err) {
    showToast(err.message, true);
    loadUsers(); // revert the dropdown to the actual saved role
  }
});

document.getElementById("users-body").addEventListener("click", async (e) => {
  const row = e.target.closest("tr[data-id]");
  if (!row) return;
  const { id, username } = row.dataset;

  if (e.target.classList.contains("btn-reset-password")) {
    document.getElementById("reset-password-user-id").value = id;
    document.getElementById("reset-password-username").textContent = username;
    document.getElementById("reset-password-value").value = "";
    document.getElementById("reset-password-dialog").showModal();
  } else if (e.target.classList.contains("btn-toggle-status")) {
    const nextStatus = e.target.textContent.trim() === "Deactivate" ? "inactive" : "active";
    try {
      await api.patch(`/users/${id}`, { status: nextStatus });
      showToast(`${username} is now ${nextStatus}.`);
      loadUsers();
    } catch (err) {
      showToast(err.message, true);
    }
  } else if (e.target.classList.contains("btn-delete")) {
    try {
      await api.delete(`/users/${id}`);
      showToast(`${username} deleted.`);
      loadUsers();
    } catch (err) {
      showToast(err.message, true);
    }
  }
});

document.getElementById("btn-cancel-reset").addEventListener("click", () => {
  document.getElementById("reset-password-dialog").close();
});

document.getElementById("reset-password-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const id = document.getElementById("reset-password-user-id").value;
  try {
    await api.patch(`/users/${id}`, { password: document.getElementById("reset-password-value").value });
    showToast("Password reset.");
    document.getElementById("reset-password-dialog").close();
  } catch (err) {
    showToast(err.message, true);
  }
});

loadUsers();
