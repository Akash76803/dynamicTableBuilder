# Automatic record hyperlinks

No new configuration fields. Schema describes detect base record-name fields (including custom auto-number names), direct references and related record-name paths. A configured Lookup relationship display field can also target its parent record. Non-name relationship values remain plain text by default.

Service adds corresponding ID/name paths to the same query and returns recordLinks separately from raw fields. ID determines actual referenced object for polymorphic records. Null relationships have no link. A direct lookup ID displays the related name while raw fields remain available for existing filter/sort processing.

LWC uses NavigationMixin GenerateUrl with standard__recordPage and native anchors in table/card cells. Normal click uses Navigate; modified clicks retain native new-tab behaviour. URL generation is deduplicated by record ID per response, with a generation guard against stale results. Navigation failures retain readable text.

Local checks: LWC compilation, Apex syntax parsing, JS link/blank/card/raw-value/aggregate/modifier-click tests, existing table regressions. SimpleTableRecordLinkTest included; Salesforce semantic compilation, Apex execution and live-org navigation remain pending. Run both SimpleTableRecordLinkTest and SimpleTableFilterLogicTest after deployment. Schema resolution for heterogeneous polymorphic paths beyond shared Name may require additional support if the org uses them.

Sticky header is a separate follow-up and is not changed by this commit.

## Configured lookup path priority

Lookup_Field_API_Name__c is authoritative for link targets on any data type, including Text. Column_API_Name__c remains the display path. Example: Account.Name + Account.Id displays the account name and opens that account; Account.Name + Account.ParentId displays the account name but opens the configured parent. Paths are schema-validated and may end in Id or a reference field. Invalid configured paths fail explicitly instead of silently selecting another target. Blank configuration retains schema fallback. The base object's own record-name column always uses the current row Id. No LWC change or new metadata field is required.

Apex tests include configured Text paths, overridden targets, blank fallback, current-name priority, invalid paths and separate display/target mapping. Local Apex syntax and existing JS link tests pass; org compilation and Apex execution remain pending.
