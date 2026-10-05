/**
 * SimpleTableService
 * ─────────────────────────────────────────────────────────────────────────────
 * Service layer for SimpleDataTable component.
 * Owns ALL business logic: config fetch, SOQL build, record mapping.
 *
 * Design principles:
 *   - No @AuraEnabled here. Only called by SimpleTableController.
 *   - No matrix, no export, no import — only data fetch.
 *   - with sharing enforced on the controller class.
 *
 * Queries use:
 *   - Table__c         (Shree_Tech namespace — resolved via full API name)
 *   - Table_Columns__c (Shree_Tech namespace)
 *
 * Layer:  Service
 * Called by: SimpleTableController
 */
public inherited sharing class SimpleTableService {

    // ─── Schema caches (per-transaction) ─────────────────────────────────────
    private static Map<String, Schema.SObjectType>             sObjectTypeCache = new Map<String, Schema.SObjectType>();
    private static Map<String, Map<String, Schema.SObjectField>> fieldMapCache  = new Map<String, Map<String, Schema.SObjectField>>();

    // ─── Entry Point ─────────────────────────────────────────────────────────

    /**
     * Main method: load config, build SOQL, fetch records, map to DTOs.
     *
     * @param tableName  Name field on Table__c — identifies which config to use
     * @param parentId   Optional — when on a record page, auto-filters child records
     * @return           TableResult DTO for LWC consumption
     */
    public static SimpleTableDTO.TableResult getData(
        String tableName, 
        String parentId, 
        String searchTerm, 
        String filtersJson, 
        String sortColumn, 
        String sortDirection
    ) {

        // 1. Validate input & fetch Table__c config
        if (String.isBlank(tableName)) {
            throw new AuraHandledException('tableName is required.');
        }

        Table__c tableConfig = fetchTableConfig(tableName);
        String baseObject = tableConfig.Object_API_Name__c;

        // 2. Fetch column configs (Table_Columns__c records)
        List<Table_Columns__c> rawCols = fetchColumnConfigs(tableConfig.Id);

        // 3. Build ColumnDef DTOs + SOQL field list
        List<SimpleTableDTO.ColumnDef>  columns      = new List<SimpleTableDTO.ColumnDef>();
        List<String>                    soqlFields   = new List<String>{ 'Id' };
        Map<String, String>             keyToSoql    = new Map<String, String>(); // col key → soql path

        String parentFilterField = null;
        String parentObjType     = String.isNotBlank(parentId) ? getObjectTypeFromId(parentId) : null;

        Integer idx = 0;
        for (Table_Columns__c col : rawCols) {
            SimpleTableDTO.ColumnDef cd = buildColumnDef(col, baseObject, idx);
            columns.add(cd);

            // Collect SOQL fields (skip additional/formula-only cols)
            if (!col.Additional_Column__c && String.isNotBlank(cd.soqlFieldPath)) {
                String path = cd.soqlFieldPath.toLowerCase();
                if (!soqlFields.contains(path)) {
                    soqlFields.add(path);
                }
                // Also pull lookup Id field if present
                if (cd.isLookup && String.isNotBlank(col.Lookup_Field_API_Name__c)) {
                    String lf = col.Lookup_Field_API_Name__c.toLowerCase();
                    if (!soqlFields.contains(lf)) soqlFields.add(lf);
                }
                keyToSoql.put(cd.key, path);
            }

            // Auto-detect parent filter field from Lookup column referencing parent object
            if (String.isNotBlank(parentId) && parentFilterField == null
                && String.isNotBlank(col.Lookup_Field_API_Name__c)
                && String.isNotBlank(parentObjType)
                && col.Object_Reference__c != null
                && col.Object_Reference__c.equalsIgnoreCase(parentObjType)) {
                parentFilterField = col.Lookup_Field_API_Name__c;
            }

            idx++;
        }

        // Fallback: auto-detect parent lookup if metadata didn't tag it
        if (String.isNotBlank(parentId) && String.isBlank(parentFilterField)) {
            parentFilterField = autoDetectParentLookup(baseObject, parentObjType);
        }

        // 4. Build & execute SOQL
        String soql = buildQuery(
            baseObject, 
            soqlFields, 
            parentId, 
            parentFilterField, 
            columns, 
            searchTerm, 
            filtersJson, 
            sortColumn, 
            sortDirection
        );
        List<SObject> records;
        try {
            records = Database.query(soql);
        } catch (Exception ex) {
            throw new AuraHandledException('Failed to load data: ' + ex.getMessage());
        }

        // 5. Map records to RowData DTOs
        List<SimpleTableDTO.RowData> rows = mapRecords(records, columns, keyToSoql);

        // 6. Build and return result
        SimpleTableDTO.TableResult result = new SimpleTableDTO.TableResult();
        result.tableName    = tableConfig.Name;
        result.objectApiName = baseObject;
        result.columns      = columns;
        result.rows         = rows;
        return result;
    }

    // ─── Config Fetching ─────────────────────────────────────────────────────

    private static Table__c fetchTableConfig(String tableName) {
        List<Table__c> configs = [
            SELECT Id, Name,
                   Object_API_Name__c,
                   Object_Name__c
            FROM   Table__c
            WHERE  Name = :tableName
            LIMIT  1
        ];
        if (configs.isEmpty()) {
            throw new AuraHandledException(
                'No Table Configuration found with name: "' + tableName + '".'
            );
        }
        return configs[0];
    }

    private static List<Table_Columns__c> fetchColumnConfigs(Id tableId) {
        List<Table_Columns__c> cols = [
            SELECT Id, Name,
                   Column_API_Name__c,
                   Data_Type__c,
                   Index__c,
                   Is_Sortable__c,
                   Is_Filterable__c,
                   Is_Searchable__c,
                   Is_Visible__c,
                   Additional_Column__c,
                   Lookup_Field_API_Name__c,
                   Object_Reference__c,
                   Aggregate__c
            FROM   Table_Columns__c
            WHERE  Table_Name__c = :tableId
            AND    Is_Visible__c = true
            ORDER BY Index__c ASC NULLS LAST
        ];
        if (cols.isEmpty()) {
            throw new AuraHandledException('No visible columns configured for this table.');
        }
        return cols;
    }

    // ─── ColumnDef Builder ───────────────────────────────────────────────────

    private static SimpleTableDTO.ColumnDef buildColumnDef(
        Table_Columns__c col,
        String baseObject,
        Integer idx
    ) {
        SimpleTableDTO.ColumnDef cd = new SimpleTableDTO.ColumnDef();
        cd.key       = 'col' + idx;
        cd.label     = col.Name;
        cd.fieldName = col.Column_API_Name__c;
        cd.dataType  = col.Data_Type__c != null ? col.Data_Type__c : 'Text';
        cd.sortable  = col.Is_Sortable__c == true;
        cd.filterable = col.Is_Filterable__c == true;
        cd.searchable = col.Is_Searchable__c == true;
        cd.sortOrder  = col.Index__c != null ? col.Index__c.intValue() : idx;
        
        try {
            cd.aggregate = (String)col.get('Aggregate__c');
        } catch (Exception e) {
            cd.aggregate = 'None';
        }

        // Build SOQL path — handle dot-notation for relationship traversal
        String apiName = col.Column_API_Name__c;
        if (String.isNotBlank(apiName)) {
            // If it already has a dot it's already a traversal path
            cd.soqlFieldPath = apiName.toLowerCase();
        }

        // Type-flag booleans for LWC template rendering
        String dt = cd.dataType.toLowerCase();
        cd.isText     = dt == 'text' || dt == 'email' || dt == 'phone' || dt == 'url' || dt == 'richtext' || dt == 'longtext';
        cd.isNumber   = dt == 'number';
        cd.isCurrency = dt == 'currency';
        cd.isPercent  = dt == 'percent' || dt == 'percentage';
        cd.isDate     = dt == 'date';
        cd.isDateTime = dt == 'datetime';
        cd.isBoolean  = dt == 'boolean';
        cd.isPicklist = dt == 'picklist' || dt == 'multipicklist';
        cd.isLookup   = dt == 'lookup';

        // Fetch picklist values dynamically
        if (cd.isPicklist && String.isNotBlank(baseObject) && String.isNotBlank(cd.fieldName)) {
            try {
                String targetObj = baseObject;
                String targetFld = cd.fieldName;

                if (targetFld.contains('.')) {
                    List<String> parts = targetFld.split('\\.');
                    targetFld = parts[parts.size() - 1]; // "Industry"
                    
                    Schema.SObjectType currentObjType = Schema.getGlobalDescribe().get(baseObject);
                    for (Integer i = 0; i < parts.size() - 1; i++) {
                        String relName = parts[i];
                        if (currentObjType == null) break;
                        
                        Schema.DescribeSObjectResult describe = currentObjType.getDescribe();
                        Boolean found = false;
                        for (Schema.SObjectField f : describe.fields.getMap().values()) {
                            Schema.DescribeFieldResult dfr = f.getDescribe();
                            if (dfr.getRelationshipName() != null && dfr.getRelationshipName().equalsIgnoreCase(relName)) {
                                if (dfr.getReferenceTo().size() > 0) {
                                    currentObjType = dfr.getReferenceTo()[0];
                                    found = true;
                                    break;
                                }
                            }
                        }
                        if (!found) {
                            currentObjType = null;
                            break;
                        }
                    }
                    if (currentObjType != null) {
                        targetObj = String.valueOf(currentObjType);
                    }
                }

                if (!sObjectTypeCache.containsKey(targetObj)) {
                    sObjectTypeCache.put(targetObj, Schema.getGlobalDescribe().get(targetObj));
                }
                Schema.SObjectType sObjType = sObjectTypeCache.get(targetObj);
                if (sObjType != null) {
                    if (!fieldMapCache.containsKey(targetObj)) {
                        fieldMapCache.put(targetObj, sObjType.getDescribe().fields.getMap());
                    }
                    Schema.SObjectField sField = fieldMapCache.get(targetObj).get(targetFld);
                    if (sField != null) {
                        List<Schema.PicklistEntry> entries = sField.getDescribe().getPicklistValues();
                        cd.picklistOptions = new List<SimpleTableDTO.PicklistOption>();
                        for (Schema.PicklistEntry entry : entries) {
                            if (entry.isActive()) {
                                cd.picklistOptions.add(new SimpleTableDTO.PicklistOption(entry.getLabel(), entry.getValue()));
                            }
                        }
                    }
                }
            } catch (Exception e) {
                // Ignore metadata describe errors
            }
        }

        return cd;
    }

    // ─── SOQL Builder ────────────────────────────────────────────────────────

    @TestVisible
    private static String buildQuery(
        String                         baseObject,
        List<String>                   fields,
        String                         parentId,
        String                         parentFilterField,
        List<SimpleTableDTO.ColumnDef> columns,
        String                         searchTerm,
        String                         filtersJson,
        String                         sortColumn,
        String                         sortDirection
    ) {
        String fieldList = String.join(fields, ', ');
        String soql = 'SELECT ' + fieldList + ' FROM ' + baseObject;
        
        List<String> conditions = new List<String>();

        // Add parent filter if present
        if (String.isNotBlank(parentId) && String.isNotBlank(parentFilterField)) {
            conditions.add(parentFilterField + ' = \'' + String.escapeSingleQuotes(parentId) + '\'');
        }

        // Add search term condition
        if (String.isNotBlank(searchTerm)) {
            List<String> searchOrs = new List<String>();
            String likeTerm = '\'%' + String.escapeSingleQuotes(searchTerm) + '%\'';
            for (SimpleTableDTO.ColumnDef c : columns) {
                if (c.searchable && String.isNotBlank(c.soqlFieldPath) && !c.isDate && !c.isDateTime && !c.isBoolean) {
                    searchOrs.add(c.soqlFieldPath + ' LIKE ' + likeTerm);
                }
            }
            if (!searchOrs.isEmpty()) {
                conditions.add('(' + String.join(searchOrs, ' OR ') + ')');
            }
        }

        // Accept the original array payload and the logic-aware envelope.
        if (String.isNotBlank(filtersJson)) {
            try {
                String mode = 'AND';
                String expression;
                String filterArray = filtersJson;
                if (filtersJson.trim().startsWith('{')) {
                    Map<String, Object> envelope = (Map<String, Object>)JSON.deserializeUntyped(filtersJson);
                    mode = (String)envelope.get('logic');
                    expression = (String)envelope.get('expression');
                    filterArray = JSON.serialize(envelope.get('filters'));
                }
                if (String.isBlank(mode)) mode = 'AND';
                if (mode != 'AND' && mode != 'OR' && mode != 'CUSTOM') throw new AuraHandledException('Invalid filter mode.');
                List<SimpleTableDTO.FilterDef> filters = (List<SimpleTableDTO.FilterDef>)JSON.deserialize(filterArray, List<SimpleTableDTO.FilterDef>.class);
                if (filters == null || filters.size() > 50) throw new AuraHandledException('Maximum 50 filter conditions.');
                List<String> compiled = new List<String>();
                for (SimpleTableDTO.FilterDef f : filters) {
                    String colPath = '';
                    String dataType = 'Text';
                    for (SimpleTableDTO.ColumnDef c : columns) {
                        if (c.key == f.fieldKey && c.filterable == true) {
                            colPath = c.soqlFieldPath; dataType = c.dataType; break;
                        }
                    }
                    if (String.isBlank(colPath)) throw new AuraHandledException('Invalid filter field.');
                    String condition = buildFilterCondition(colPath, dataType, f);
                    if (String.isBlank(condition)) throw new AuraHandledException('Complete every filter condition.');
                    compiled.add('(' + condition + ')');
                }
                if (!compiled.isEmpty()) {
                    String groupCondition = mode == 'CUSTOM'
                        ? compileFilterLogic(expression, compiled)
                        : String.join(compiled, ' ' + mode + ' ');
                    conditions.add('(' + groupCondition + ')');
                } else if (mode == 'CUSTOM') {
                    throw new AuraHandledException('Add conditions before using custom logic.');
                }
            } catch (Exception e) {
                throw new AuraHandledException('Invalid filters: ' + e.getMessage());
            }
        }

        if (!conditions.isEmpty()) {
            soql += ' WHERE ' + String.join(conditions, ' AND ');
        }

        // Sorting
        if (String.isNotBlank(sortColumn)) {
            String sortPath = '';
            for (SimpleTableDTO.ColumnDef c : columns) {
                if (c.key == sortColumn) {
                    sortPath = c.soqlFieldPath;
                    break;
                }
            }
            if (String.isNotBlank(sortPath)) {
                String dir = String.isNotBlank(sortDirection) && sortDirection.equalsIgnoreCase('desc') ? 'DESC' : 'ASC';
                soql += ' ORDER BY ' + sortPath + ' ' + dir + ' NULLS LAST';
            }
        }

        soql += ' LIMIT 2000';
        return soql;
    }

    private static String buildFilterCondition(String field, String dataType, SimpleTableDTO.FilterDef f) {
        String val = f.value;
        String op = f.operator;
        
        if (op == 'is_blank') op = 'is_null';
        if (op == 'is_not_blank') op = 'is_not_null';
        if (op == 'before') op = 'less_than';
        if (op == 'after') op = 'greater_than';
        if (op == 'is_true') return field + ' = TRUE';
        if (op == 'is_false') return field + ' = FALSE';
        if (op == 'is_null') return field + ' = NULL';
        if (op == 'is_not_null') return field + ' != NULL';
        
        if (String.isBlank(val) && op != 'is_null' && op != 'is_not_null' && op != 'between') return null;

        String safeVal = String.isBlank(val) ? null : filterLiteral(val, dataType);

        if (op == 'equals') return field + ' = ' + safeVal;
        if (op == 'not_equals') return field + ' != ' + safeVal;
        if (op == 'less_than') return field + ' < ' + safeVal;
        if (op == 'greater_than') return field + ' > ' + safeVal;
        if (op == 'less_or_equal') return field + ' <= ' + safeVal;
        if (op == 'greater_or_equal') return field + ' >= ' + safeVal;
        if (op == 'contains') return field + ' LIKE \'%' + String.escapeSingleQuotes(val) + '%\'';
        if (op == 'not_contains') return '(NOT ' + field + ' LIKE \'%' + String.escapeSingleQuotes(val) + '%\')';
        if (op == 'starts_with') return field + ' LIKE \'' + String.escapeSingleQuotes(val) + '%\'';
        if (op == 'ends_with') return field + ' LIKE \'%' + String.escapeSingleQuotes(val) + '\'';
        
        if (op == 'in' || op == 'not_in' || op == 'includes' || op == 'excludes') {
            List<String> parts = val.split(';');
            List<String> escapedParts = new List<String>();
            for (String p : parts) {
                escapedParts.add('\'' + String.escapeSingleQuotes(p.trim()) + '\'');
            }
            String joined = '(' + String.join(escapedParts, ',') + ')';
            if (op == 'in') return field + ' IN ' + joined;
            if (op == 'not_in') return field + ' NOT IN ' + joined;
            if (op == 'includes') return field + ' INCLUDES ' + joined;
            if (op == 'excludes') return field + ' EXCLUDES ' + joined;
        }
        
        if (op == 'between') {
            if (String.isNotBlank(f.valueMin) && String.isNotBlank(f.valueMax)) {
                String safeMin = filterLiteral(f.valueMin, dataType);
                String safeMax = filterLiteral(f.valueMax, dataType);
                return '(' + field + ' >= ' + safeMin + ' AND ' + field + ' <= ' + safeMax + ')';
            }
        }
        return null;
    }

    private static String filterLiteral(String value, String dataType) {
        if (dataType.equalsIgnoreCase('Number') || dataType.equalsIgnoreCase('Currency') || dataType.equalsIgnoreCase('Percent') || dataType.equalsIgnoreCase('Percentage')) {
            return String.valueOf(Decimal.valueOf(value));
        }
        if (dataType.equalsIgnoreCase('Date')) return String.valueOf(Date.valueOf(value));
        if (dataType.equalsIgnoreCase('DateTime')) {
            String normalized = value.replace('T', ' ').replace('Z', '');
            if (normalized.length() == 16) normalized += ':00';
            return Datetime.valueOfGmt(normalized).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        }
        if (dataType.equalsIgnoreCase('Boolean')) {
            if (value != 'true' && value != 'false') throw new AuraHandledException('Invalid boolean value.');
            return value.toUpperCase();
        }
        return '\'' + String.escapeSingleQuotes(value) + '\'';
    }

    // ─── Record → DTO Mapper ─────────────────────────────────────────────────

    private static List<SimpleTableDTO.RowData> mapRecords(
        List<SObject>                  records,
        List<SimpleTableDTO.ColumnDef> columns,
        Map<String, String>            keyToSoql
    ) {
        List<SimpleTableDTO.RowData> rows = new List<SimpleTableDTO.RowData>();

        for (SObject rec : records) {
            SimpleTableDTO.RowData row = new SimpleTableDTO.RowData();
            row.recordId = (String) rec.get('Id');
            row.fields   = new Map<String, Object>();

            for (SimpleTableDTO.ColumnDef cd : columns) {
                String soqlPath = keyToSoql.get(cd.key);
                if (String.isBlank(soqlPath)) continue;

                Object val = resolveFieldValue(rec, soqlPath);
                row.fields.put(cd.key, val);
            }

            rows.add(row);
        }
        return rows;
    }

    /**
     * Traverses dot-notation path on SObject.
     * e.g. 'account.name' → rec.getSObject('Account').get('Name')
     */
    private static Object resolveFieldValue(SObject rec, String soqlPath) {
        if (rec == null || String.isBlank(soqlPath)) return null;

        List<String> parts = soqlPath.split('\\.');
        if (parts.size() == 1) {
            return rec.get(parts[0]);
        }

        // Traverse relationship chain
        SObject current = rec;
        for (Integer i = 0; i < parts.size() - 1; i++) {
            if (current == null) return null;
            try {
                current = current.getSObject(parts[i]);
            } catch (Exception e) {
                return null;
            }
        }
        if (current == null) return null;

        try {
            return current.get(parts[parts.size() - 1]);
        } catch (Exception e) {
            return null;
        }
    }

    // ─── Parent Lookup Auto-Detection ────────────────────────────────────────

    private static String getObjectTypeFromId(String recordId) {
        if (String.isBlank(recordId) || recordId.length() < 3) return null;
        try {
            Id parsedId = (Id) recordId;
            return parsedId.getSObjectType().getDescribe().getName();
        } catch (Exception e) {
            return null;
        }
    }

    private static String autoDetectParentLookup(String childObject, String parentObject) {
        if (String.isBlank(childObject) || String.isBlank(parentObject)) return null;
        try {
            Map<String, Schema.SObjectField> fieldMap = getFieldMap(childObject);
            if (fieldMap == null) return null;

            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult dfr = fieldMap.get(fieldName).getDescribe();
                if (dfr.getType() == Schema.DisplayType.REFERENCE) {
                    for (Schema.sObjectType ref : dfr.getReferenceTo()) {
                        if (ref.getDescribe().getName().equalsIgnoreCase(parentObject)) {
                            return dfr.getName();
                        }
                    }
                }
            }
        } catch (Exception e) { }
        return null;
    }

    private static Map<String, Schema.SObjectField> getFieldMap(String objectName) {
        String key = objectName.toLowerCase();
        if (!fieldMapCache.containsKey(key)) {
            try {
                List<Schema.DescribeSObjectResult> describes = Schema.describeSObjects(
                    new List<String>{ objectName }
                );
                fieldMapCache.put(key,
                    describes.isEmpty() ? null : describes[0].fields.getMap()
                );
            } catch (Exception e) {
                fieldMapCache.put(key, null);
            }
        }
        return fieldMapCache.get(key);
    }

    @TestVisible
    private static String compileFilterLogic(String expression, List<String> conditions) {
        return new FilterLogicParser(expression, conditions).parse();
    }

    // Grammar: numbers, AND, OR and parentheses only. No user text enters SOQL.
    private class FilterLogicParser {
        List<String> tokens = new List<String>();
        List<String> conditions;
        Set<Integer> used = new Set<Integer>();
        Integer position = 0;
        FilterLogicParser(String expression, List<String> compiled) {
            conditions = compiled;
            if (String.isBlank(expression) || expression.length() > 1000) fail();
            String normalized = expression.toUpperCase();
            Matcher matcher = Pattern.compile('[0-9]+|AND|OR|[()]').matcher(normalized);
            while (matcher.find()) tokens.add(matcher.group());
            if (String.join(tokens, '') != normalized.replaceAll('\\s', '') || tokens.size() > 200) fail();
        }
        String parse() {
            String result = parseOr();
            if (position != tokens.size() || used.size() != conditions.size()) fail();
            return result;
        }
        String parseOr() {
            String result = parseAnd();
            while (peek() == 'OR') { position++; result = '(' + result + ' OR ' + parseAnd() + ')'; }
            return result;
        }
        String parseAnd() {
            String result = parseAtom();
            while (peek() == 'AND') { position++; result = '(' + result + ' AND ' + parseAtom() + ')'; }
            return result;
        }
        String parseAtom() {
            String token = peek(); position++;
            if (token == '(') {
                String result = parseOr();
                if (peek() != ')') fail();
                position++; return '(' + result + ')';
            }
            if (token == null || !Pattern.matches('[0-9]+', token) || token.length() > 3) fail();
            Integer numberValue = Integer.valueOf(token);
            if (numberValue < 1 || numberValue > conditions.size()) fail();
            used.add(numberValue);
            return '(' + conditions[numberValue - 1] + ')';
        }
        String peek() { return position < tokens.size() ? tokens[position] : null; }
        void fail() { throw new AuraHandledException('Invalid filter logic. Use every condition number with AND, OR and parentheses.'); }
    }
}
