# Sticky table header

The table container owns horizontal and vertical scrolling, with a default maximum height of 480px (CSS custom property --sdt-table-max-height). Short lists keep their natural height. Column header cells remain at top:0 within this surface; horizontal scrolling moves header and rows together. Separate collapsed-border replacement avoids sticky border painting artifacts.

The data wrapper is a flex column; pagination remains outside the scroll surface. The table can shrink in constrained page regions. Card view keeps its own overflow; toolbar and filters retain their placement. No data, SOQL, navigation, sorting, resize or aggregate logic is changed.

Both branches use identical CSS. LWC CSS compilation verified. Live Salesforce browser verification remains pending: scroll both axes, resize a column, sort, wrap text, open filters, switch cards, paginate and follow record links.
