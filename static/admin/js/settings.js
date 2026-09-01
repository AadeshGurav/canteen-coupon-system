// Global settings (grace allowance, meal windows, reversal window) for the
// admin dashboard. All of this is DB-backed — see app/routers/settings.py.

const MEAL_TYPES = [
  { key: "breakfast", label: "Breakfast" },
  { key: "lunch", label: "Lunch" },
  { key: "brunch", label: "Brunch (Saturday only)" },
];

function renderMealWindowFields(mealWindows) {
  const container = document.getElementById("meal-windows-fields");
  container.innerHTML = MEAL_TYPES.map(({ key, label }) => {
    const window = mealWindows[key] || { start: "", end: "" };
    return `
      <fieldset class="field" style="border:none;padding:0">
        <label>${label}</label>
        <div class="form-row">
          <div class="field">
            <label for="window-${key}-start">Start</label>
            <input id="window-${key}-start" type="time" value="${window.start}">
          </div>
          <div class="field">
            <label for="window-${key}-end">End</label>
            <input id="window-${key}-end" type="time" value="${window.end}">
          </div>
        </div>
      </fieldset>`;
  }).join("");
}

async function loadSettings() {
  try {
    const settings = await api.get("/settings");
    document.getElementById("grace-enabled").checked = settings.grace_allowance_enabled;
    document.getElementById("grace-units").value = settings.grace_allowance_units;
    document.getElementById("reversal-window").value = settings.reversal_window_minutes;
    renderMealWindowFields(settings.meal_windows);
  } catch (err) {
    showToast(`Could not load settings: ${err.message}`, true);
  }
}

document.getElementById("settings-form").addEventListener("submit", async (e) => {
  e.preventDefault();

  const meal_windows = Object.fromEntries(
    MEAL_TYPES.map(({ key }) => [
      key,
      {
        start: document.getElementById(`window-${key}-start`).value,
        end: document.getElementById(`window-${key}-end`).value,
      },
    ])
  );

  try {
    await api.patch("/settings", {
      grace_allowance_enabled: document.getElementById("grace-enabled").checked,
      grace_allowance_units: Number(document.getElementById("grace-units").value) || 0,
      reversal_window_minutes: Number(document.getElementById("reversal-window").value) || 0,
      meal_windows,
    });
    showToast("Settings saved.");
  } catch (err) {
    showToast(err.message, true);
  }
});

loadSettings();
