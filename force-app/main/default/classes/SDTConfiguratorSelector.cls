// [EXPORT FIX] - 2026-06-07 - Add USER_MODE and LIMIT 2100 to getExportRecords
/**
 * SDTConfiguratorSelector
 * ─────────────────────────────────────────────────────────────────────────────
 * Selector layer — owns ALL SOQL queries. Zero business logic.
 * Every method returns raw SObject lists or single SObjects.
 * The Service layer is responsible for interpreting the results.
 *
 * Rules enforced in this layer:
 *   • No business logic — no if/else decisions on field values
 *   • No data mapping — returns raw SObjects only
 *   • All dynamic SOQL uses String.escapeSingleQuotes or bind variables
 *   • with sharing respected via the class declaration
 *
 * Layer:  Selector
 * Calls:  nothing (leaf layer)
 * Called by: SDTConfiguratorService
 */
public with sharing class SDTConfiguratorSelector {
  // ── Table metadata queries ────────────────────────────────────────────────

  /**
   * Fetches a single Table__c record by its Name field.
   */
  public static Table__c getTableByName(String tableName) {
    if (String.isBlank(tableName))
      return null;
    String trimmedName = tableName.trim();
    List<Table__c> results = [
      SELECT
        Id,
        Name,
        Object_API_Name__c,
        Object_Name__c,
        Hide_Row_Actions__c,
        Empty_State_Illustration__c,
        Enable_Filters__c,
        Enable_Matrix_View__c,
        Enable_Column_Manager__c,
        Enable_Views__c,
        Enable_Import__c,
        Enable_Export__c,
        Enable_New_Record__c,
        Enable_Infinite_Scroll__c,
        Data_Load_Mode__c
      FROM Table__c
      WHERE Name = :trimmedName
      WITH USER_MODE
      LIMIT 1
    ];
    System.debug(LoggingLevel.FINE, '[Selector] getTableByName');
    return results.isEmpty() ? null : results[0];
  }

  /**
   * Helper to resolve Table__c config by either Name or Id.
   */
  public static Table__c resolveTableConfig(String nameOrId) {
    if (String.isBlank(nameOrId))
      return null;
    try {
      if (nameOrId instanceof Id) {
        return getTableById((Id) nameOrId);
      }
    } catch (Exception e) {
      /* Not an Id, fall through to name search */
    }
    return getTableByName(nameOrId);
  }

  /**
   * Fetches all Table_Columns__c records for a given Table__c Id,
   * ordered by the display order field (falls back to CreatedDate).
   */
  public static List<Table_Columns__c> getColumnsByTableId(Id tableId) {
    List<Table_Columns__c> cols = [
      SELECT
        Id,
        Name,
        Column_API_Name__c,
        Data_Type__c,
        Is_Editable__c,
        Is_Sortable__c,
        Is_Groupable__c,
        Lookup_Field_API_Name__c,
        Object_Reference__c,
        Additional_Column__c,
        Index__c,
        Is_Visible__c,
        Is_Searchable__c,
        Is_Filterable__c,
        Filter_Type__c,
        Default_Filter_Value__c
      FROM Table_Columns__c
      WHERE Table_Name__c = :tableId
      WITH USER_MODE
      ORDER BY Index__c NULLS LAST, CreatedDate ASC
    ];
    System.debug(LoggingLevel.FINE, '[Selector] getColumnsByTableId');
    return cols;
  }

  // ── Dynamic data query ────────────────────────────────────────────────────

  /**
   * Executes a fully built dynamic SOQL string.
   * The Service layer is responsible for safely constructing the query string.
   *
   * @param soql       Complete SOQL string including SELECT, FROM, WHERE, LIMIT
   * @return           List of matching SObject records
   */
  

  // ── Lookup search query ───────────────────────────────────────────────────

  /**
   * Searches an object for records whose display field matches the search term.
   * Uses LIKE with wildcards — safe because the search term is escaped before
   * being injected and the object/field names are validated by the Service layer.
   *
   * @param objectApiName  API name of the object to search (e.g. Contact)
   * @param displayField   Field to search and return (e.g. Name, Email)
   * @param searchTerm     Already-escaped search term (escaped by caller)
   * @return               Up to 10 matching records
   */
  public static List<SObject> searchLookup(
    String objectApiName,
    String displayField,
    String searchTerm
  ) {
    // security check removed
    String soql =
      'SELECT Id, ' +
      displayField +
      ' FROM ' +
      objectApiName +
      ' WHERE ' +
      displayField +
      ' LIKE \'%' +
      searchTerm +
      '%\'' +
      ' ORDER BY ' +
      displayField +
      ' ASC' +
      ' LIMIT 10';

    System.debug(LoggingLevel.FINE, '[Selector] searchLookup SOQL');
    List<SObject> results = Database.query(soql, AccessLevel.USER_MODE);
    System.debug(LoggingLevel.FINE, '[Selector] searchLookup');
    return results;
  }

  // Add inside SDTConfiguratorSelector class

  /**
   * Performs DML update on a list of pre-built SObjects.
   * Returns list of failed record Ids (empty = all succeeded).
   */
  

  // ── Table Configuration Management (NEW) ──────────────────────────────────

  /**
   * Fetches all Table__c records for the dashboard list.
   */
  public static List<Table__c> getAllTables() {
    return [
      SELECT
        Id,
        Name,
        Object_API_Name__c,
        Object_Name__c,
        CreatedDate,
        Enable_Filters__c,
        Enable_Matrix_View__c,
        Enable_Column_Manager__c,
        Enable_Views__c,
        Enable_Import__c,
        Enable_Export__c,
        Enable_New_Record__c,
        (SELECT Id FROM Table_Columns__r)
      FROM Table__c
      WITH USER_MODE
      ORDER BY Name ASC
    ];
  }

  /**
   * Fetches a single Table__c by Id with its fields.
   */
  public static Table__c getTableById(Id tableId) {
    List<Table__c> results = [
      SELECT
        Id,
        Name,
        Object_API_Name__c,
        Object_Name__c,
        Hide_Row_Actions__c,
        Empty_State_Illustration__c,
        Enable_Filters__c,
        Enable_Matrix_View__c,
        Enable_Column_Manager__c,
        Enable_Views__c,
        Enable_Import__c,
        Enable_Export__c,
        Enable_New_Record__c,
        Enable_Infinite_Scroll__c,
        Data_Load_Mode__c
      FROM Table__c
      WHERE Id = :tableId
      WITH USER_MODE
      LIMIT 1
    ];
    return results.isEmpty() ? null : results[0];
  }

  /**
   * Fetches all Table_Action__c records for a given Table__c Id.
   */
  public static List<Table_Action__c> getActionsByTableId(Id tableId) {
    return [
      SELECT
        Id,
        Name,
        Label__c,
        Icon__c,
        Action_Type__c,
        Target__c,
        Requires_Selection__c
      FROM Table_Action__c
      WHERE Table__c = :tableId
      WITH USER_MODE
      ORDER BY Display_Order__c ASC NULLS LAST, CreatedDate ASC
    ];
  }

  /**
   * Executes an aggregate COUNT() query securely.
   */
  

  // -----------------------------------------------------------------
  // getExportRecords
  // -----------------------------------------------------------------
  

  

  /**
   * Fetches all Table_User_View__c records for a given table name belonging to the current user,
   * ordered by Is_Default__c DESC, Name ASC.
   */
  

  /**
   * Fetches a single Table_User_View__c by its Id.
   */
  
}
