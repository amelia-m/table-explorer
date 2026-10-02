# golem (Agent B1)

Researched 2026-10-02. Scope: golem only, as the incumbent. Labels: "(inference)" marks reasoning from cited sources; `[unverified]` marks claims without a source.

## What it is

An opinionated framework from ThinkR in which a Shiny app is an R package: `R/app_ui.R`, `R/app_server.R`, `R/run_app.R`, `R/app_config.R`, `inst/golem-config.yml`, `inst/app/www/`, and `dev/` scripts that call golem's file generators [1][4]. Most of golem is dev-time tooling; the generated app calls a few golem functions at runtime.

## Status facts

| Fact | Value | Source |
|---|---|---|
| Current CRAN release | 1.0.1, published 2026-07-07 | [1] |
| Previous release | 1.0.0, tarball dated 2026-06-26 in the CRAN archive | [2] |
| CRAN checks (1.0.1) | OK on all 13 flavours, 2026-10-02 | [3] |
| Last GitHub commit | 2026-09-15 ("chore: CRAN Submission" and pkgdown rework, default branch `master`) | [5] |
| Open issues | 21 (issues only; repo API reports the same 21) | [6][7] |
| Archived | No | [7] |
| Maintainer | Colin Fay | [1] |
| Runtime dependencies (Imports) | attempt (>= 0.3.0), codetools, config, htmltools, rlang (>= 1.0.0), shiny (>= 1.5.0), utils, yaml; Depends R (>= 3.5.0) | [1] |

GitHub Releases stop at v0.5.1 (2024-08-28); 1.0.x exists only as CRAN releases and repo tags [8]. A gap between 0.5.1 (2024) and 1.0.0 (2026) is worth noting for maintenance health.

### What changed in 1.0

From NEWS [4]:
- `get_current_config()` now reads `GOLEM_CONFIG_PATH` or defaults to `inst/golem-config.yml`, and fails if missing instead of copying a skeleton file.
- Path arguments standardised to `golem_wd`; old `wd`/`path`/`pkg` are deprecated aliases whose values are ignored.
- Removed: `get_sysreqs()`, `use_recommended_deps()`, `add_rstudioconnect_file()`.
- `create_golem()` no longer calls `usethis::create_project()`; `add_*_files`/`use_*_files` fail if the target exists.
- New: `use_skills()`, `use_agent_skills()`, `use_claude_skills()`, `use_skill()` (Claude Code / AGENTS.md skill layouts); `add_github_action()`, `add_gitlab_ci()`; multi-stage Dockerfiles; `add_dockerfile_with_renv()` sets `golem.app.prod = TRUE` by default.
- Soft-deprecated: `add_dockerfile()`, `add_dockerfile_shinyproxy()`, `add_dockerfile_heroku()`, `browser_button()`.
- The golem repo itself switched to Air and ships a `CLAUDE.md`.
- 1.0.1 only fixes `favicon()`, which needed suggested-only `{fs}` at runtime and crashed minimal deployments [4].

None of the 1.0 breaking changes touch anything table-explorer calls (`with_golem_options()` only) (inference from [4] and `R/run_app.R`).

## What it generates or requires

Current templates [9][10][11][12]:
- `R/app_config.R`: `app_sys(...)`, a wrapper on `system.file(..., package = "<pkg>")`, and `get_golem_config(value, config, use_parent, file)`, which calls `config::get()` on `golem-config.yml`, choosing the environment from `GOLEM_CONFIG_ACTIVE`, then `R_CONFIG_ACTIVE`, then `"default"`.
- `R/run_app.R`: `run_app(onStart = NULL, options = list(), enableBookmarking = NULL, uiPattern = "/", ...)`, passing the four named arguments to `shinyApp()` and `...` to `with_golem_options(golem_opts = list(...))`.
- `R/app_ui.R`: `golem_add_external_resources()` calls `add_resource_path("www", app_sys("app/www"))`, `favicon()` and `bundle_resources(path = app_sys("app/www"), app_title = ...)`.
- `inst/golem-config.yml`: `default` (golem_name, golem_version, app_prod), `production`, and `dev: golem_wd: !expr golem::pkg_path()`.

`with_golem_options(app, golem_opts, maintenance_page = golem::maintenance_page, print = FALSE)` stores options in `app$appOptions$golem_options` and shows a maintenance page when `GOLEM_MAINTENANCE_ACTIVE` is `"TRUE"` [13][14].

## Runtime vs dev-time dependencies

Runtime: an installed or deployed app needs golem plus its Imports [1]. Beyond what table-explorer already needs (shiny, htmltools, rlang, utils), that adds golem, attempt (Imports only rlang [15]), config (Imports only yaml [16]), yaml and codetools (inference). codetools ships with R as a recommended package `[unverified]`.

Dev-time: the generators (`add_module()`, `add_fct()`, `add_utils()`, `use_recommended_tests()`, the `add_dockerfile*` family, deployment file helpers) live in golem and its Suggests (attachment, usethis, dockerfiler, pkgload, rsconnect, renv and more) [1]. They are needed only on a developer machine.

## Config handling

`golem-config.yml` uses the `{config}` format and is read only through `get_golem_config()` in `R/app_config.R` [17]. The docs separate two mechanisms: `run_app(...)` arguments become golem options read by `get_golem_options()` at runtime, while the config file is for backend values and "will not be linked to the parameters passed to `run_app()`" [17]. Config values are not turned into R options automatically, and the docs warn that `app_prod` in the YAML and `options(golem.app.prod)` are "not automatically synchronized" [17]. `app_prod()`/`app_dev()` read `getOption("golem.app.prod")` [18]. So a `shiny.maxRequestSize` key in the YAML does nothing until code reads it and calls `options()` (inference from [17]).

## Testing story

- Helpers: `expect_shinytag()`, `expect_shinytaglist()`, `expect_html_equal()`, `expect_running(sleep, R_path = NULL)`; `expect_running()` only checks that the app launches and stays up [19].
- `use_recommended_tests()` writes a recommended test file plus spellcheck [20]. The file tests UI/server formals, `app_sys()`, `get_golem_config()`, the server via `shiny::testServer()`, and launch via `expect_running()` [21].
- `use_module_test()` scaffolds a module test [22].
- golem's docs do not mention shinytest2 [20]. Nothing in golem blocks it: shinytest2 works on any app object or directory (inference).
- table-explorer already uses `testServer()` in two test files and no golem test helpers (`git grep`).

## Fit with each shipping route

- **Installable R package:** native; a golem app is a package [1]. Cost: golem and its Imports become install dependencies. This route works for any package-shaped app, so golem does not enable it, it only adds weight. `add_positconnect_file()` adds `app.R` and `rsconnect` to `.Rbuildignore` [23], but CRAN readiness (I6, `.Rbuildignore`) is still manual.
- **Positron extension:** no golem tooling, docs or examples found. The only Positron mention in the repo is open issue #1185 (2025-01-23): golem apps ignore Positron's `"shiny.previewType": "external"` setting during development [24]. That is a dev-workflow gap, not a shipping blocker. Whether structure matters for an extension is Agent C's subject.
- **Posit Connect Cloud:** golem documents Posit Connect (self-hosted), shinyapps.io and Shiny Server, via `add_positconnect_file()`, `add_shinyappsio_file()`, `add_shinyserver_file()`, and `rsconnect::writeManifest()` for Git-backed deploys; it never mentions Connect Cloud [23][25]. The generated `app.R` is `pkgload::load_all(...)`, `options("golem.app.prod" = TRUE)`, `<pkg>::run_app()` [23], so pkgload must be in the deployed environment (inference). table-explorer's `app.R` already follows this pattern apart from the option line.

## Python counterpart

None found. Searched: ThinkR-open GitHub repositories with Python as language, and the web for a golem equivalent for Shiny for Python. The only ThinkR Python result is `talospy`, "A Template for Building Shiny Apps with Python" (cookiecutter and Poetry; created 2025-02-26, last push 2025-03-07, 0 stars, 5 open issues, docs "a work in progress") [26][27]. Its docs do not mention golem and describe no layout, so it is not counted as a counterpart.

## renv interplay

golem does not require renv. `add_dockerfile_with_renv()` (signature includes `lockfile = NULL`, `set_golem.app.prod = TRUE`) builds Docker images from a lockfile, with or without renv during development [28][25]. For Connect-style deploys, golem relies on `rsconnect` manifests, not on renv [25]. Two open issues mention renv, both Docker-related (#1096, #1188) [29]. Adopting renv is independent of golem (inference).

## Notable limits or open issues

- Runtime dependency on golem even when only `with_golem_options()` is used.
- Half-adoption is easy and silent: config, prod mode and resource helpers only work if `R/app_config.R` exists and is called (see below) [17].
- Dev-time preview in Positron (#1185) [24].
- No Connect Cloud, Positron or CRAN-release guidance in the docs [25].

## Wiring golem up in table-explorer

Current `main` (read directly): `R/run_app.R` takes only `...`, calls `shiny::addResourcePath("tableexplorer", system.file("app/www", package = "tableexplorer"))`, then `golem::with_golem_options()`. `R/tableexplorer-package.R:13` imports `with_golem_options` and `get_golem_options`. `inst/golem-config.yml` has `app_version` (not `golem_version`), `shiny.maxRequestSize: 104857600` and no `dev:` block. `app.R` lacks `options("golem.app.prod" = TRUE)`. There is no `R/app_config.R` and no `.Rbuildignore`. So C3, I5, I13, M9, M10 and M11 all hold on `main` as described in the backlog.

Steps from the current templates (described, not done):

1. **Add `R/app_config.R`** with `app_sys()` and `get_golem_config()` copied from the template, `package = "tableexplorer"` [9]. It calls `config::get()`, so `config` goes into `DESCRIPTION` Imports, or `R CMD check` notes an undeclared import (inference). Resolves I5 and the "wire it" branch of D1.
2. **Fix `inst/golem-config.yml`:** `app_version` to `golem_version`; add `dev: golem_wd: !expr golem::pkg_path()` [12]. Part of I5 and D1.
3. **Apply the upload limit (C3):** golem does not map YAML keys to options [17], so `run_app()` (or an `onStart`) must call `options(shiny.maxRequestSize = get_golem_config("shiny.maxRequestSize"))` (inference). This is the only step that changes behaviour users see.
4. **Template signature for `run_app()` (M10):** `onStart`, `options`, `enableBookmarking`, `uiPattern`, `...` passed through to `shinyApp()` [10].
5. **Resource path (M11):** replace the raw `system.file()` call with `app_sys("app/www")`, optionally via `add_resource_path("tableexplorer", app_sys("app/www"))` [11][30]. Keeping the prefix `tableexplorer` leaves the five `tableexplorer/...` asset URLs in `R/app_ui.R` unchanged. Switching to `bundle_resources()` is optional: it bundles CSS and JS from `inst/app/www` with all files included by default and no documented order [31], while `app_ui.R` loads vendor scripts in a set order (inference: a risk worth testing, not a requirement).
6. **`app.R` (I13, D3):** add `options("golem.app.prod" = TRUE)` as in the generated deployment file [23].
7. **Unused import (M9):** drop `get_golem_options` from the roxygen import, or start using golem options.
8. **Tests:** `use_recommended_tests()`'s file would cover `app_sys()` and `get_golem_config()` [21]; one test that `run_app()` sets `shiny.maxRequestSize` would pin C3.
9. **Not golem's job:** `.Rbuildignore` (I6). `add_positconnect_file()` and `add_rscignore_file()` would add some entries [23], but legacy root files, `app.py`, `dev/` and `tmp/` must be listed by hand.

Files touched: `R/app_config.R` (new), `R/run_app.R`, `R/tableexplorer-package.R`, `DESCRIPTION`, `inst/golem-config.yml`, `app.R`, one test file, and optionally `R/app_ui.R`. The other branch of D1 (delete the YAML) leaves golem's footprint at one call, `with_golem_options()`, whose only runtime features here would be maintenance mode and golem options [13][14] (inference).

## What could not be verified

- The CRAN date of 1.0.0 is the archive tarball date, not a confirmed publication date [2].
- `codetools` shipping with R is `[unverified]`.
- No golem material on Posit Connect Cloud or Positron extensions exists to verify against.
- The order in which `bundle_resources()` emits files is undocumented [31].
- `[unverified]` claims remaining: 1.

## Sources

1. https://cran.r-project.org/package=golem
2. https://cran.r-project.org/src/contrib/Archive/golem/
3. https://cran.r-project.org/web/checks/check_results_golem.html
4. https://github.com/ThinkR-open/golem/blob/master/NEWS.md
5. https://api.github.com/repos/ThinkR-open/golem/commits?per_page=3
6. https://api.github.com/search/issues?q=repo:ThinkR-open/golem+type:issue+state:open
7. https://api.github.com/repos/ThinkR-open/golem
8. https://github.com/ThinkR-open/golem/releases
9. https://github.com/ThinkR-open/golem/blob/master/inst/shinyexample/R/app_config.R
10. https://github.com/ThinkR-open/golem/blob/master/inst/shinyexample/R/run_app.R
11. https://github.com/ThinkR-open/golem/blob/master/inst/shinyexample/R/app_ui.R
12. https://github.com/ThinkR-open/golem/blob/master/inst/shinyexample/inst/golem-config.yml
13. https://thinkr-open.github.io/golem/reference/with_golem_options.html
14. https://github.com/ThinkR-open/golem/blob/master/R/with_opt.R
15. https://cran.r-project.org/package=attempt
16. https://cran.r-project.org/package=config
17. https://thinkr-open.github.io/golem/articles/e-config.html
18. https://thinkr-open.github.io/golem/reference/prod.html
19. https://thinkr-open.github.io/golem/reference/testhelpers.html
20. https://thinkr-open.github.io/golem/reference/use_recommended.html
21. https://github.com/ThinkR-open/golem/blob/master/inst/utils/test-golem-recommended.R
22. https://thinkr-open.github.io/golem/reference/index.html
23. https://github.com/ThinkR-open/golem/blob/master/R/add_rstudio_files.R and https://thinkr-open.github.io/golem/reference/rstudio_deploy.html
24. https://github.com/ThinkR-open/golem/issues/1185
25. https://thinkr-open.github.io/golem/articles/c-deploy.html
26. https://github.com/ThinkR-open/talospy
27. https://thinkr-open.github.io/talospy/
28. https://thinkr-open.github.io/golem/reference/dockerfiles.html
29. https://github.com/ThinkR-open/golem/issues/1096 and https://github.com/ThinkR-open/golem/issues/1188
30. https://thinkr-open.github.io/golem/reference/add_resource_path.html
31. https://thinkr-open.github.io/golem/reference/bundle_resources.html
