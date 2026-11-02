# make_answer_key.R - writes access_fixture_key.csv from the lists below.
#
# The lists are typed from the design in build_fixture.ps1, not read back from a
# built file, so the key can disagree with what got built. Only the *_clean
# columns are computed, by the same janitor calls mod_upload.R makes.
# Run: Rscript --vanilla make_answer_key.R   (from this folder)

long_name <- paste0("Long_Table_Name_", strrep("x", 48))
tbl <- function(name, rows, cols, pk = "", expect = "yes", note = "") {
  list(name = name, rows = rows, cols = cols, pk = pk, expect = expect, note = note)
}

tables <- list(
  tbl("tlk Status", 5, c("StatusID", "Status Label", "Sort#", "Is Active?"), "StatusID"),
  tbl("tlk_Region", 4, c("Code", "Region/Area", "Rate %"), "Code"),
  tbl("tlk Ship Method", 3, c("ID", "Method"), "ID"),
  tbl("tblCustomer", 12, c("CustomerID", "Customer Name", "StatusID", "RegionCode", "ReferredBy", "Balance", "Visits", "Score", "Ratio", "Is Member", "Joined", "Call Time", "Birth Date", "Homepage", "Notes", "Row Guid", "ZIP"), "CustomerID"),
  tbl("Customer Photo", 3, c("CustomerID", "Caption", "Photo"), "CustomerID"),
  tbl("Customer Profile", 5, c("CustomerID", "Email", "Phone", "2nd Phone"), "CustomerID"),
  tbl("Orders", 8, c("OrderNo", "CustomerID", "Select", "Order", "Date", "Group", "ShipMethodID", "Pay Type", "LegacyCustNo"), "OrderNo"),
  tbl("Order Line", 10, c("OrderNo", "LineNo", "Qty", "Unit Price"), "OrderNo|LineNo"),
  tbl("Line Note", 4, c("NoteID", "Ref Order", "Ref Line", "Note"), "NoteID"),
  tbl("Line Alloc", 3, c("AllocID", "Alloc Line", "Alloc Order", "Share"), "AllocID"),
  tbl("Warehouse", 3, c("WarehouseID", "Name"), "WarehouseID"),
  tbl("Empty Carrier", 0, c("CarrierID", "Carrier Name", "Active"), "CarrierID"),
  tbl("Shipment", 4, c("ShipmentID", "FromWarehouse", "ToWarehouse", "CarrierID"), "ShipmentID"),
  tbl("Store", 3, c("StoreID", "RegionCode", "HomeWarehouse"), "StoreID"),
  tbl("Legacy Code", 3, c("LegacyCode", "Meaning")),
  tbl("Legacy Use", 3, c("LegacyCode", "Used On")),
  tbl("Audit Log", 6, c("CustomerID", "Action")),
  tbl("Device", 3, c("DeviceGuid", "Label"), "DeviceGuid"),
  tbl("Device Log", 4, c("LogID", "DeviceGuid", "Reading"), "LogID"),
  tbl("Date Traps", 13, c("DateID", "Case Name", "Value", "Expected"), "DateID"),
  tbl("Number Traps", 5, c("NumID", "Case Name", "ByteV", "IntV", "LongV", "SingleV", "DoubleV", "CurrV", "DecV", "Expected"), "NumID"),
  tbl("Text Traps", 29, c("TextID", "Case Name", "Short Text", "Comp Text", "Long Text", "Expected Len", "Expected Hex"), "TextID"),
  tbl("Collide Cols", 2, c("RowID", "Item Code", "item_code", "ITEM-CODE", "ItemCode", "Item%", "Café Nº", "Naïve Field", "日本語", "#", "%", "NA"), "RowID"),
  tbl("Order Detail", 2, c("OrderNo", "Qty")),
  tbl("order_detail", 3, c("Order No", "Comment")),
  tbl("Order-Detail", 4, c("OrderNo", "Flag")),
  tbl("Customer's Notes", 1, c("CustomerID", "Author's Note")),
  tbl("Select", 1, c("From", "Where")),
  tbl("Reports/Monthly", 2, c("Month", "Total #")),
  tbl("Übersicht Bücher", 2, c("Büro Nr", "Titel")),
  tbl("顧客", 1, c("ID", "Label")),
  tbl(long_name, 1, "ID"),
  tbl("MSystem Parts", 2, c("PartNo", "RegionCode"), note = "negative case: a user table, name resembles MSys"),
  tbl("USystem Notes", 1, c("NoteNo", "Body"), note = "negative case: a user table, name resembles USys"),
  tbl("~Draft Table", 1, "DraftNo", note = "negative case: a user table, name begins with a tilde"),
  tbl("msys_lower", 1, "LowerNo", note = "negative case: lower case, the filter is case sensitive"),
  tbl("Hidden Table", 2, c("HiddenNo", "StatusID"), note = "hidden, still the user's data"),
  tbl("USysRibbons", 1, c("RibbonName", "RibbonXML"), expect = "no", note = "USys prefix is Access's own convention for app tables"),
  tbl("MSysUserMade", 1, "MadeNo", expect = "no", note = "true MSys prefix, made through DAO"),
  tbl("Flagged System", 1, "FlagNo", expect = "no", note = "carries the system object flag")
)

rel <- function(name, child, cols, parent, ref_cols, native) {
  lapply(seq_along(cols), function(i) {
    list(name = name, child = child, col = cols[[i]], parent = parent, ref = ref_cols[[i]], i = i - 1L, native = native)
  })
}
u <- "Übersicht Bücher"
rels <- c(
  rel("R01_status", "tblCustomer", "StatusID", "tlk Status", "StatusID", 0),
  rel("R02_region_unenforced", "tblCustomer", "RegionCode", "tlk_Region", "Code", 2),
  rel("R03_self", "tblCustomer", "ReferredBy", "tblCustomer", "CustomerID", 0),
  rel("R04_profile_1to1", "Customer Profile", "CustomerID", "tblCustomer", "CustomerID", 1),
  rel("R05_orders_cascade", "Orders", "CustomerID", "tblCustomer", "CustomerID", 4352),
  rel("R06_lookup_ship", "Orders", "ShipMethodID", "tlk Ship Method", "ID", 2),
  rel("R07_line_order", "Order Line", "OrderNo", "Orders", "OrderNo", 4096),
  rel("R08_note_composite", "Line Note", c("Ref Order", "Ref Line"), "Order Line", c("OrderNo", "LineNo"), 0),
  rel("R09_alloc_reversed", "Line Alloc", c("Alloc Order", "Alloc Line"), "Order Line", c("OrderNo", "LineNo"), 0),
  rel("R10_ship_from", "Shipment", "FromWarehouse", "Warehouse", "WarehouseID", 0),
  rel("R11_ship_to", "Shipment", "ToWarehouse", "Warehouse", "WarehouseID", 0),
  rel("R12_ship_carrier_empty", "Shipment", "CarrierID", "Empty Carrier", "CarrierID", 0),
  rel("R13_store_region_case", "Store", "RegionCode", "tlk_Region", "Code", 0),
  rel("R14_legacy_unique", "Legacy Use", "LegacyCode", "Legacy Code", "LegacyCode", 0),
  rel("R15_audit_nopk", "Audit Log", "CustomerID", "tblCustomer", "CustomerID", 2),
  rel("R16_device_guid", "Device Log", "DeviceGuid", "Device", "DeviceGuid", 0),
  rel("R17_msystem_like", "MSystem Parts", "RegionCode", "tlk_Region", "Code", 2),
  rel("R18_collide_col", "Collide Cols", "ITEM-CODE", "tlk_Region", "Code", 2),
  rel("R19_collide_table", "Order-Detail", "OrderNo", "Orders", "OrderNo", 2),
  rel("R20_left_join", "Store", "HomeWarehouse", "Warehouse", "WarehouseID", 16777218),
  rel("R21_hidden_child", "Hidden Table", "StatusID", "tlk Status", "StatusID", 2),
  rel("R22_apostrophe", "Customer's Notes", "CustomerID", "tblCustomer", "CustomerID", 2),
  rel("R23_non_ascii", u, "Büro Nr", "tblCustomer", "CustomerID", 2),
  rel("R24_photo", "Customer Photo", "CustomerID", "tblCustomer", "CustomerID", 0)
)
queries <- c("qryActiveCustomers", "qry Customer Param", "qryUpdateNothing", "qryUnion", "qryCrosstab", "qryWildIIf")

blank <- data.frame(
  kind = character(0), table_raw = character(0), table_clean = character(0),
  column_raw = character(0), column_clean = character(0), rows = numeric(0),
  pk = character(0), expect_read = character(0), ref_table_raw = character(0),
  ref_column_raw = character(0), ref_table_clean = character(0), ref_column_clean = character(0),
  rel_name = character(0), icolumn = integer(0), grbit_native = numeric(0),
  grbit_app = integer(0), note = character(0), stringsAsFactors = FALSE
)
row <- function(...) {
  x <- blank[NA_integer_, ]
  a <- list(...)
  for (n in names(a)) x[[n]] <- a[[n]]
  rownames(x) <- NULL
  x
}

clean_of <- list()
out <- list()
for (t in tables) {
  df <- as.data.frame(setNames(rep(list(1), length(t$cols)), t$cols), check.names = FALSE)
  cl <- names(janitor::clean_names(df))
  names(cl) <- t$cols
  clean_of[[t$name]] <- cl
  tc <- janitor::make_clean_names(t$name)
  out[[length(out) + 1]] <- row(
    kind = "table", table_raw = t$name, table_clean = tc, rows = t$rows,
    pk = t$pk, expect_read = t$expect, note = t$note
  )
  for (i in seq_along(t$cols)) {
    out[[length(out) + 1]] <- row(
      kind = "column", table_raw = t$name, table_clean = tc,
      column_raw = t$cols[i], column_clean = unname(cl[i])
    )
  }
}
for (r in rels) {
  out[[length(out) + 1]] <- row(
    kind = "relationship", table_raw = r$child,
    table_clean = janitor::make_clean_names(r$child),
    column_raw = r$col, column_clean = unname(clean_of[[r$child]][[r$col]]),
    ref_table_raw = r$parent, ref_column_raw = r$ref,
    ref_table_clean = janitor::make_clean_names(r$parent),
    ref_column_clean = unname(clean_of[[r$parent]][[r$ref]]),
    rel_name = r$name, icolumn = r$i, grbit_native = r$native,
    grbit_app = as.integer(r$native %% 4)
  )
}
for (q in queries) {
  out[[length(out) + 1]] <- row(kind = "query", table_raw = q, table_clean = janitor::make_clean_names(q), expect_read = "no")
}
key <- do.call(rbind, out)
key_path <- "../../../tests/testthat/fixtures/access_fixture_key.csv"
utils::write.csv(key, key_path, row.names = FALSE, na = "", fileEncoding = "UTF-8")
cat(sprintf("%s: %d rows (%s)\n", basename(key_path), nrow(key), paste(names(table(key$kind)), table(key$kind), collapse = ", ")))
