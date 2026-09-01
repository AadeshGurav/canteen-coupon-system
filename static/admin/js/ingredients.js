// Ingredients (master list), recipes (dish -> ingredients), and the
// purchase schedule those recipes generate from the menu calendar.

const isAdmin = getAuth()?.role === "admin";
let ingredientsById = {};

// --- Ingredients ---

async function loadIngredients() {
  const body = document.getElementById("ingredients-body");
  try {
    const ingredients = await api.get("/ingredients");
    ingredientsById = Object.fromEntries(ingredients.map((i) => [i._id, i]));
    renderIngredientSelect();

    if (ingredients.length === 0) {
      body.innerHTML = `<tr><td colspan="3" class="empty-state">No ingredients yet — add one above.</td></tr>`;
      return;
    }
    body.innerHTML = ingredients
      .map(
        (i) => `
      <tr>
        <td>${escapeHtml(i.name)}</td>
        <td>${escapeHtml(i.unit)}</td>
        <td><button class="secondary btn-delete-ingredient" data-id="${i._id}">Delete</button></td>
      </tr>`
      )
      .join("");
  } catch (err) {
    body.innerHTML = `<tr><td colspan="3" class="empty-state">Could not load ingredients: ${escapeHtml(err.message)}</td></tr>`;
  }
}

function renderIngredientSelect() {
  const select = document.getElementById("manual-item-ingredient");
  const options = Object.values(ingredientsById);
  select.innerHTML =
    options.length === 0
      ? `<option value="">No ingredients yet</option>`
      : options.map((i) => `<option value="${i._id}">${escapeHtml(i.name)} (${escapeHtml(i.unit)})</option>`).join("");
}

document.getElementById("btn-add-ingredient")?.addEventListener("click", async () => {
  const name = document.getElementById("ingredient-name").value.trim();
  const unit = document.getElementById("ingredient-unit").value.trim();
  if (!name || !unit) {
    showToast("Enter both a name and a unit.", true);
    return;
  }
  try {
    await api.post("/ingredients", { name, unit });
    document.getElementById("ingredient-name").value = "";
    document.getElementById("ingredient-unit").value = "";
    showToast("Ingredient added.");
    await loadIngredients();
    await loadRecipes();
  } catch (err) {
    showToast(err.message, true);
  }
});

document.getElementById("ingredients-body")?.addEventListener("click", async (e) => {
  if (!e.target.classList.contains("btn-delete-ingredient")) return;
  try {
    await api.delete(`/ingredients/${e.target.dataset.id}`);
    showToast("Ingredient removed.");
    await loadIngredients();
    await loadRecipes();
  } catch (err) {
    showToast(err.message, true);
  }
});

// --- Recipes ---

function addIngredientRow() {
  const container = document.getElementById("recipe-ingredient-rows");
  const options = Object.values(ingredientsById)
    .map((i) => `<option value="${i._id}">${escapeHtml(i.name)}</option>`)
    .join("");
  const row = document.createElement("div");
  row.className = "form-row recipe-ingredient-row";
  row.innerHTML = `
    <div class="field">
      <select class="recipe-row-ingredient">${options || `<option value="">Add an ingredient first</option>`}</select>
    </div>
    <div class="field">
      <input type="text" class="recipe-row-note" placeholder="e.g. 2kg per 50 servings">
    </div>
    <div class="field">
      <button type="button" class="secondary btn-remove-ingredient-row">Remove</button>
    </div>`;
  container.appendChild(row);
}

document.getElementById("btn-add-ingredient-row").addEventListener("click", addIngredientRow);

document.getElementById("recipe-ingredient-rows").addEventListener("click", (e) => {
  if (e.target.classList.contains("btn-remove-ingredient-row")) {
    e.target.closest(".recipe-ingredient-row").remove();
  }
});

function renderRecipeIngredients(recipe) {
  return recipe.ingredients
    .map((ri) => {
      const ingredient = ingredientsById[ri.ingredient_id];
      const name = ingredient ? ingredient.name : "(deleted ingredient)";
      return `${escapeHtml(name)} — ${escapeHtml(ri.quantity_note)}`;
    })
    .join("<br>");
}

async function loadRecipes() {
  const body = document.getElementById("recipes-body");
  try {
    const recipes = await api.get("/recipes");
    if (recipes.length === 0) {
      body.innerHTML = `<tr><td colspan="3" class="empty-state">No recipes yet — add one above.</td></tr>`;
      return;
    }
    body.innerHTML = recipes
      .map(
        (r) => `
      <tr>
        <td>${escapeHtml(r.dish_name)}</td>
        <td>${renderRecipeIngredients(r)}</td>
        <td><button class="secondary btn-delete-recipe" data-id="${r._id}">Delete</button></td>
      </tr>`
      )
      .join("");
  } catch (err) {
    body.innerHTML = `<tr><td colspan="3" class="empty-state">Could not load recipes: ${escapeHtml(err.message)}</td></tr>`;
  }
}

document.getElementById("recipes-body")?.addEventListener("click", async (e) => {
  if (!e.target.classList.contains("btn-delete-recipe")) return;
  try {
    await api.delete(`/recipes/${e.target.dataset.id}`);
    showToast("Recipe removed.");
    loadRecipes();
  } catch (err) {
    showToast(err.message, true);
  }
});

document.getElementById("recipe-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const dishName = document.getElementById("recipe-dish-name").value.trim();
  const rows = Array.from(document.querySelectorAll(".recipe-ingredient-row"));
  const ingredients = rows
    .map((row) => ({
      ingredient_id: row.querySelector(".recipe-row-ingredient").value,
      quantity_note: row.querySelector(".recipe-row-note").value.trim(),
    }))
    .filter((i) => i.ingredient_id && i.quantity_note);

  if (!dishName || ingredients.length === 0) {
    showToast("Enter a dish name and at least one ingredient with a quantity note.", true);
    return;
  }

  try {
    await api.post("/recipes", { dish_name: dishName, ingredients });
    showToast("Recipe saved.");
    e.target.reset();
    document.getElementById("recipe-ingredient-rows").innerHTML = "";
    loadRecipes();
  } catch (err) {
    showToast(err.message, true);
  }
});

// --- Purchase schedule ---

function scheduleRow(item) {
  const canEdit = isAdmin || getAuth()?.role === "counter";
  const checkbox = canEdit
    ? `<input type="checkbox" class="schedule-purchased-toggle" data-id="${item._id}" ${item.purchased ? "checked" : ""}>`
    : item.purchased
      ? "✅"
      : "—";
  const deleteBtn = isAdmin
    ? `<button class="secondary btn-delete-schedule-item" data-id="${item._id}">Delete</button>`
    : "";
  return `
    <tr>
      <td>${checkbox}</td>
      <td>${new Date(item.date).toLocaleDateString()}</td>
      <td>${escapeHtml(item.ingredient_name)}</td>
      <td>${escapeHtml(item.quantity_note)} ${escapeHtml(item.ingredient_unit)}</td>
      <td><span class="badge ${item.source === "auto" ? "badge-neutral" : "badge-warning"}">${item.source}</span></td>
      <td>${deleteBtn}</td>
    </tr>`;
}

async function loadSchedule() {
  const body = document.getElementById("schedule-body");
  try {
    const items = await api.get("/purchase-schedule");
    if (items.length === 0) {
      body.innerHTML = `<tr><td colspan="6" class="empty-state">Nothing scheduled yet.</td></tr>`;
      return;
    }
    body.innerHTML = items.map(scheduleRow).join("");
  } catch (err) {
    body.innerHTML = `<tr><td colspan="6" class="empty-state">Could not load the schedule: ${escapeHtml(err.message)}</td></tr>`;
  }
}

document.getElementById("schedule-body").addEventListener("change", async (e) => {
  if (!e.target.classList.contains("schedule-purchased-toggle")) return;
  try {
    await api.patch(`/purchase-schedule/${e.target.dataset.id}`, { purchased: e.target.checked });
    showToast(e.target.checked ? "Marked purchased." : "Marked not purchased.");
  } catch (err) {
    showToast(err.message, true);
    e.target.checked = !e.target.checked; // revert on failure
  }
});

document.getElementById("schedule-body").addEventListener("click", async (e) => {
  if (!e.target.classList.contains("btn-delete-schedule-item")) return;
  try {
    await api.delete(`/purchase-schedule/${e.target.dataset.id}`);
    showToast("Item removed.");
    loadSchedule();
  } catch (err) {
    showToast(err.message, true);
  }
});

document.getElementById("btn-generate-schedule")?.addEventListener("click", async () => {
  const start = document.getElementById("generate-start").value;
  const end = document.getElementById("generate-end").value;
  if (!start || !end) {
    showToast("Pick both a start and end date.", true);
    return;
  }
  try {
    const result = await api.post(`/purchase-schedule/generate?start=${start}&end=${end}`, {});
    showToast(`Generated ${result.created} new item(s) from the menu calendar.`);
    loadSchedule();
  } catch (err) {
    showToast(err.message, true);
  }
});

document.getElementById("btn-add-manual-item").addEventListener("click", async () => {
  const date = document.getElementById("manual-item-date").value;
  const ingredient_id = document.getElementById("manual-item-ingredient").value;
  const quantity_note = document.getElementById("manual-item-note").value.trim();
  if (!date || !ingredient_id || !quantity_note) {
    showToast("Fill in a date, ingredient, and quantity note.", true);
    return;
  }
  try {
    await api.post("/purchase-schedule", { date, ingredient_id, quantity_note });
    document.getElementById("manual-item-note").value = "";
    showToast("Added to the schedule.");
    loadSchedule();
  } catch (err) {
    showToast(err.message, true);
  }
});

(function applyRoleVisibility() {
  if (isAdmin) return;
  document.getElementById("ingredients-card").style.display = "none";
  document.getElementById("recipes-card").style.display = "none";
  document.getElementById("generate-schedule-row").style.display = "none";
})();

(async function init() {
  await loadIngredients(); // needed by everyone: populates the manual-item ingredient select
  if (isAdmin) await loadRecipes(); // recipes-card is hidden (and GET /recipes is admin-only) otherwise
  await loadSchedule();
})();
