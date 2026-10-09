# ============================================================
# dev/03_deploy.R - Deployment helpers
# Run interactively when deploying.
# ============================================================

# ── Deploy to Posit Connect / shinyapps.io ───────────────────
# rsconnect::deployApp(appName = "tableexplorer")

# ── Posit Connect Cloud (deploys from GitHub) ────────────────
# Connect Cloud reads manifest.json, not renv.lock; regenerate and commit it
# whenever dependencies change. It supports R 4.0.0 to 4.6.0 (see TODO.md).
# rsconnect::writeManifest(appPrimaryDoc = "app.R")

# ── Build source package for CRAN/distribution ───────────────
# devtools::build()
