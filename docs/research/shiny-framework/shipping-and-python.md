# Shipping routes and Shiny for Python (Agent C)

Research date: 2026-10-02. Scope: questions 1 to 5 of the task contract. No
framework comparison here; where a route makes demands on structure, they are
stated in general terms.

## 1. Shiny app in an R package for release (CRAN or r-universe)

What `R CMD check` and CRAN policy require of a package that ships an app:

- **Top-level files.** Anything at the package root that is not part of the
  standard package layout triggers the NOTE "Non-standard files/directories
  found at top level". Shiny app sources and CI configuration are the usual
  causes; the fix is `.Rbuildignore` (R-hub blog, 2020, older than 2 years).
  R Packages describes `.Rbuildignore` as the way to resolve "the tension
  between the practices that support your development process and CRAN's
  requirements", and recommends `usethis::use_build_ignore()`. For
  table-explorer this would cover at least `app.R`, `app.py`,
  `requirements.txt`, `dev/`, `docs/`, `_scratch/`, `sample_data/`, the loose
  top-level `.R` files, `CLAUDE.md`, `TODO.md` and any `manifest.json`; there
  is no `.Rbuildignore` today (backlog I6).
- **Static assets.** Files under `inst/` are copied to the top level of the
  installed package and found at run time with `system.file(..., package =
  )`. Do not create `inst/` subdirectories that collide with package
  directories (`inst/R`, `inst/data`, and so on).
- **Entry point.** Mastering Shiny (ch. 20) wraps `shinyApp()` in an exported
  function, adds an `app.R` that calls `pkgload::load_all(".")` and then that
  function for deployment, and build-ignores `app.R`.
- **Examples and tests.** CRAN policy: examples "should run for no more than
  a few seconds each", and packages "should not start external software (such
  as PDF viewers or browsers) during examples or tests unless that specific
  instance of the software is explicitly closed afterwards". So a
  `run_app()` example must not launch the app during check (the usual
  wrapper is `if (interactive())` [unverified as a policy wording; it is
  convention]). Browser-driven tests (shinytest2) need skipping on CRAN for
  the same reason.
- **Suggests.** A Suggests package "should be used conditionally in examples
  or tests if it cannot straightforwardly be installed on the major R
  platforms". table-explorer lists `rJava`, `RJDBC`, `odbc`, `bigrquery` and
  several other drivers there, so every use needs a `requireNamespace()`
  guard.
- **File system and network.** Packages "should not write in the user's home
  filespace ... nor anywhere else on the file system apart from the R
  session's temporary directory", and Internet resources must "fail
  gracefully". Neither data nor documentation "should exceed 5MB", which
  bears on `sample_data/` if it were shipped.
- **r-universe.** Needs a registry repo named `<user>.r-universe.dev` with a
  `packages.json`, plus the r-universe GitHub app. Packages "do not need to be
  under the same account or even on GitHub" and need not be on CRAN. I found
  no statement on whether a package that fails `R CMD check` is still
  published.

Sources:
- https://www.r-bloggers.com/2020/05/non-standard-files-directories-rbuildignore-and-inst/
- https://r-pkgs.org/structure.html#sec-rbuildignore
- https://r-pkgs.org/misc.html#sec-misc-inst
- https://mastering-shiny.org/scaling-packaging.html
- https://cran.r-project.org/web/packages/policies.html
- https://docs.r-universe.dev/publish/set-up.html

## 2. Shiny app as or inside a Positron (or VS Code) extension

**Mechanism.** Positron runs ordinary VS Code extensions ("Positron is
compatible with VS Code extensions"). An extension reaches Positron-only
features through the `@posit-dev/positron` npm package and
`tryAcquirePositronApi()`, which returns `null` in VS Code. Two namespaces
matter: `positron.runtime` ("Execute Python or R code in the active console,
enumerate sessions, inspect variables") and `positron.window` ("Preview URLs
and HTML"). Posit's `positron-api-showcase` repo, labelled a "demo
extension", shows `executeCode()` and `previewUrl()` (opens a URL in the
Viewer pane). So the plausible shape is: an extension command calls
`executeCode("r", "tableexplorer::run_app()")` in the user's R session, and
the app appears in the Viewer.

**Existing extensions that launch Shiny apps.** Posit's Shiny extension
(`posit.shiny`, VS Code Marketplace and Open VSX; latest release v1.4.2,
dated 22 July on the releases page, year not shown) adds "Run Shiny App" and
"Debug Shiny App" to the Run menu "when editing an `app.py` or `app.R`
file". Python apps use whatever interpreter the VS Code Python extension
selects. Positron ships it as a bootstrapped extension; apps open in the
Viewer by default (`positron.runApp.previewMode`, `shiny.previewType`).
Positron also has an internal `runApplication` API, exposed to the Shiny
extension, that launches apps in a terminal; issue #14973 (opened
2026-07-17, closed, milestone 2026.08.0) extended it for Python apps.

**Extensions that bundle an R or Python app.** None found. Searched: Positron
extension docs, the Positron repo issues and discussions, Open VSX and the
VS Code Marketplace via web search, and "webR VS Code extension". Every
mechanism found runs code in the user's own R or Python session, so **an
extension route needs R, the package and its dependencies installed on the
user's machine**. The only path without local R is Shinylive (webR in the
browser; R package shinylive 0.5.0, `shinylive::export()`), which could in
principle be shown in a webview, but no extension doing so was found, and
webR cannot install packages from source, only prebuilt WebAssembly
binaries. Database drivers such as `odbc` or `rJava` would not work there
[unverified for each specific driver].

**Does structure matter?** Only at the edges. If the app is an installed
package, the extension calls one exported function, which is the cleanest
contract. If it is a folder, the extension must know a path and call
`shiny::runApp()` on it. The Shiny extension's Run button keys on file names
(`app.R`, `app.py`, `app_*.py`), not on any framework.

Sources:
- https://positron.posit.co/extension-development.html
- https://github.com/posit-dev/positron-api-showcase
- https://positron.posit.co/develop-data-apps.html
- https://github.com/posit-dev/shiny-vscode
- https://github.com/posit-dev/shiny-vscode/releases
- https://github.com/posit-dev/positron/issues/14973
- https://posit-dev.github.io/r-shinylive/

## 3. Hosting on Posit Connect Cloud

All sources below are Connect Cloud pages or posts, not Posit Cloud,
self-hosted Connect or shinyapps.io, except the rsconnect and renv references,
which describe the tool that writes the manifest.

- **Entry point.** A primary file, for example `app.R`, confirmed at publish
  time.
- **Manifest.** "Any content that has R code needs a `manifest.json` file
  included in the GitHub repository." Connect Cloud "does not currently
  support renv to setup the R environment. It captures everything it needs
  from `manifest.json`, including the packages and R version." Generate it
  with `rsconnect::writeManifest()` (rsconnect 1.11.2; arguments include
  `appDir`, `appFiles`, `appPrimaryDoc`) and re-run it when files or
  dependencies change.
- **R version.** Connect Cloud "will attempt to use the R version specified
  in the `manifest.json`" and supports R 4.0.0 through 4.6.0. The project
  builds on R 4.6.1, so a manifest written from that session names a version
  newer than the stated range. What Connect Cloud does then is not
  documented; worth a test deploy.
- **Dependency capture.** rsconnect uses `renv.lock` if present, otherwise
  `renv::snapshot()`. renv "will also detect dependencies expressed in the
  DESCRIPTION file" and finds `pkg::`, `library()` and `requireNamespace()`
  calls in code. Suggests are excluded from deployment resolution, so a
  Suggests package used only conditionally may need an explicit
  `requireNamespace()` call to be picked up. Packages "built and installed
  from a directory on your local computer" cannot be deployed.
- **Apps structured as packages.** No Connect Cloud page discusses package
  structure, golem, rhino or DESCRIPTION directly. The working pattern is the
  Mastering Shiny one: a top-level `app.R` that loads the package source
  (`pkgload::load_all()`) and calls the run function. The package is then
  deployed as files, not installed, and its own Imports become dependencies.
  table-explorer's `app.R` already does this. `pkgload` is in Suggests but is
  called with `::` in `app.R`, so renv should detect it [unverified: not
  tested here].
- **Publishing paths.** GitHub (needs `manifest.json`; optional automatic
  republish on push), Positron with Posit Publisher, `rsconnect::deployApp()`,
  and RStudio (post of 2026-09-04). Private repositories need the Basic or
  Enhanced plan; Free is public only.
- **Python.** A primary `app.py` and a `requirements.txt`, from a public
  repo; the guide chooses a Python version at publish time. `pyproject.toml`
  is not mentioned.

**Structure verdict:** this route works with any structure that offers an
`app.R` (or `app.py`) entry point and a manifest. It does not separate the
options except by what that entry file must do.

Sources:
- https://docs.posit.co/connect-cloud/user/platform/r.html
- https://docs.posit.co/connect-cloud/user/content/shiny.html
- https://posit.co/blog/four-ways-publish-your-shiny-application-posit-connect-cloud
- https://rstudio.github.io/rsconnect/reference/writeManifest.html
- https://rstudio.github.io/rsconnect/reference/appDependencies.html
- https://rstudio.github.io/renv/reference/dependencies.html
- https://docs.posit.co/connect-cloud/whats-new/posts/2024-12-01-connect-cloud-beta.html
- https://docs.posit.co/connect-cloud/how-to/python/shiny-python.html

## 4. One codebase for routes 1 to 3

Yes, if the codebase is an R package, because the package form is the only
one of the three routes that constrains structure. What it requires:

1. An exported function that builds and returns the app (`run_app()`), with
   all static assets in `inst/` resolved through `system.file()`, so the app
   behaves the same installed (route 1, route 2) and source-loaded (route 3).
2. A thin top-level `app.R` that loads the package and calls that function,
   plus a committed `manifest.json` regenerated whenever dependencies change,
   both listed in `.Rbuildignore`.
3. Every non-package file at the root (Python app, dev scripts, docs, sample
   data, notes) in `.Rbuildignore`, so `R CMD check` stays clean.
4. For route 2, an extension kept outside the package (its own repo or a
   build-ignored folder) that calls `tableexplorer::run_app()` through
   `positron.runtime.executeCode()`; the user installs R and the package.
5. Conditional use of every Suggests package, which both CRAN (route 1) and
   manifest capture (route 3) reward.
6. The R version in the manifest kept within what Connect Cloud supports.

Routes 2 and 3 alone would work from a plain folder with `app.R`; only
route 1 forces package form, and package form serves the other two at the
cost of the entry file and the ignore list.

Sources: as in sections 1 to 3.

## 5. How Shiny for Python structures a larger app

- **Version.** `shiny` 1.8.0 on PyPI, released 2026-09-13, requires Python
  3.10 or later.
- **Modules.** Core syntax splits a module into `@module.ui` and
  `@module.server` functions; each instance takes an `id` that namespaces its
  inputs and outputs. Express syntax uses a single `@module` decorator.
  "Modules are just functions": they take parameters, return values and nest.
- **Entry point.** `shiny run` looks for `app.py` by default; Posit
  recommends names beginning with `app` "because the Shiny extension expects
  this naming pattern". `shiny.run_app()` takes `app` as `"<module>:<attribute>"`,
  where the module "can be a relative path to a `.py` file or a directory
  (with an `app.py` file inside of it)", plus `app_dir` and `factory=True`
  for an application factory.
- **Static assets.** `App(ui, server, *, static_assets=...)` takes a directory
  mounted at `/`, or a dict of mount points, which is the Python counterpart
  of `inst/app/www`.
- **Packaging as a Python package.** The Shiny for Python docs I found give
  no official guide or template for shipping an app as an installable
  package. The general pattern would be a `pyproject.toml` package exposing
  the `App` object or a factory, with a thin `app.py` for `shiny run` and
  Connect Cloud [unverified: inferred from `run_app()` arguments, not from a
  Posit guide]. Connect Cloud's documented Python input is `app.py` plus
  `requirements.txt`.

Sources:
- https://pypi.org/project/shiny/
- https://shiny.posit.co/py/docs/modules.html
- https://shiny.posit.co/py/get-started/create-run.html
- https://shiny.posit.co/py/api/core/run_app.html
- https://shiny.posit.co/py/api/core/App.html

## What could not be verified

- Whether r-universe publishes packages that fail `R CMD check`.
- What Connect Cloud does when the manifest names R 4.6.1.
- Any extension that bundles an R or Python app; the year of the Shiny
  extension's v1.4.2 release.
- An official Shiny for Python guide to app-as-package.
- `[unverified]` claims remaining: 4.
