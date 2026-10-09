# Shiny framework options for table-explorer: synthesis

Written 2026-10-02 by the dispatching session, from the five agent reports in
this folder (`leprechaun.md`, `golem.md`, `rhino.md`, `no-framework.md`,
`shipping-and-python.md`) and the contract (`contract.md`). Every report
passed the contract's acceptance checks: 2 spot-checked sources each, and
every named leprechaun, golem and rhino function checked against the
package's exports or reference index.

This is input for a decision Amelia is still weighing. It recommends only
where one option clearly wins; elsewhere it sets out the trade-off.

## Decisions

- 2026-10-02, Amelia: leprechaun, rhino and a plain `app.R` are rejected.
- 2026-10-02, Amelia: **drop golem for now; the app is a plain package.**

### Why golem was dropped

- **It was never really used.** Its only runtime role was one
  `golem::with_golem_options()` call around `shinyApp()`. The config file
  was never read (so the 100 MB upload limit in it never applied), one
  import was unused, and none of its helpers were called.
- **Finishing the adoption would have cost more than removing it:** about 8
  files of wiring, against about 6 for removal. Its config would still not
  have set Shiny options by itself.
- **None of the three shipping routes needs it.** A plain package serves the
  R package, Positron extension and Connect Cloud routes equally well.
- **A plain package is the most widely known layout,** and it leaves no
  half-adopted conventions for people or agents to trip over.
- **The runtime saving is small, and was not the reason:** 4 packages
  (golem, attempt, config, codetools), 2.5 MB, and about 0.3 s at startup,
  measured on this machine.

### What changed

- `R/run_app.R` builds the app with plain `shinyApp()`, passing through
  `onStart`, `options`, `enableBookmarking` and `uiPattern` (backlog M10).
- It sets `shiny.maxRequestSize` (default 100 MB, argument
  `max_request_size`) when the app starts, and restores it when the app
  stops (C3).
- It stops with a clear message if the static files can't be found (M11).
- golem is gone from `DESCRIPTION`, `NAMESPACE` and the package
  documentation (M9); `inst/golem-config.yml` is deleted (I5, D1: "delete
  it"; I13 moot). The golem lines in `dev/`, `app.R` and `README.md` are
  updated.
- New `R/_disable_autoload.R`, so Shiny doesn't source `R/` by itself when
  `app.R` runs.
- New `tests/testthat/test-run_app.R`: 3 tests, which failed on the golem
  version and pass now.
- `renv.lock` lost golem, attempt, config and codetools.

### When golem would be worth bringing back

Re-adding it costs about what wiring it up would have: an
`R/app_config.R`, a config file, the template `run_app()`, and golem in
Imports. Reconsider if any of these become true:

1. **Settings differ between environments.** Dev, staging and production
   need different values (upload limits, feature switches, database
   defaults), and switching them by environment variable with golem's
   config profiles beats hand-written `Sys.getenv()` code.
2. **A maintenance page is needed.** A hosted copy has users who should see
   "down for maintenance" during updates without a redeploy.
3. **New modules are added often,** and `add_module()` and similar
   generators would save real time over copying an existing module.
4. **Container or CI deployment.** golem's Dockerfile generators
   (including a renv-based one) and CI templates would be the quickest
   route.
5. **More contributors who know golem.** Working with a team that expects
   golem's layout and conventions.
6. **golem gains support for the routes in use here:** Connect Cloud
   deployment files, Positron extension support, or a fix for issue #1185
   (golem apps ignore Positron's external preview setting).

Golem's runtime weight is not a factor either way.

## The short version

- **Two options fit table-explorer: golem with its config wired up, or a
  plain package that drops golem.** Both keep every shipping route open.
- **leprechaun loses to a plain package here.** Its value is scaffolding a
  new app, and this one already has the shape. Adopting it would mean
  renaming the entry points, taking on a dormant dependency, and an asset
  loader that would pick up the vendor scripts.
- **rhino rules out the R package route by design** ("Rhino apps are not R
  packages"), and its development tools become runtime installs.
- **A plain `app.R` rules out the R package route** and weakens testing.
- **Python compatibility does not separate the options much.** The Python
  version is Streamlit, so a shared structure would first need a port to
  Shiny for Python. Only rhino has a Python counterpart (the Tapyr
  template), and that shares a folder naming convention, not code or tools.

## Options compared

| Option | What it means here |
|---|---|
| **golem, wired** | Keep golem and finish the half-adoption: add `R/app_config.R`, fix `inst/golem-config.yml`, apply the upload limit (golem.md, "Wiring golem up") |
| **Plain package** | Remove the one `golem::with_golem_options()` call and the golem files; keep the package (no-framework.md, Layout P) |
| **leprechaun** | Re-scaffold the package with leprechaun and move the code into its layout |
| **rhino** | Rebuild as a rhino app: `app/view`, `app/logic`, `box::use()` imports |
| **Plain `app.R`** | Drop the package; an app directory with `R/` auto-sourced (no-framework.md, Layout S) |

## Options against shipping routes

Each cell gives whether the route works, its cost, and why.

| Option | R package (CRAN or r-universe) | Positron extension | Posit Connect Cloud |
|---|---|---|---|
| golem, wired | **Yes, native.** It is already a package. Cost: golem and its Imports (attempt, codetools, config, yaml) become install dependencies, and `.Rbuildignore` is still manual. | **Yes.** The extension calls `tableexplorer::run_app()` in the user's R session. golem has no Positron tooling, and open issue #1185 concerns dev preview only. | **Yes.** Root `app.R` with `pkgload::load_all()` plus a committed `manifest.json`. golem documents self-hosted Connect, not Connect Cloud. |
| Plain package | **Yes, native.** No framework dependency. `.Rbuildignore`, the asset path and the upload option are maintained by hand (a few lines each, mostly already present). | **Yes,** the same as golem: one exported function to call. | **Yes,** the same `app.R` plus `manifest.json`. |
| leprechaun | **Yes, native** after re-scaffolding. Whether the generated app passes `R CMD check` cleanly is untested. | **Yes,** as a package. No leprechaun tooling. | **Yes.** `add_app_file()` writes the same `load_all()` pattern. |
| rhino | **No.** Not a package by design, and no documented way to make one. | **Folder only:** the extension must know a path and call `shiny::runApp()`. Box-module tooling is documented for VS Code and Vim, not Positron. | **Yes, probably.** It has `app.R`, but Connect Cloud ignores its `renv.lock` and needs a `manifest.json` (unverified for rhino specifically). |
| Plain `app.R` | **No.** Not a package. | **Folder only,** as for rhino. | **Yes, native shape:** `app.R` plus `manifest.json`. |

Two of the routes do not separate the options. **Connect Cloud works with any
structure** that has an `app.R` entry point and a `manifest.json`
(shipping-and-python.md, section 3). **A Positron extension works with any
structure too**, because every documented mechanism runs code in the user's
own R session through `positron.runtime.executeCode()`. An exported function
is a cleaner contract than a folder path, but both work. **Only the R package
route constrains structure.**

## Combinations each option allows from one codebase

| Option | Package + extension + Connect Cloud | Extension + Connect Cloud only |
|---|---|---|
| golem, wired | Yes | Yes |
| Plain package | Yes | Yes |
| leprechaun | Yes | Yes |
| rhino | No (no package) | Yes (folder-based extension) |
| Plain `app.R` | No (no package) | Yes (folder-based extension) |

Serving all three needs, in any package option (shipping-and-python.md,
section 4):
1. an exported `run_app()` with assets found through `system.file()`;
2. a build-ignored root `app.R` and a committed `manifest.json`;
3. a `.Rbuildignore` covering every non-package file, the Python app
   included;
4. the extension kept outside the package;
5. a guarded use of every Suggests package.

## Ranked criteria

| Criterion | golem, wired | Plain package | leprechaun | rhino | Plain `app.R` |
|---|---|---|---|---|---|
| 1. Python compatibility | None found (ThinkR's `talospy` is unrelated and inactive) | Maps to plain Shiny for Python; no shared tooling | None found | Tapyr template (v0.2.0, last code change 2024-10-29): same `logic`/`view` naming, nothing shared | Closest to a multi-file plain `app.py` |
| 2. Migration cost | Moderate: about 8 files (golem.md lists them) | **Lowest:** remove one wrapper and the golem files; add the upload option and a `.Rbuildignore` | High: rename `app_ui`/`app_server`/`run_app`/`mod_*` to leprechaun's fixed names; re-check assets | **Highest:** dissolve `R/` into box modules and rewrite the tests | High: drop `DESCRIPTION` and `NAMESPACE`, move `www/`, rework the tests |
| 3. Maintenance health | Active: 1.0.1 (2026-07-07), last commit 2026-09-15 | Depends on shiny only (1.14.0, 2026-06-21) | **Dormant:** last CRAN release 2022-01-19; 9 open issues with no maintainer replies | Active: 1.12.0 (2026-06-10) | Depends on shiny only |
| 4. Testability | testthat plus `testServer()` as today; golem test helpers optional | testthat plus `testServer()` as today | As a package, but open issue #14 reports shinytest2 failing to start a leprechaun app | `test_r()` with box imports; shinytest2 supported; Cypress needs Node 20+ | **Weaker:** testthat assumes a package; shinytest2 app-support loaders instead |
| 5. Ease for agents | Standard package plus golem conventions; 1.0 adds Claude/AGENTS skill helpers | **Standard R package**, the most widely known layout | Package plus fixed names and regenerated "do not edit" files | box conventions to learn; ships an `AGENTS.md` template | Simple, but no namespace and load order by file name |
| 6. Runtime dependency weight | golem plus attempt, codetools, config, yaml | shiny and the app's own Imports | shiny, bslib, htmltools | **Heaviest:** rhino brings lintr, styler, testthat, covr, renv, box.linters, box.lsp and more | shiny only |

Criterion 5 is judgement, not measurement.

## Migration cost from today's state

What exists now: a golem-shaped package whose only golem call is
`with_golem_options()` (`R/run_app.R:11`). `R/run_app.R` already calls
`addResourcePath()` itself. `app.R` already uses `pkgload::load_all()`. The
tests already use `testServer()`.

- **Plain package:**
  - replace the wrapper with a plain `shinyApp()` and give `run_app()` the
    full signature;
  - set `shiny.maxRequestSize`;
  - delete `inst/golem-config.yml` and the golem `dev/` scripts;
  - drop golem from Imports and `NAMESPACE`;
  - add `.Rbuildignore` and `R/_disable_autoload.R`.

  About 6 files. No user-visible change apart from the upload limit, which
  is a fix.
- **golem, wired:** add `R/app_config.R`; fix the yaml (`golem_version`, a
  `dev:` block); set the upload option from config; adopt the template
  `run_app()` signature; use `app_sys()`; add `options("golem.app.prod" =
  TRUE)` to `app.R`; drop the unused import; add a test. About 8 files,
  plus `config` in Imports.
- **leprechaun:** scaffold into the existing package; rename entry points
  and modules to its fixed names; replace the asset handling. Its
  `serveAssets()` loads every `.js` and `.css` file in the installed
  package, the `inst/app/www/vendor/` scripts included, and three open
  issues concern assets. Edits may later be overwritten by
  `update_scaffold()`.
- **rhino:** a rewrite of the structure. The migration guide covers
  `ui.R`/`server.R` apps only, not packages or golem.
- **Plain `app.R`:** un-package the app and move the tests to shinytest2's
  app-support loaders. The hand-written fallback in
  `tests/testthat/setup.R` shows the cost.

## Backlog items by option

From `dev/code-review-backlog.md`. golem.md confirms all of C3, I5, I13, M9,
M10 and M11 still hold on `main`.

| Item | golem, wired | Plain package | leprechaun | rhino | Plain `app.R` |
|---|---|---|---|---|---|
| C3: upload limit never applied | Fixed by an explicit `options()` from config | Fixed by an explicit `options()` in `run_app()` or `onStart` | Same: explicit `options()` needed | Same: set in code or `.Rprofile` | Same: `options()` in `app.R` or `global.R` |
| I5: `golem-config.yml` inert | Resolved by wiring | Moot (file deleted) | Moot (`use_config()` replaces it) | Moot (`config.yml` replaces it) | Moot |
| I13: no `golem.app.prod` in `app.R` | Resolved (add the line) | Moot | Moot | Moot | Moot |
| M9: unused `get_golem_options` import | Resolved (drop it) | Moot | Moot | Moot | Moot |
| M10: `run_app()` takes only `...` | Resolved (template signature) | **Still applies:** fix by hand | Moot (`run(...)` passes through) | Moot | Moot |
| M11: `addResourcePath()` with an empty path | Resolved (`app_sys()`) | **Still applies:** guard by hand | Moot, but replaced by the `serveAssets()` risk | Moot (`app/static`) | Moot (`www/`) |
| D1: wire the yaml or delete it | **Wire it** | **Delete it** | Delete it | Delete it | Delete it |

**C3 needs code in every option.** No framework turns a config value into a
Shiny option by itself. golem's docs say the config "will not be linked to
the parameters passed to `run_app()`". So the upload-limit bug does not
argue for or against any framework.

## Trade-offs and recommendation

**Clear calls:**
- **Not leprechaun.** For an app that already exists in package form, a plain
  package gives everything leprechaun would, without the renames, the
  dormant dependency or the asset loader. leprechaun suits a new app
  started from nothing.
- **Not rhino, while the R package route stays open.** rhino is also the
  most expensive migration, and the heaviest at runtime. Reconsider only if
  the package route is dropped for good and a rhino-to-Tapyr pairing for a
  future Shiny for Python port matters more than everything else.
- **Not a plain `app.R`, while the package route stays open.** It gives up
  testthat's package workflow for no gain on the other two routes.

**The real choice, golem wired or a plain package.** Both serve all three
routes. The difference is whether golem's extras are worth a runtime
dependency and about 8 files of wiring:
- **For golem:** config profiles chosen by environment variable, a
  maintenance-mode page, the `add_module()` and Dockerfile generators, and
  the new agent-skill helpers.
- **For a plain package:** the lowest migration cost, the lightest runtime,
  the most widely known layout, and no framework half-adopted again. Two
  small backlog items (M10, M11) stay as hand fixes.

**Lean (judgement, not a clear win):** a plain package. golem has been
adopted in name only for the app's whole life: one call, an unread config
file, unused imports. That suggests its extras are not being missed. If
config profiles or the maintenance page turn out to matter, golem can be
re-added later at about the same cost as wiring it now.

## Findings that hold whatever is chosen

- **R version for Connect Cloud.** Connect Cloud supports R 4.0.0 to 4.6.0,
  and this machine builds on 4.6.1. A manifest written here names a version
  outside that range. What Connect Cloud then does is undocumented: a test
  deploy, or writing the manifest from R 4.6.0, settles it.
- **Connect Cloud does not use renv.** It reads `manifest.json`. So renv is
  not needed for that route, and the renv question is independent of the
  framework choice, except under rhino, which makes renv mandatory.
- **`pkgload` is in Suggests but runs at deploy time** (`app.R` calls
  `pkgload::load_all()`). Its capture into the manifest is unverified; move
  it to Imports or check the manifest.
- **`R/_disable_autoload.R` is missing.** Since shiny 1.6.0, `runApp()`
  warns when run in a package directory, and since 1.8.1 that file
  silences it.
- **`.Rbuildignore` is missing** (backlog I6). It is needed for any package
  release.
- **A Positron extension means the user has R and the package installed.**
  No extension bundling an R or Python app was found. Shinylive (webR) is
  the only no-install path, and the database drivers would very likely not
  work there.
- **Python:** Shiny for Python (1.8.0) has modules and an `App(...,
  static_assets=...)` counterpart to `www/`, but no official app-as-package
  guide. A cross-language structure starts with porting the Streamlit app,
  which is outside this research.

## What is still weak

- No test deploy to Connect Cloud was made. The R 4.6.1 question and
  whether `DESCRIPTION` Imports are captured via `load_all()` are both open.
- The extension route rests on Positron's documented API and a demo
  extension. Nobody has built one.
- leprechaun's generated app was not run through `R CMD check`, and its
  shinytest2 issue (#14) was not reproduced.
- Restoring `shiny.maxRequestSize` on exit from `run_app()` may undo it
  before the app serves a request; the `onStart` pattern is unverified.
- golem 1.0.0's exact CRAN date is the archive tarball date.
- `[unverified]` claims left in the reports: leprechaun 3, golem 1, rhino
  1, no framework 6, shipping 4.
