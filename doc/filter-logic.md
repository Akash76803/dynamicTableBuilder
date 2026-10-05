# Filter panel and logic

Numbered conditions, full-width selectors, labelled ranges, add below conditions, footer clear/apply. Existing sdtMultiSelect is unchanged.

All (AND) is the default. Any (OR) and Custom support numbers, AND, OR, parentheses; AND has precedence. Every condition must appear. Incomplete conditions and invalid expressions block Apply. After deleting a condition, check renumbered references. Removing a custom filter via a table chip opens the panel for explicit editing rather than changing logic silently.

Reopening preserves mode, expression, operators, values and numeric zero. Clear resets AND. Legacy filter arrays remain accepted; OR/custom use {filters, logic, expression} in existing filtersJson parameter. Server validates configured filterable fields, grammar, range of references, every-condition inclusion, length/token/count limits. Invalid filters now fail explicitly rather than silently return unfiltered data. Parent and search restrictions remain AND outside the entire custom group.

Validation: local JS component tests cover payload, reopening, zero, expression validation, remove/clear and table request wiring. Apex parser tests included; execute SimpleTableFilterLogicTest in target org. No org deployment or Apex test execution performed here. Smoke-test picklists, range filters, parent restriction, sorting, pagination, aggregates and resize after deployment.

LWC compiler checks passed for both branches. Backend operator aliases for blank/boolean/date now match the panel; numeric/date literals are parsed before query insertion. Datetime-local values retain GMT interpretation.
