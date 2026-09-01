// Login page — deliberately doesn't use nav.js/requireAuthOrRedirect (this
// is the one page that must work with no session at all). If a valid
// session already exists, skip straight past the login form.

const existing = getAuth();
if (existing && existing.token) {
  window.location.href = "index.html";
}

const errorEl = document.getElementById("login-error");
const submitBtn = document.getElementById("login-submit");

document.getElementById("login-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  errorEl.style.display = "none";
  submitBtn.disabled = true;
  submitBtn.textContent = "Logging in…";

  try {
    const response = await api.post("/auth/login", {
      username: document.getElementById("login-username").value,
      password: document.getElementById("login-password").value,
    });
    setAuth(response);
    window.location.href = "index.html";
  } catch (err) {
    errorEl.textContent = err.message;
    errorEl.style.display = "block";
    submitBtn.disabled = false;
    submitBtn.textContent = "Log in";
  }
});

// Best-effort branding — GET /settings/branding is the one setting that's
// public (no login yet to gate it behind); everything else on Settings
// stays behind auth. Falls back to the default brand text on any failure.
(async () => {
  try {
    const branding = await api.get("/settings/branding");
    document.getElementById("login-brand").textContent = branding.app_name;
    document.title = `Log in — ${branding.app_name}`;
  } catch (_) {
    // keep the default brand text
  }
})();
