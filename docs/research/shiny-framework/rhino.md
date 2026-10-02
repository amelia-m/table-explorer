# rhino (and Tapyr)

Agent B2. Researched 2026-10-02. Covers rhino and its Python counterpart only.

## What it is

rhino is Appsilon's framework for "enterprise" Shiny apps in R. It combines a fixed directory layout, `box` modules instead of `library()`, renv, linting and formatting, Sass and JavaScript bundling (via Node.js), testthat unit tests and Cypress end-to-end tests, all driven by `rhino::` functions [1][2].

**A rhino app is not an R package.** rhino's own docs say so directly: "Rhino apps are not R packages", contrasting this with golem [3]. The generated project has no `DESCRIPTION`, no `R/` and no `NAMESPACE` [4]. The only statement that a rhino app can later become a package is an Appsilon blog post (opinion, 2022-05-19): "There is no such limit if you want to develop an app using Rhino, but later compile it as a package" [5]. It gives no method, and nothing in rhino's docs, FAQ or how-to list describes packaging a rhino app [6][7]. The one packaging-related issue found, #461 (open since 2023-06-01), is about a `DESCRIPTION` in a *parent* directory breaking `test_r()`, not about the app itself being a package [8].

## Status facts

| Fact | rhino | Source |
|---|---|---|
| Current release | 1.12.0, 2026-06-10 (CRAN) | [9][10] |
| Last GitHub commit | 2026-06-10 (post-release merge, PR #657) | [11] |
| Open issues | 78 issues and 5 PRs (API count 83), checked 2026-10-02 | [2][12] |
| Archived | No | [12] |
| Maintainer | Jakub Nowicki (Appsilon); older CRAN releases listed Kamil Zyla | [9][13] |
| License | LGPL-3 | [9] |
| Imports | box (>= 1.1.3), box.linters (>= 0.10.5), box.lsp, callr, cli, config, covr (>= 3.6.5), fs, glue, lintr (>= 3.0.0), logger, purrr, renv, rstudioapi, sass, shiny, styler, testthat (>= 3.0.0), utils, withr, yaml | [9] |

Recent NEWS: 1.12.0 added `use_agents_md()`, `use_e2e_tests()`, `use_github_actions_ci()`, `covr_r()`/`covr_report()`, and raised Node.js to >= 20; 1.11.0 (2025-04-02) added `devmode()`, `auto_test_r()` and the `%<-%` operator; 1.10.0 (2024-09-10) added `box.lsp` and `box.linters` integration [10].

## What it generates or requires

`rhino::init()` creates [4]:

```
app/ (main.R, view/, logic/, static/, styles/main.scss, js/index.js)
tests/ (testthat/test-main.R, cypress/e2e/app.cy.js)
app.R  dependencies.R  renv.lock  rhino.yml  <name>.Rproj
```

1.12.0 also adds `AGENTS.md` [10]. `app.R` contains only `rhino::app()` and must not be edited or used as `global.R` [14]. `app()` reads `rhino.yml`, sets `box.path`, registers `app/static`, configures logging, loads `app/main.R` as a box module and returns `shiny::shinyApp()` [15]. UI and server code live in `app/view/` (Shiny modules); non-reactive code in `app/logic/` [14]. Every file imports what it uses with `box::use()` [7].

Migrating an existing app: move sources into `app/`, write `dependencies.R`, run `init()`, and set `legacy_entrypoint: app_dir` in `rhino.yml` so the old app runs while being refactored [16]. The guide covers `ui.R`/`server.R` apps only; it says nothing about migrating from golem or from a package [16]. For table-explorer this means dissolving `R/` into `app/view` and `app/logic` and rewriting every cross-file reference as a `box::use()` import.

## Runtime vs dev-time dependencies

There is no split. `app.R` calls `rhino::app()`, so a deployed app must install rhino, and installing rhino installs every Import above, including dev tooling (lintr, styler, testthat, covr, box.linters, box.lsp, renv, callr, rstudioapi) [9][14]. At run time `app()` itself uses shiny, box, config, logger, fs and cli [15]. Node.js (>= 20) is needed only for `build_js()`, `build_sass()` and the JS and Sass linters, not at run time; `sass: r` in `rhino.yml` avoids it for Sass [4][17].

## Config handling

Two files. `rhino.yml` holds framework options: `sass` (`node`, `r` or `custom`) and `legacy_entrypoint` [17]. App settings go in `config.yml`, read with the `config` package (`box::use(config)`, `config$get(...)`), with the environment chosen by `R_CONFIG_ACTIVE` in `.Renviron` and values overridable through `!expr Sys.getenv(...)` [18]. Shiny options such as `shiny.maxRequestSize` would be set in code or `.Rprofile`; the FAQ shows `.Rprofile` for `shiny.port` [7].

## Testing story

`test_r()` runs testthat tests in `tests/testthat` [1]. End-to-end tests default to Cypress (`test_e2e()`, Node.js) [1]. shinytest2 is supported as an alternative: install with `pkg_install()`, record tests as usual, optionally delete the package-style `tests/testthat.R`, and run them with `test_r()` [19]. `covr_r()` gives coverage [10]. Because code lives in box modules rather than a package namespace [7], tests import the module under test with `box::use()` (inferred from the box design; the generated `test-main.R` was not read). The documented runner is `test_r()`, not `testthat::test_local()` (table-explorer's current command) [19].

## Fit with each shipping route

- **Installable R package:** not supported by design [3]. Getting there means adding `DESCRIPTION`, `R/` and `inst/` by hand and reconciling box modules with a package namespace; no rhino doc describes it, and the only claim it is possible is a 2022 blog opinion [5].
- **Positron extension:** rhino's docs do not mention Positron or extensions [6]. `box.lsp` autocomplete is documented for VS Code and Vim only [20]. Whether the extension mechanism cares about app structure is Agent C's subject; nothing rhino-specific was found.
- **Posit Connect Cloud:** rhino's FAQ says to deploy "the same as in the case of a regular Shiny app" [7], and every rhino app carries `app.R` plus `renv.lock` [4]. rhino's docs never mention Connect Cloud by name; they include a Hugging Face guide [6]. That an `app.R` plus `renv.lock` repo deploys to Connect Cloud is `[unverified]` here (see Agent C).

## Python counterpart: Tapyr

Confirmed to exist. Tapyr is Appsilon's Shiny for Python template, described by Appsilon as bringing "Rhino-like capabilities" to Shiny for Python [21]. It is a GitHub template repository, not an installable framework: there is no `tapyr` library to depend on [22][23].

| Fact | Tapyr | Source |
|---|---|---|
| Repo | Appsilon/tapyr-template, template repo, MIT | [22] |
| Current release | v0.2.0, 2024-10-18 (moved Poetry to uv, Python 3.12) | [24] |
| Last commit | 2026-03-18 (README only); last code change 2024-10-29 | [25] |
| Open issues | 4 issues (API count 5 incl. PRs), checked 2026-10-02 | [22][23] |
| Archived | No | [22] |
| Maintainer | Appsilon (no named person found) | [23] |
| Runtime deps | loguru, pydantic-settings, python-dotenv, rich, shiny (>= 1.1.0); Python >= 3.10 | [26] |

Layout: `app.py` entry point, a package `tapyr_template/` with `logic/`, `view/` and `settings.py` (pydantic settings), `www/` for static files, `tests/`, a dev container [23][27]. The `logic`/`view` split mirrors rhino's `app/logic` and `app/view`. Dev tools: uv, ruff, pyright, pytest, Playwright, pre-commit, rsconnect-python [26]. Deployment documented to Posit Connect with `rsconnect deploy shiny` [23]; not Connect Cloud. Unlike a rhino app, Tapyr's code is a buildable Python package (hatchling) [26].

Shared structure with rhino is a naming convention, not shared code or tooling. table-explorer's Python version is Streamlit, so Tapyr would apply only after a port.

## renv interplay

renv is mandatory in rhino: "Rhino relies on renv to manage the R package dependencies" [28]. `dependencies.R` lists `library()` calls and `.renvignore` makes renv read only that file; `pkg_install()` and `pkg_remove()` edit `dependencies.R`, install and snapshot together [28]. Adopting rhino therefore also decides the open renv question.

## Notable limits or open issues

- Dev tooling becomes a runtime install (see above).
- box imports replace package namespaces; agents and humans must learn `box::use()` conventions. rhino ships an `AGENTS.md` template for this [29].
- Issue #461: a `DESCRIPTION` in a parent directory breaks `test_r()` (open) [8].
- Issue #518: `init()` installs from different repositories than recorded in `renv.lock` (open) [12].
- Autocomplete for box modules only in VS Code and Vim [20].

## What could not be verified

- Any rhino-documented method for shipping a rhino app as an R package: none found in docs, FAQ, how-to list or issues searched for "package DESCRIPTION".
- Connect Cloud deployment of a rhino app: no rhino or Posit source found. 1 `[unverified]` claim remains (Connect Cloud route).
- PyPI listing for Tapyr: page did not load; the repo itself shows it is a template, not a published library.

## Sources

1. https://appsilon.github.io/rhino/reference/index.html
2. https://github.com/Appsilon/rhino
3. https://appsilon.github.io/rhino/articles/explanation/what-is-rhino.html
4. https://appsilon.github.io/rhino/articles/tutorial/create-your-first-rhino-app.html
5. https://appsilon.com/post/should-you-develop-your-shiny-app-as-an-r-package (opinion, 2022-05-19)
6. https://appsilon.github.io/rhino/articles/index.html
7. https://appsilon.github.io/rhino/articles/faq.html
8. https://github.com/Appsilon/rhino/issues/461
9. https://cran.r-project.org/package=rhino
10. https://appsilon.github.io/rhino/news/index.html
11. https://api.github.com/repos/Appsilon/rhino/commits?per_page=3
12. https://github.com/Appsilon/rhino/issues?q=is%3Aissue+package+DESCRIPTION and https://api.github.com/repos/Appsilon/rhino
13. https://archive.linux.duke.edu/cran/web/packages/rhino/index.html (older CRAN mirror page)
14. https://appsilon.github.io/rhino/articles/explanation/application-structure.html
15. https://github.com/Appsilon/rhino/blob/main/R/app.R
16. https://appsilon.github.io/rhino/articles/how-to/migrate-app-to-rhino.html
17. https://appsilon.github.io/rhino/articles/explanation/rhino-yml.html
18. https://appsilon.github.io/rhino/articles/how-to/manage-secrets-and-environments.html
19. https://appsilon.github.io/rhino/articles/how-to/use-shinytest2.html
20. https://appsilon.github.io/rhino/articles/how-to/box-lsp.html
21. https://appsilon.com/introducing-tapyr (Appsilon announcement, 2024-04)
22. https://api.github.com/repos/Appsilon/tapyr-template
23. https://github.com/Appsilon/tapyr-template
24. https://api.github.com/repos/Appsilon/tapyr-template/releases
25. https://api.github.com/repos/Appsilon/tapyr-template/commits?per_page=3
26. https://github.com/Appsilon/tapyr-template/blob/main/pyproject.toml
27. https://github.com/Appsilon/tapyr-template/blob/main/app.py
28. https://appsilon.github.io/rhino/articles/explanation/renv-configuration.html
29. https://appsilon.github.io/rhino/articles/how-to/build-rhino-apps-with-llm-tools.html
