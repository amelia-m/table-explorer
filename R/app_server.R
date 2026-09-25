# ============================================================
# app_server.R - Main Application Server
# ============================================================

#' @noRd
app_server <- function(input, output, session) {
  # ── Shared mutable state ─────────────────────────────────────
  all_tables_rv <- reactiveVal(list())
  rename_log_rv <- reactiveVal(data.frame(
    object_type = character(),
    source = character(),
    original_name = character(),
    cleaned_name = character(),
    stringsAsFactors = FALSE
  ))
  schema_rels_rv <- reactiveVal(list())
  table_meta_rv <- reactiveVal(list())
  false_positives_rv <- reactiveVal(character(0))
  conf_overrides_rv <- reactiveVal(list())

  # FK detection cache (mutable env, shared across modules)
  fk_cache <- new.env(parent = emptyenv())
  fk_cache$result <- list()
  fk_cache$scanned_sig <- character(0)
  fk_cache$handled_id <- NULL

  # ── Upload module (includes manual override section) ─────────
  upload_out <- mod_upload_server(
    "upload",
    all_tables_rv,
    rename_log_rv,
    schema_rels_rv,
    table_meta_rv,
    fk_cache
  )
  manual_rels_rv <- upload_out$manual_rels_rv

  # ── Database connection module ───────────────────────────────
  mod_db_connect_server(
    "db",
    all_tables_rv,
    rename_log_rv,
    schema_rels_rv,
    table_meta_rv
  )

  # ── Detection module (returns settings + strategy) ───────────
  detection <- mod_detection_server("detection", all_tables_rv, fk_cache)

  # ── PK detection reactives ───────────────────────────────────
  pk_map_rv <- reactive({
    tbls <- all_tables_rv()
    req(length(tbls) > 0)
    method <- if (detection$detect_method() == "manual") {
      "both"
    } else {
      detection$detect_method()
    }
    setNames(
      lapply(names(tbls), function(t) detect_pks(tbls[[t]], t, method)),
      names(tbls)
    )
  })

  composite_pk_map_rv <- reactive({
    tbls <- all_tables_rv()
    if (!detection$enable_composite_pk()) {
      return(setNames(vector("list", length(tbls)), names(tbls)))
    }
    req(length(tbls) > 0)
    setNames(
      lapply(names(tbls), function(t) detect_composite_pks(tbls[[t]], t)),
      names(tbls)
    )
  })

  # ── FK detection with incremental cache ──────────────────────
  # fk_cache$result holds every relationship found so far and
  # fk_cache$scanned_sig the signature of each table when it was scanned.
  # Scans only run for a new scan request: scope "all" rescans everything,
  # scope "new" compares only unscanned tables against the rest. Removing a
  # table just filters its relationships out of the cached result.
  auto_rels_rv <- reactive({
    tbls <- all_tables_rv()
    request <- detection$scan_request_rv()
    settings <- detection$detection_settings_rv()
    req(length(tbls) > 0)
    current <- names(tbls)

    cached_for <- function(keep) {
      Filter(
        function(r) r$from_table %in% keep && r$to_table %in% keep,
        fk_cache$result
      )
    }

    if (
      is.null(request) ||
        is.null(settings) ||
        identical(request$id, fk_cache$handled_id)
    ) {
      return(cached_for(current))
    }
    fk_cache$handled_id <- request$id

    to_scan <- if (identical(request$scope, "new")) {
      tables_needing_scan(tbls, fk_cache$scanned_sig)
    } else {
      current
    }
    if (length(to_scan) == 0) {
      return(cached_for(current))
    }
    # Relationships among already-scanned, unchanged tables are kept as is
    kept <- if (identical(request$scope, "new")) {
      cached_for(setdiff(current, to_scan))
    } else {
      list()
    }

    naming_only <- identical(request$strategy, "naming_only")
    method <- if (naming_only) "naming" else settings$method
    min_conf <- settings$min_conf %||% "medium"
    flags <- if (naming_only) {
      list(
        naming = TRUE,
        value_overlap = FALSE,
        cardinality = FALSE,
        format = FALSE,
        distribution = FALSE,
        null_pattern = FALSE
      )
    } else {
      list(
        naming = isTRUE(settings$naming),
        value_overlap = isTRUE(settings$value_overlap),
        cardinality = isTRUE(settings$cardinality),
        format = isTRUE(settings$format),
        distribution = isTRUE(settings$distribution),
        null_pattern = isTRUE(settings$null_pattern)
      )
    }

    sampled_tbls <- lapply(tbls, function(df) {
      if (nrow(df) > 10000) {
        set.seed(42)
        df[sample(nrow(df), 10000), , drop = FALSE]
      } else {
        df
      }
    })
    names(sampled_tbls) <- names(tbls)

    for (nm in names(sampled_tbls)) {
      df <- sampled_tbls[[nm]]
      if (ncol(df) > 60) {
        id_cols <- grep(
          "(_id|_key|id$|key$|_code|_num)",
          names(df),
          value = TRUE
        )
        other_cols <- setdiff(names(df), id_cols)
        keep <- union(id_cols, head(other_cols, 60 - length(id_cols)))
        sampled_tbls[[nm]] <- df[, keep, drop = FALSE]
      }
    }

    scan_label <- if (identical(request$scope, "new")) {
      sprintf(
        "%d new of %d tables",
        length(to_scan),
        length(sampled_tbls)
      )
    } else {
      paste0(length(sampled_tbls), " tables")
    }

    found <- withProgress(
      message = "Detecting relationships...",
      value = 0.1,
      {
        incProgress(0.1, detail = paste0(scan_label, ", sampling..."))
        tryCatch(
          {
            r <- detect_fks(
              sampled_tbls,
              method,
              min_conf,
              flags,
              progress_fn = function(i, n, tname) {
                setProgress(
                  value = 0.2 + 0.75 * (i - 1) / n,
                  detail = sprintf("table %d of %d: %s", i, n, tname)
                )
              },
              focus_tables = if (identical(request$scope, "new")) to_scan,
              existing = kept
            )
            setProgress(
              value = 1,
              detail = paste0("Found ", length(r), " relationship(s)")
            )
            if (isTRUE(attr(r, "truncated"))) {
              showNotification(
                paste0(
                  "Relationship scan hit its comparison limit, so some ",
                  "tables were not fully compared. Try a quick scan ",
                  "(naming only) or fewer tables."
                ),
                type = "warning",
                duration = 12
              )
            }
            r
          },
          error = function(e) {
            showNotification(
              paste0("Relationship detection error: ", conditionMessage(e)),
              type = "error",
              duration = 8
            )
            NULL
          }
        )
      }
    )

    # On error keep the previous results and leave the tables unscanned
    if (is.null(found)) {
      return(cached_for(current))
    }

    sig <- vapply(tbls, table_signature, character(1))
    if (identical(request$scope, "new")) {
      prev_sig <- fk_cache$scanned_sig %||% character(0)
      prev_sig <- prev_sig[intersect(names(prev_sig), setdiff(current, to_scan))]
      fk_cache$scanned_sig <- c(prev_sig, sig[to_scan])
    } else {
      fk_cache$scanned_sig <- sig
    }
    fk_cache$result <- sort_rels(c(kept, found))
    fk_cache$result
  })

  # ── Combined relationships ────────────────────────────────────
  rel_key <- function(r) {
    paste(r$from_table, r$from_col, r$to_table, r$to_col, sep = "|")
  }

  all_rels_rv <- reactive({
    raw <- c(auto_rels_rv(), manual_rels_rv(), schema_rels_rv())
    suppressed <- false_positives_rv()
    overrides <- conf_overrides_rv()
    filtered <- Filter(function(r) !rel_key(r) %in% suppressed, raw)
    lapply(filtered, function(r) {
      k <- rel_key(r)
      if (k %in% names(overrides)) {
        r$confidence <- overrides[[k]]
        conf_rank <- c(low = 0.3, medium = 0.7, high = 0.95)
        r$score <- conf_rank[[r$confidence]]
      }
      r
    })
  })

  # ── Visible tables/relationships (view-only filter) ─────────
  # Hiding empty tables affects the ERD, Table Details and Relationships
  # views only; detection and export still use every table.
  visible_tables_rv <- reactive({
    tbls <- all_tables_rv()
    if (upload_out$hide_empty_tables()) {
      tbls <- Filter(function(df) nrow(df) > 0, tbls)
    }
    tbls
  })

  visible_rels_rv <- reactive({
    keep <- names(visible_tables_rv())
    Filter(
      function(r) r$from_table %in% keep && r$to_table %in% keep,
      all_rels_rv()
    )
  })

  # ── has_tables output (used by conditionalPanel in ERD tab) ──
  output$has_tables <- reactive({
    if (length(all_tables_rv()) > 0) "true" else "false"
  })
  outputOptions(output, "has_tables", suspendWhenHidden = FALSE)

  # ── Module servers ────────────────────────────────────────────
  mod_erd_server(
    "erd",
    visible_tables_rv,
    visible_rels_rv,
    pk_map_rv,
    composite_pk_map_rv
  )

  mod_table_details_server(
    "table_details",
    visible_tables_rv,
    pk_map_rv,
    composite_pk_map_rv,
    visible_rels_rv
  )

  mod_relationships_server(
    "relationships",
    visible_tables_rv,
    visible_rels_rv,
    false_positives_rv,
    conf_overrides_rv
  )

  mod_name_changes_server("name_changes", rename_log_rv)

  mod_export_server(
    "export",
    all_tables_rv,
    all_rels_rv,
    pk_map_rv,
    composite_pk_map_rv,
    manual_rels_rv,
    schema_rels_rv,
    detect_method = detection$detect_method,
    min_confidence = reactive(
      detection$detection_settings_rv()$min_conf %||% "medium"
    )
  )
}
