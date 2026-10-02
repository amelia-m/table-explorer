# No framework: plain package vs plain `app.R`

Agent B3. Researched 2026-10-02. Sources are numbered [S1] to [S18] and listed at the end. Claims from reasoning or memory without a source are marked `[unverified]`.

Two layouts, both with no app framework:

- **Layout P, plain package.** A package whose `R/` holds the app, with an exported function that returns `shiny::shinyApp(...)`, plus a root `app.R` for deployment. This is Mastering Shiny's recommendation [S1].
- **Layout S, plain `app.R` with sourced files.** A directory with `app.R`, an `R/` folder of helpers and modules, and `www/`. No `DESCRIPTION`. Shiny sources `R/*.R` itself [S3][S4].

Status facts for both: **not a package.** The guidance relied on instead:

| Document | Version or date |
|---|---|
| Mastering Shiny (Wickham) | O'Reilly print April 2021; online repo last commit 2026-02-03 [S13][S15] |
| R Packages 2e (Wickham, Bryan) | O'Reilly print June 2023; online repo last commit 2026-06-04 [S14][S16] |
| shiny (R) | 1.14.0, CRAN 2026-06-21; reference pages read at 1.14.0 [S2] |
| Shiny "App formats" article | dated 2017-06-28 (over 2 years old) [S3] |
| shinytest2 | 0.5.1, CRAN 2026-02-25 [S9] |
| renv | reference read at 1.3.0 [S12] |
| shiny (Python) | 1.8.0, PyPI 2026-09-13 [S17] |

Golem appears in neither Mastering Shiny chapter read here [S1].

---

## Layout P: plain R package with Shiny inside

### What it is
Mastering Shiny's three steps: move the app into `R/`, wrap it in a function ending in `shinyApp(ui, server, ...)`, add a `DESCRIPTION` [S1]. table-explorer already has this shape: `R/run_app.R` builds `shiny::shinyApp(ui = app_ui, server = app_server)`. Only the `golem::with_golem_options()` wrapper around it is framework code.

### What it generates or requires
Nothing is generated. The project maintains by hand:

- **Entry point.** An exported launcher, here `run_app()`, and a root `app.R` for hosting containing `pkgload::load_all(".")` then the launcher. That file must not sit in `R/`, which would cause "an infinite loop when loading" [S1]. table-explorer's `app.R` already does this.
- **Autoload clash.** A root `app.R` next to `R/` triggers Shiny's own `R/` autoloading (default since shiny 1.5.0) [S4], and since 1.6.0 `runApp()` warns when run in a package directory; since 1.8.1 an `R/_disable_autoload.R` file silences that warning [S5]. table-explorer has no such file.
- **Static assets.** `www/` is only served automatically for app directories. A package must call `addResourcePath(prefix, directoryPath)`, which the docs describe as "primarily intended for package authors" [S6], with `system.file("app/www", package = ...)`. `inst/` contents are copied to the installed package's top level, and `load_all()` shims `system.file()` to the source tree [S7]. table-explorer already does this in `run_app.R`.
- **Release hygiene.** `.Rbuildignore` for `app.R`, `dev/`, `docs/`, `_scratch/` and the other root files; R Packages 2e calls `inst/` "the opposite of `.Rbuildignore`" [S7]. What `R CMD check` and CRAN require is Agent C's subject.

### Runtime vs dev-time dependencies
Runtime: `shiny` and the package's own Imports; no framework package. Hosting via the root `app.R` adds `pkgload` at runtime [S1]; table-explorer lists `pkgload` only in Suggests. Dev-time: testthat, roxygen2, optionally shinytest2.

### Config handling
None provided. `shiny.maxRequestSize` defaults to 5 MB and is a global `options()` setting [S8]. R Packages 2e asks package functions that change options to restore them, via `withr::local_options()` or `on.exit()` [S10]. Restoring on exit from `run_app()` would likely undo the option before the app serves a request, since `shinyApp()` returns an object that runs later `[unverified]`; the hand-written alternative is setting it in `shinyApp(onStart = ...)`, a documented argument [S11], and restoring it with `onStop()` `[unverified]` for the pattern. Environment-specific values (dev vs production) would be plain R or `Sys.getenv()`; there is no config file reader.

### Testing story
Mastering Shiny: "testthat requires turning your app into a package" [S18]. Tests in `tests/testthat/` see exported and unexported functions through `devtools::test()` or `tests/testthat.R` [S19]. `shiny::testServer()` covers module servers [S18]; table-explorer's tests already use it. shinytest2 accepts an app directory, an app object or a function such as `run_app` in `AppDriver$new()`, and advises against calling `test_app()` from package tests [S9a].

### Fit with each shipping route
- **R package:** native; this layout is the route.
- **Positron extension:** not researched here (Agent C). Whether structure matters is `[unverified]`.
- **Posit Connect Cloud:** select `app.R` as primary file and commit a `manifest.json` from `rsconnect::writeManifest()` [S20][S21]. Whether the manifest captures the package's `DESCRIPTION` Imports when `app.R` calls `load_all()` is `[unverified]`.

### Python counterpart
See the shared section below.

### renv interplay
A `DESCRIPTION` allows renv's "explicit" snapshot, which captures only packages listed there [S12].

### Notable limits
The launcher, asset path, option handling and autoload guard are all hand-maintained, but each is a few lines and most exist already here.

---

## Layout S: plain `app.R` with sourced files

### What it is
A Shiny app directory. Since shiny 1.5.0, `loadSupport()` runs automatically, evaluating `global.R` then top-level `R/*.R` files in alphabetical order; nested folders are ignored [S3][S4]. No explicit `source()` calls are needed.

### What it generates or requires
- **Entry point.** `app.R` returning `shinyApp(ui, server)` [S3]. Nothing else; it is also the deploy entry.
- **Static assets.** `www/` next to `app.R` is served at `/` automatically [S6]. No `addResourcePath()` needed.
- **Code organisation.** Load order is alphabetical [S4], so cross-file dependencies at load time must respect file names `[unverified]` as a practical risk.

For table-explorer this means moving `inst/app/www/` to `www/`, dropping `DESCRIPTION`, `NAMESPACE` and roxygen, and replacing `run_app.R`.

### Runtime vs dev-time dependencies
Runtime: `shiny` plus whatever the code calls. No `pkgload`. Nothing records the dependency list except the code itself.

### Config handling
Plain `options(shiny.maxRequestSize = ...)` in `app.R` or `global.R` [S8]. The process belongs to the app, so the package rule on restoring options [S10] does not apply. No config file reader.

### Testing story
Weaker. Mastering Shiny's testthat workflow assumes a package [S18]. shinytest2 supports app directories: `test_app()` wraps `testthat::test_dir()` over `tests/testthat` inside the app [S9b], and `local_app_support()`, `with_app_support()` and `load_app_support()` load `R/` and `global.R` into the test environment [S9c]. The existing `tests/testthat/setup.R` already carries a hand-written fallback that sources `R/` files, which shows the cost.

### Fit with each shipping route
- **R package:** not available; it is not a package.
- **Positron extension:** not researched here (Agent C); `[unverified]`.
- **Posit Connect Cloud:** native shape: `app.R` as primary file plus `manifest.json` [S20][S21].

### Python counterpart
See below.

### renv interplay
No `DESCRIPTION`, so renv's "implicit" snapshot, inferring packages from code via `renv::dependencies()` [S12].

### Notable limits
No namespace, no documented exports, no `R CMD check`, and test setup must load code by hand.

---

## Python counterpart (both layouts)

Plain Shiny for Python, no framework. Two syntaxes: Core (`app = App(app_ui, server)`) and Express; the docs say Core's separation of UI and server is easier to restructure "as app UIs grow larger" [S22]. `App(ui, server, *, static_assets=None, ...)` serves a directory at `/`, the counterpart of `www/` [S23]. No upload size argument appears in `App()` [S23]. The Modules page defines modules with `@module.ui` and `@module.server` but gives no multi-file layout [S24]. Tests use pytest, Playwright, `shiny.playwright` controllers and `shiny.pytest.create_app_fixture` [S25]. Layout S maps closely onto a multi-file `app.py`; Layout P's Python analogue would be a Python package, which is Agent C's question 5.

## What could not be verified

- Whether restoring `shiny.maxRequestSize` on exit from `run_app()` defeats it, and the `onStart`/`onStop` pattern.
- Whether `rsconnect::writeManifest()` captures `DESCRIPTION` Imports for a package deployed via `load_all()`.
- Positron extension fit for either layout (Agent C).
- Alphabetical load order as a practical risk in Layout S.
- No official file-layout guidance for multi-file Shiny for Python apps was found on the Modules page.

`[unverified]` claims remaining: 6.

## Sources

- [S1] Mastering Shiny, ch. 20 Packages: https://mastering-shiny.org/scaling-packaging.html
- [S2] shiny on CRAN: https://cran.r-project.org/package=shiny
- [S3] Shiny App formats article (2017-06-28): https://shiny.posit.co/r/articles/build/app-formats/
- [S4] `loadSupport()` reference: https://shiny.posit.co/r/reference/shiny/latest/loadsupport.html
- [S5] shiny NEWS (1.4.0, 1.6.0, 1.8.1): https://raw.githubusercontent.com/rstudio/shiny/main/NEWS.md
- [S6] `addResourcePath()` reference: https://shiny.posit.co/r/reference/shiny/latest/resourcepaths.html
- [S7] R Packages 2e, Other components (`inst/`): https://r-pkgs.org/misc.html
- [S8] Shiny options reference (`shiny.maxRequestSize`): https://shiny.posit.co/r/reference/shiny/latest/shinyoptions.html
- [S9] shinytest2 on CRAN: https://cran.r-project.org/package=shinytest2
- [S9a] shinytest2, Using in a package: https://rstudio.github.io/shinytest2/articles/use-package.html
- [S9b] `test_app()`: https://rstudio.github.io/shinytest2/reference/test_app.html
- [S9c] App support functions: https://rstudio.github.io/shinytest2/reference/app_support.html
- [S10] R Packages 2e, Respecting the R landscape: https://r-pkgs.org/code.html#sec-code-r-landscape
- [S11] `shinyApp()` reference: https://shiny.posit.co/r/reference/shiny/latest/shinyapp.html
- [S12] renv `snapshot()` types: https://rstudio.github.io/renv/reference/snapshot.html
- [S13] Mastering Shiny print edition: https://www.oreilly.com/library/view/-/9781492047377/
- [S14] R Packages 2e print edition: https://www.oreilly.com/library/view/r-packages-2nd/9781098134938/
- [S15] Mastering Shiny repo commits: https://api.github.com/repos/hadley/mastering-shiny/commits?per_page=1
- [S16] R Packages repo commits: https://api.github.com/repos/hadley/r-pkgs/commits?per_page=1
- [S17] shiny on PyPI: https://pypi.org/project/shiny/
- [S18] Mastering Shiny, ch. 21 Testing: https://mastering-shiny.org/scaling-testing.html
- [S19] R Packages 2e, Testing basics: https://r-pkgs.org/testing-basics.html
- [S20] Connect Cloud, Deploy a Shiny app with R: https://docs.posit.co/connect-cloud/how-to/r/shiny-r.html
- [S21] Connect Cloud, manifest.json: https://docs.posit.co/connect-cloud/how-to/r/dependencies.html
- [S22] Shiny for Python, Express vs Core: https://shiny.posit.co/py/docs/express-vs-core.html
- [S23] Shiny for Python, `App`: https://shiny.posit.co/py/api/core/App.html
- [S24] Shiny for Python, Modules: https://shiny.posit.co/py/docs/modules.html
- [S25] Shiny for Python, End-to-end testing: https://shiny.posit.co/py/docs/end-to-end-testing.html
