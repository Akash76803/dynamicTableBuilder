/**
 * SDTConfiguratorDTO
 * GöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇGöÇ
 * Wrapper / DTO layer GÇö all data structures shared across the layered stack.
 */
public class SDTConfiguratorDTO {
  public class TableResult {
    @AuraEnabled
    public List<ColumnConfig> columns;
    @AuraEnabled
    public List<RowData> rows;
    @AuraEnabled
    public String objectApiName;
    @AuraEnabled
    public String tableName;
    @AuraEnabled
    public String tableId;
    @AuraEnabled
    public String parentId;
    @AuraEnabled
    public Boolean hideRowActions;
    @AuraEnabled
    public String illustrationName;
    @AuraEnabled
    public Boolean enableFilters;
    @AuraEnabled
    public Boolean enableMatrixView;
    @AuraEnabled
    public Boolean enableColumnManager;
    @AuraEnabled
    public Boolean enableViews;
    @AuraEnabled
    public Boolean enableImport;
    @AuraEnabled
    public Boolean enableExport;
    @AuraEnabled
    public Boolean enableNewRecord;
    @AuraEnabled
    public List<TableAction> actions;
    @AuraEnabled
    public Boolean enableInfiniteScroll;
    @AuraEnabled
    public String dataLoadMode;
    @AuraEnabled
    public Integer matrixPreviewRowLimit;
    @AuraEnabled
    public String parentFilterField;
    @AuraEnabled
    public FilterPayload defaultFilterPayload;
  }

  public class TableAction {
    @AuraEnabled
    public String id;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String icon;
    @AuraEnabled
    public String type; // Flow, Apex, Navigation
    @AuraEnabled
    public String target; // Flow Name, Class Name, or URL
    @AuraEnabled
    public Boolean requiresSelection;
  }

  public class ActionResponse {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Map<String, Object> data;
  }

  public class ColumnConfig {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String fieldName;
    @AuraEnabled
    public String dataType;
    @AuraEnabled
    public Boolean editable;
    @AuraEnabled
    public Boolean sortable;
    @AuraEnabled
    public Boolean isGroupable;
    @AuraEnabled
    public Boolean additional;
    @AuraEnabled
    public String lookupField;
    @AuraEnabled
    public String relationshipName;
    @AuraEnabled
    public String objectReference;
    @AuraEnabled
    public String soqlFieldPath;
    @AuraEnabled
    public Boolean isText;
    @AuraEnabled
    public Boolean isNumber;
    @AuraEnabled
    public Boolean isCurrency;
    @AuraEnabled
    public Boolean isDate;
    @AuraEnabled
    public Boolean isDateTime;
    @AuraEnabled
    public Boolean isBoolean;
    @AuraEnabled
    public Boolean isPicklist;
    @AuraEnabled
    public Boolean isLookup;
    @AuraEnabled
    public Boolean isPercentage;
    @AuraEnabled
    public Boolean isPhone;
    @AuraEnabled
    public Boolean isEmail;
    @AuraEnabled
    public Boolean isUrl;
    @AuraEnabled
    public Boolean isRichText;
    @AuraEnabled
    public Boolean isLongText;
    @AuraEnabled
    public Integer order;
    @AuraEnabled
    public List<Map<String, String>> picklistOptions;
    @AuraEnabled
    public Boolean isVisible;
    @AuraEnabled
    public Boolean isSearchable;
    @AuraEnabled
    public Boolean isFilterable;
    @AuraEnabled
    public String filterType;
    @AuraEnabled
    public String defaultFilterValue;
    @AuraEnabled
    public Boolean isNumeric;
  }

  public class RowData {
    @AuraEnabled
    public String recordId;
    @AuraEnabled
    public List<CellData> cells;
  }

  public class CellData {
    @AuraEnabled
    public String key;
    @AuraEnabled
    public String fieldName;
    @AuraEnabled
    public String value;
    @AuraEnabled
    public String lookupId;
    @AuraEnabled
    public String objectReference;
    @AuraEnabled
    public Boolean editable;
    @AuraEnabled
    public Boolean isText;
    @AuraEnabled
    public Boolean isNumber;
    @AuraEnabled
    public Boolean isCurrency;
    @AuraEnabled
    public Boolean isDate;
    @AuraEnabled
    public Boolean isDateTime;
    @AuraEnabled
    public Boolean isBoolean;
    @AuraEnabled
    public Boolean isPicklist;
    @AuraEnabled
    public Boolean isLookup;
    @AuraEnabled
    public Boolean isPercentage;
    @AuraEnabled
    public Boolean isPhone;
    @AuraEnabled
    public Boolean isEmail;
    @AuraEnabled
    public Boolean isUrl;
    @AuraEnabled
    public Boolean isRichText;
    @AuraEnabled
    public Boolean isLongText;
    @AuraEnabled
    public List<Map<String, String>> options;
    @AuraEnabled
    public Boolean isNumeric;
  }

  public class LookupSearchResult {
    @AuraEnabled
    public String recordId;
    @AuraEnabled
    public String displayName;
  }

  public class SaveRequest {
    @AuraEnabled
    public String recordId;
    @AuraEnabled
    public Map<String, String> fields;
  }

  public class SaveResult {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public List<String> failedRecordIds;
  }

  public class FilterCriteria {
    @AuraEnabled
    public Integer filterIndex;
    @AuraEnabled
    public String fieldName;
    @AuraEnabled
    public String soqlFieldPath;
    @AuraEnabled
    public String dataType;
    @AuraEnabled
    public String operator;
    @AuraEnabled
    public List<String> values;
  }

  public class FilterPayload {
    @AuraEnabled
    public String logic;
    @AuraEnabled
    public String customLogic;
    @AuraEnabled
    public List<FilterCriteria> filters;
  }

  public class MatrixParams {
    @AuraEnabled
    public List<String> rowFields;
    @AuraEnabled
    public List<String> columnFields;
    @AuraEnabled
    public String aggregateField;
    @AuraEnabled
    public List<String> aggregateFields;
    @AuraEnabled
    public Map<String, String> granularityMap;
  }

  /**
   * =ƒöÑ Data Import structures
   */
  public class ImportResult {
    @AuraEnabled
    public Boolean success;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Integer totalProcessed;
    @AuraEnabled
    public Integer successCount;
    @AuraEnabled
    public Integer errorCount;
    @AuraEnabled
    public List<ImportError> errors;
  }

  public class ImportError {
    @AuraEnabled
    public Integer rowNumber;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String recordData;
  }

  public class ImportMetadata {
    @AuraEnabled
    public List<ImportFieldInfo> allFields;
    @AuraEnabled
    public String objectApiName;
  }

  public class ImportFieldInfo {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String apiName;
    @AuraEnabled
    public String type;
    @AuraEnabled
    public Boolean isLookup;
    @AuraEnabled
    public String relationshipName;
    @AuraEnabled
    public String objectReference;
    @AuraEnabled
    public List<Map<String, String>> externalIdFields;
  }

  public class ImportMapping {
    @AuraEnabled
    public String csvHeader;
    @AuraEnabled
    public String targetField;
    @AuraEnabled
    public String externalIdField;
    @AuraEnabled
    public String relName;
  }

  public class ExportRequest {
    @AuraEnabled
    public List<ExportColumnConfig> columns { get; set; }
    @AuraEnabled
    public List<ExportFilterConfig> filters { get; set; }
    @AuraEnabled
    public String objectApiName { get; set; }
    @AuraEnabled
    public String parentId { get; set; }
    @AuraEnabled
    public String sortField { get; set; }
    @AuraEnabled
    public String sortDirection { get; set; }
    @AuraEnabled
    public String searchTerm { get; set; }
    @AuraEnabled
    public String logic { get; set; }
    @AuraEnabled
    public String tableName { get; set; }
    @AuraEnabled
    public String matrixParamsJson { get; set; }
    @AuraEnabled
    public String customLogic { get; set; }
  }

  public class ExportColumnConfig {
    @AuraEnabled
    public String fieldApiName { get; set; }
    @AuraEnabled
    public String label { get; set; }
    @AuraEnabled
    public String fieldType { get; set; }
  }

  public class ExportFilterConfig {
    @AuraEnabled
    public Integer filterIndex { get; set; }
    @AuraEnabled
    public String fieldApiName { get; set; }
    @AuraEnabled
    public String operator { get; set; }
    @AuraEnabled
    public String fieldType { get; set; }
    @AuraEnabled
    public String value { get; set; }
    @AuraEnabled
    public List<String> values { get; set; }
  }

  public class ExportResult {
    @AuraEnabled
    public Boolean success { get; set; }
    @AuraEnabled
    public String contentVersionId { get; set; }
    @AuraEnabled
    public String fileName { get; set; }
    @AuraEnabled
    public Integer totalRows { get; set; }
    @AuraEnabled
    public String errorMessage { get; set; }
    @AuraEnabled
    public String outputFormat { get; set; }
    @AuraEnabled
    public String decisionReason { get; set; }
    @AuraEnabled
    public Boolean matrixDowngraded { get; set; }
    @AuraEnabled
    public Id exportLogId { get; set; }
  }

  public class BrowserDownloadResult {
    @AuraEnabled
    public Boolean success { get; set; }
    @AuraEnabled
    public String fileName { get; set; }
    @AuraEnabled
    public String contentType { get; set; }
    @AuraEnabled
    public String base64Data { get; set; }
    @AuraEnabled
    public Integer totalRows { get; set; }
    @AuraEnabled
    public String errorMessage { get; set; }
  }

  // -----------------------------------------------------------------
  // PAGINATION DTOs
  // -----------------------------------------------------------------
  public class PaginationCursorDTO {
    @AuraEnabled
    public String sortField;
    @AuraEnabled
    public Object sortValue;
    @AuraEnabled
    public String recordId;
    @AuraEnabled
    public String sortDirection;
  }

  public class TableChunkDTO {
    @AuraEnabled
    public List<RowData> rows;
    @AuraEnabled
    public PaginationCursorDTO nextCursor;
    @AuraEnabled
    public PaginationCursorDTO previousCursor;
    @AuraEnabled
    public Boolean hasMore;
    @AuraEnabled
    public Integer totalCount;
  }

  // -----------------------------------------------------------------
  // MATRIX DTOs
  // -----------------------------------------------------------------
  public class MatrixRequest {
    @AuraEnabled
    public String objectApiName { get; set; }
    @AuraEnabled
    public List<MatrixGroupField> rowGroupFields { get; set; }
    @AuraEnabled
    public List<MatrixGroupField> colGroupFields { get; set; }
    @AuraEnabled
    public List<MatrixSummaryField> summaryFields { get; set; }
    @AuraEnabled
    public List<ExportFilterConfig> filters { get; set; }
    @AuraEnabled
    public Boolean includeSubtotals { get; set; }
    @AuraEnabled
    public String parentId { get; set; }
    @AuraEnabled
    public String logic { get; set; }
    @AuraEnabled
    public String customLogic { get; set; }
    @AuraEnabled
    public Integer previewRowLimit { get; set; }
  }

  public class MatrixGroupField {
    @AuraEnabled
    public String fieldApiName { get; set; }
    @AuraEnabled
    public String granularity { get; set; }
    @AuraEnabled
    public String label { get; set; }
  }

  public class MatrixSummaryField {
    @AuraEnabled
    public String fieldApiName { get; set; }
    @AuraEnabled
    public String aggregateFunction { get; set; }
    @AuraEnabled
    public String label { get; set; }
  }

  public class MatrixResult {
    @AuraEnabled
    public List<List<String>> rowKeys { get; set; }
    @AuraEnabled
    public List<List<String>> colKeys { get; set; }
    @AuraEnabled
    public List<MatrixCell> cells { get; set; }
    @AuraEnabled
    public List<String> rowFieldLabels { get; set; }
    @AuraEnabled
    public List<String> colFieldLabels { get; set; }
    @AuraEnabled
    public List<String> summaryAliases { get; set; }
    @AuraEnabled
    public List<String> summaryLabels { get; set; }
    @AuraEnabled
    public Integer totalCellCount { get; set; }
    @AuraEnabled
    public Integer totalMatrixRowCount { get; set; }
    @AuraEnabled
    public Integer previewRowLimit { get; set; }
    @AuraEnabled
    public Boolean isPreviewTruncated { get; set; }
    @AuraEnabled
    public List<MatrixCell> grandTotalCells { get; set; }
    @AuraEnabled
    public String errorMessage { get; set; }
  }

  public class MatrixResponse {
    @AuraEnabled
    public String status { get; set; }
    @AuraEnabled
    public String jobId { get; set; }
    @AuraEnabled
    public Integer progress { get; set; }
    @AuraEnabled
    public String message { get; set; }
    @AuraEnabled
    public MatrixResult matrixResult { get; set; }
    @AuraEnabled
    public MatrixExecutionDecision decision { get; set; }
  }

  public class MatrixJobStatus {
    @AuraEnabled
    public String status { get; set; }
    @AuraEnabled
    public String jobId { get; set; }
    @AuraEnabled
    public Integer progress { get; set; }
    @AuraEnabled
    public String message { get; set; }
    @AuraEnabled
    public Boolean isTerminal { get; set; }
  }

  public class MatrixExecutionDecision {
    @AuraEnabled
    public String mode { get; set; }
    @AuraEnabled
    public String reason { get; set; }
    @AuraEnabled
    public Integer sourceRecordCount { get; set; }
    @AuraEnabled
    public String configHash { get; set; }
  }

  public class MatrixCell {
    @AuraEnabled
    public String rowKey { get; set; }
    @AuraEnabled
    public String colKey { get; set; }
    @AuraEnabled
    public String alias { get; set; }
    @AuraEnabled
    public Decimal value { get; set; }
  }

  public class UserViewDTO {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String filterPayloadJson;
    @AuraEnabled
    public String columnStateJson;
    @AuraEnabled
    public String matrixConfigJson;
    @AuraEnabled
    public String sortKey;
    @AuraEnabled
    public String sortDirection;
    @AuraEnabled
    public Boolean isDefault;
    @AuraEnabled
    public String description;
  }
}
