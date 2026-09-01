// Global settings (grace allowance, meal windows, timezone, unit prices,
// UPI, reversal window, branding) for the admin dashboard. All of this is
// DB-backed — see app/routers/settings.py.

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

async function loadTimezoneOptions(selected) {
  const select = document.getElementById("local-timezone");
  try {
    const timezones = await api.get("/settings/timezones");
    select.innerHTML = timezones.map((tz) => `<option value="${tz}" ${tz === selected ? "selected" : ""}>${tz}</option>`).join("");
  } catch (err) {
    select.innerHTML = `<option value="${selected}">${selected}</option>`;
    showToast(`Could not load the full timezone list: ${err.message}`, true);
  }
}

async function loadSettings() {
  try {
    const settings = await api.get("/settings");
    document.getElementById("grace-enabled").checked = settings.grace_allowance_enabled;
    document.getElementById("grace-units").value = settings.grace_allowance_units;
    document.getElementById("reversal-window").value = settings.reversal_window_minutes;
    document.getElementById("upi-id").value = settings.upi_id;
    document.getElementById("upi-payee-name").value = settings.upi_payee_name;
    document.getElementById("app-name").value = settings.app_name;
    document.getElementById("price-lunch").value = settings.unit_prices.lunch;
    document.getElementById("price-breakfast").value = settings.unit_prices.breakfast;
    document.getElementById("price-brunch").value = settings.unit_prices.brunch;
    document.getElementById("prep-lead-minutes").value = settings.prep_lead_minutes;
    document.getElementById("purchase-lead-days").value = settings.purchase_lead_days;
    renderMealWindowFields(settings.meal_windows);
    await loadTimezoneOptions(settings.local_timezone);
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
      local_timezone: document.getElementById("local-timezone").value,
      upi_id: document.getElementById("upi-id").value.trim(),
      upi_payee_name: document.getElementById("upi-payee-name").value.trim(),
      app_name: document.getElementById("app-name").value.trim() || "Canteen Coupon System",
      unit_prices: {
        lunch: Number(document.getElementById("price-lunch").value) || 0,
        breakfast: Number(document.getElementById("price-breakfast").value) || 0,
        brunch: Number(document.getElementById("price-brunch").value) || 0,
      },
      prep_lead_minutes: Number(document.getElementById("prep-lead-minutes").value) || 0,
      purchase_lead_days: Number(document.getElementById("purchase-lead-days").value) || 0,
      meal_windows,
    });
    showToast("Settings saved.");
  } catch (err) {
    showToast(err.message, true);
  }
});

loadSettings();
