# List view UI update

Both independent and namespace editions share the same Simple Data Table UI. This change is presentation and browser preferences only; Apex endpoints and configuration schema are unchanged.

Horizontal scrolling is contained in the table; flex children have min-width zero to prevent parent clipping. Width defaults are 150px for numeric/date/boolean columns, 300px for Description and 200px otherwise. Resize with drag or left/right keys, bounded to 90–600px. Preferences use a separate sdt_widths_<tableName> localStorage key keyed by field API name; column order/visibility still use the existing sdt_cols_ key. Reset widths only clears width preferences. Wrap text affects the table display without changing cell values. Record count shows the fetched dataset count; footer shows the current range. Currency formatting and aggregate formulas remain unchanged. No new custom field or record editing was introduced.

Validation: local component-method regression checks cover existing search/filter/sort query parameters, pagination, aggregates, card view, visibility/reorder, width persistence, reset, keyboard and pointer resize cleanup. Live Salesforce compilation and browser UI QA are still required.

Org QA: load a wide table and scroll to the last column; resize first/middle/last columns; hide/reorder and reopen; search and filter; sort; switch pages and card view; verify totals; reload and check widths; reset widths; wrap long text; open panels on narrow screens. Namespace edition uses its code-only manifest. No org deployment was performed by this change.
