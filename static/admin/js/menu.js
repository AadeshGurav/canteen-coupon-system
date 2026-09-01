// Menu category CRUD and menu log entries for the admin dashboard.

let categories = [];

async function loadCategories() {
  try {
    categories = await api.get("/menu-categories");
    renderCategoriesList();
    renderCategoryCheckboxes();
  } catch (err) {
    showToast(err.message, true);
  }
}

function renderCategoriesList() {
  const container = document.getElementById("categories-list");
  if (categories.length === 0) {
    container.innerHTML = '<span class="empty-state">No categories yet — add one above.</span>';
    return;
  }
  container.innerHTML = categories.map((c) => `
    <span class="badge badge-neutral">
      ${escapeHtml(c.name)}
      <button class="secondary btn-delete-category" data-id="${c._id}" style="min-height:auto;padding:0 6px;margin-left:4px">×</button>
    </span>`).join("");
}

function renderCategoryCheckboxes() {
  const container = document.getElementById("menu-categories-checkboxes");
  if (categories.length === 0) {
    container.innerHTML = '<span class="empty-state">Add a category above first.</span>';
    return;
  }
  container.innerHTML = categories.map((c) => `
    <label style="display:inline-flex;align-items:center;gap:4px;font-weight:400">
      <input type="checkbox" value="${escapeHtml(c.name)}" class="menu-category-checkbox"> ${escapeHtml(c.name)}
    </label>`).join("");
}

document.getElementById("btn-add-category").addEventListener("click", async () => {
  const name = document.getElementById("category-name").value.trim();
  if (!name) {
    showToast("Enter a category name.", true);
    return;
  }
  try {
    await api.post("/menu-categories", {
      name,
      description: document.getElementById("category-description").value || null,
    });
    document.getElementById("category-name").value = "";
    document.getElementById("category-description").value = "";
    showToast("Category added.");
    loadCategories();
  } catch (err) {
    showToast(err.message, true);
  }
});

document.getElementById("categories-list").addEventListener("click", async (e) => {
  if (!e.target.classList.contains("btn-delete-category")) return;
  try {
    await api.delete(`/menu-categories/${e.target.dataset.id}`);
    showToast("Category removed.");
    loadCategories();
  } catch (err) {
    showToast(err.message, true);
  }
});

// --- Menu log ---

document.getElementById("menu-date").valueAsDate = new Date();

async function loadMenuLog() {
  const body = document.getElementById("menu-body");
  try {
    const entries = await api.get("/menu");
    if (entries.length === 0) {
      body.innerHTML = `<tr><td colspan="5" class="empty-state">No menu entries logged yet.</td></tr>`;
      return;
    }
    body.innerHTML = entries.slice().reverse().map((entry) => `
      <tr>
        <td>${new Date(entry.date).toLocaleDateString()}</td>
        <td>${entry.meal_type}</td>
        <td>${entry.categories.map(escapeHtml).join(", ")}</td>
        <td>${entry.items.map(escapeHtml).join(", ")}</td>
        <td><button class="secondary btn-delete-entry" data-id="${entry._id}">Delete</button></td>
      </tr>`).join("");
  } catch (err) {
    body.innerHTML = `<tr><td colspan="5" class="empty-state">Could not load menu log: ${escapeHtml(err.message)}</td></tr>`;
  }
}

document.getElementById("menu-body").addEventListener("click", async (e) => {
  if (!e.target.classList.contains("btn-delete-entry")) return;
  try {
    await api.delete(`/menu/${e.target.dataset.id}`);
    showToast("Menu entry removed.");
    loadMenuLog();
  } catch (err) {
    showToast(err.message, true);
  }
});

document.getElementById("menu-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const selectedCategories = Array.from(document.querySelectorAll(".menu-category-checkbox:checked")).map((c) => c.value);
  if (selectedCategories.length === 0) {
    showToast("Select at least one category.", true);
    return;
  }
  const items = document.getElementById("menu-items").value.split(",").map((i) => i.trim()).filter(Boolean);

  try {
    await api.post("/menu", {
      date: document.getElementById("menu-date").value,
      meal_type: document.getElementById("menu-meal-type").value,
      categories: selectedCategories,
      items,
      created_by: document.getElementById("menu-created-by").value,
    });
    showToast("Menu entry logged.");
    document.getElementById("menu-items").value = "";
    document.querySelectorAll(".menu-category-checkbox").forEach((c) => (c.checked = false));
    loadMenuLog();
  } catch (err) {
    showToast(err.message, true);
  }
});

(async function init() {
  await loadCategories();
  await loadMenuLog();
})();
