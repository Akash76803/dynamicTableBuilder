/**
 * SimpleTableDTO
 * ─────────────────────────────────────────────────────────────────────────────
 * Data Transfer Objects for SimpleDataTable LWC component.
 * Pure data shapes only — no business logic, no SOQL.
 *
 * Layer:  DTO
 * Used by: SimpleTableController, SimpleTableService
 */
public class SimpleTableDTO {

    // ─── Column Definition ───────────────────────────────────────────────────

    /**
     * Represents a single column in the table.
     * Built from Table_Columns__c config records.
     */
    public class ColumnDef {
        @AuraEnabled public String  key;          // Unique key = Column_API_Name__c (col0, col1...)
        @AuraEnabled public String  label;        // Display label (Name field on Table_Columns__c)
        @AuraEnabled public String  fieldName;    // Salesforce field API name (Column_API_Name__c)
        @AuraEnabled public String  soqlFieldPath;// Dot-notation SOQL path (e.g. Account.Name)
        @AuraEnabled public String  dataType;     // Text|Number|Currency|Percent|Date|DateTime|Picklist|Boolean|Lookup
        @AuraEnabled public Boolean sortable;
        @AuraEnabled public Boolean filterable;
        @AuraEnabled public Boolean searchable;
        @AuraEnabled public Integer sortOrder;    // From Index__c on Table_Columns__c
        @AuraEnabled public String  aggregate;    // Sum, Average, Count, etc.
        // Type-flag booleans — pre-computed for easy template rendering in LWC
        @AuraEnabled public Boolean isText;
        @AuraEnabled public Boolean isNumber;
        @AuraEnabled public Boolean isCurrency;
        @AuraEnabled public Boolean isPercent;
        @AuraEnabled public Boolean isDate;
        @AuraEnabled public Boolean isDateTime;
        @AuraEnabled public Boolean isBoolean;
        @AuraEnabled public Boolean isPicklist;
        public String linkIdPath;
        public String linkLabelPath;
        @AuraEnabled public Boolean isLookup;
        @AuraEnabled public List<PicklistOption> picklistOptions; // Added for Picklist/Multipicklist
    }

    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class FilterDef {
        @AuraEnabled public String fieldKey;
        @AuraEnabled public String operator;
        @AuraEnabled public String value;
        @AuraEnabled public String valueMin;
        @AuraEnabled public String valueMax;
    }

    // ─── Row Data ────────────────────────────────────────────────────────────

    /**
     * Represents a single data row returned to the LWC.
     * fields map: ColumnDef.key → raw display value
     */
    public class RecordLink {
        @AuraEnabled public String recordId;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String label;
    }

    public class RowData {
        @AuraEnabled public String              recordId;
        @AuraEnabled public Map<String, Object> fields;
        @AuraEnabled public Map<String, RecordLink> recordLinks;
    }

    // ─── Table Result ────────────────────────────────────────────────────────

    /**
     * Top-level response object returned to simpleDataTable via @wire.
     */
    public class TableResult {
        @AuraEnabled public List<ColumnDef> columns;       // Ordered column definitions
        @AuraEnabled public List<RowData>   rows;          // All fetched rows
        @AuraEnabled public String          objectApiName; // e.g. 'Account'
        @AuraEnabled public String          tableName;     // Config name (Name on Table__c)
    }
}
