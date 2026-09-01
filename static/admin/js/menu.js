// Menu planning: a month calendar as the primary view (item 8), plus the
// category CRUD that feeds it. Clicking any day opens a dialog to log an
// entry for that date and review what's already logged there.

let categories = [];
let entriesByDate = {}; // "YYYY-MM-DD" -> array of entries
let calendarMonth = new Date(); // any date within the month currently shown

const MEAL_LABELS = { breakfast: "Breakfast", lunch: "Lunch", brunch: "Brunch" };

function dateKey(d) {
  const yyyy = d.getFullYear();
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const dd = String(d.getDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}

function isSameDay(a, b) {
  return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
}

// --- Categories ---

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

// --- Calendar ---

function renderWeekdayHeader() {
  const container = document.getElementById("calendar-weekdays");
  const weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  container.innerHTML = weekdays.map((w) => `<div class="calendar-weekday">${w}</div>`).join("");
}

async function loadEntriesForMonth() {
  const start = new Date(calendarMonth.getFullYear(), calendarMonth.getMonth(), 1);
  const end = new Date(calendarMonth.getFullYear(), calendarMonth.getMonth() + 1, 0);
  entriesByDate = {};
  try {
    const entries = await api.get(`/menu?start=${dateKey(start)}&end=${dateKey(end)}`);
    for (const entry of entries) {
      const key = entry.date.slice(0, 10);
      (entriesByDate[key] ||= []).push(entry);
    }
  } catch (err) {
    showToast(`Could not load menu entries: ${err.message}`, true);
  }
}

function renderCalendarGrid() {
  const label = document.getElementById("calendar-month-label");
  label.textContent = calendarMonth.toLocaleDateString(undefined, { month: "long", year: "numeric" });

  const grid = document.getElementById("calendar-grid");
  const year = calendarMonth.getFullYear();
  const month = calendarMonth.getMonth();
  const firstOfMonth = new Date(year, month, 1);
  const startOffset = firstOfMonth.getDay(); // Sunday-first grid
  const gridStart = new Date(year, month, 1 - startOffset);
  const today = new Date();

  const cells = [];
  for (let i = 0; i < 42; i++) {
    const cellDate = new Date(gridStart.getFullYear(), gridStart.getMonth(), gridStart.getDate() + i);
    const key = dateKey(cellDate);
    const entries = entriesByDate[key] || [];
    const classes = ["calendar-day"];
    if (cellDate.getMonth() !== month) classes.push("is-outside-month");
    if (isSameDay(cellDate, today)) classes.push("is-today");

    const entryTags = entries
      .map((e) => `<div class="day-entry">${MEAL_LABELS[e.meal_type] || e.meal_type}: ${escapeHtml(e.items.join(", "))}</div>`)
      .join("");

    cells.push(`
      <div class="${classes.join(" ")}" data-date="${key}" role="button" tabindex="0">
        <div class="day-number">${cellDate.getDate()}</div>
        ${entryTags}
      </div>`);
  }
  grid.innerHTML = cells.join("");
}

async function refreshCalendar() {
  await loadEntriesForMonth();
  renderCalendarGrid();
}

document.getElementById("btn-prev-month").addEventListener("click", () => {
  calendarMonth = new Date(calendarMonth.getFullYear(), calendarMonth.getMonth() - 1, 1);
  refreshCalendar();
});

document.getElementById("btn-next-month").addEventListener("click", () => {
  calendarMonth = new Date(calendarMonth.getFullYear(), calendarMonth.getMonth() + 1, 1);
  refreshCalendar();
});

document.getElementById("calendar-grid").addEventListener("click", (e) => {
  const cell = e.target.closest(".calendar-day");
  if (cell) openMenuDialog(cell.dataset.date);
});

document.getElementById("calendar-grid").addEventListener("keydown", (e) => {
  if (e.key !== "Enter" && e.key !== " ") return;
  const cell = e.target.closest(".calendar-day");
  if (cell) {
    e.preventDefault();
    openMenuDialog(cell.dataset.date);
  }
});

document.getElementById("btn-add-entry").addEventListener("click", () => openMenuDialog(dateKey(new Date())));

// --- Log-entry dialog ---

const menuDialog = document.getElementById("menu-dialog");

function renderExistingEntriesForDialog(key) {
  const container = document.getElementById("menu-dialog-existing");
  const entries = entriesByDate[key] || [];
  if (entries.length === 0) {
    container.innerHTML = '<p class="empty-state">Nothing logged yet for this day.</p>';
    return;
  }
  container.innerHTML = `
    <table>
      <thead><tr><th>Meal</th><th>Categories</th><th>Items</th><th></th></tr></thead>
      <tbody>
        ${entries.map((e) => `
          <tr>
            <td>${MEAL_LABELS[e.meal_type] || e.meal_type}</td>
            <td>${e.categories.map(escapeHtml).join(", ")}</td>
            <td>${e.items.map(escapeHtml).join(", ")}</td>
            <td><button type="button" class="secondary btn-delete-entry" data-id="${e._id}">Delete</button></td>
          </tr>`).join("")}
      </tbody>
    </table>`;
}

function openMenuDialog(key) {
  document.getElementById("menu-entry-date").value = key;
  const label = new Date(`${key}T00:00:00`).toLocaleDateString(undefined, {
    weekday: "long", year: "numeric", month: "long", day: "numeric",
  });
  document.getElementById("menu-dialog-date-label").textContent = label;
  document.getElementById("menu-items").value = "";
  document.querySelectorAll(".menu-category-checkbox").forEach((c) => (c.checked = false));
  renderExistingEntriesForDialog(key);
  menuDialog.showModal();
}

document.getElementById("btn-close-menu-dialog").addEventListener("click", () => menuDialog.close());

document.getElementById("menu-dialog-existing").addEventListener("click", async (e) => {
  if (!e.target.classList.contains("btn-delete-entry")) return;
  try {
    await api.delete(`/menu/${e.target.dataset.id}`);
    showToast("Menu entry removed.");
    await refreshCalendar();
    renderExistingEntriesForDialog(document.getElementById("menu-entry-date").value);
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
  const key = document.getElementById("menu-entry-date").value;

  try {
    await api.post("/menu", {
      date: key,
      meal_type: document.getElementById("menu-meal-type").value,
      categories: selectedCategories,
      items,
      created_by: document.getElementById("menu-created-by").value,
    });
    showToast("Menu entry logged.");
    document.getElementById("menu-items").value = "";
    document.querySelectorAll(".menu-category-checkbox").forEach((c) => (c.checked = false));
    await refreshCalendar();
    renderExistingEntriesForDialog(key);
  } catch (err) {
    showToast(err.message, true);
  }
});

(async function init() {
  const auth = getAuth();
  document.getElementById("menu-created-by").value = auth?.username || "";
  renderWeekdayHeader();
  await loadCategories();
  await refreshCalendar();
})();
