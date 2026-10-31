# Test fixtures

## `declared_rels.accdb`

Made by hand by Amelia Miramonti to test reading an Access file. Every value is an invented placeholder. No script rebuilds it; added in fa0b4e9, 2026-09-28.

| Table | Columns | Rows |
|---|---|---|
| `tbl Visits` | `VisitID`, `ServiceID`, `SiteID` | 6 |
| `tlk_services` | `ID`, `Service` | 3 |
| `tlk_sites` | `ID`, `Site` | 3 |

Two declared relationships: `ServiceID` to `tlk_services.ID` (integrity enforced) and `SiteID` to `tlk_sites.ID` (not enforced). A regression test relies on the space in `tbl Visits`, so keep the name.
