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
  public static List<SObject> queryRecords(String soql) {
    System.debug(LoggingLevel.FINE, '[Selector] queryRecords SOQL');
    List<SObject> records = Database.query(soql, AccessLevel.USER_MODE);
    System.debug(LoggingLevel.FINE, '[Selector] queryRecords');
    return records;
  }

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
    DynamicTableSecurity.assertValidObjectAndField(objectApiName, displayField);
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
  public static List<String> saveRecords(List<SObject> records) {
    List<String> failedIds = new List<String>();

    Database.SaveResult[] results = Database.update(
      records,
      false,
      AccessLevel.USER_MODE
    ); // partial success with user security

    for (Integer i = 0; i < results.size(); i++) {
      if (!results[i].isSuccess()) {
        failedIds.add((String) records[i].get('Id'));
        for (Database.Error err : results[i].getErrors()) {
          System.debug(LoggingLevel.FINE, '[Selector] saveRecords DML error on');
        }
      }
    }

    System.debug(LoggingLevel.FINE, '[Selector] saveRecords');

    return failedIds;
  }

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
  public static Integer getRecordCount(String soql) {
    System.debug(LoggingLevel.FINE, '[Selector] getRecordCount SOQL');
    return Database.countQuery(soql, AccessLevel.USER_MODE);
  }

  // -----------------------------------------------------------------
  // getExportRecords
  // -----------------------------------------------------------------
  public List<SObject> getExportRecords(
    List<String> fieldApiNames,
    String objectApiName,
    String whereClause,
    String sortField,
    String sortDir
  ) {
    Set<String> fieldSet = new Set<String>{ 'Id' };
    fieldSet.addAll(fieldApiNames);
    String selectClause = String.join(new List<String>(fieldSet), ', ');

    String soql =
      'SELECT ' +
      selectClause +
      ' FROM ' +
      String.escapeSingleQuotes(objectApiName);

    if (String.isNotBlank(whereClause)) {
      soql += ' WHERE ' + whereClause;
    }

    if (String.isNotBlank(sortField)) {
      String dir = (sortDir == 'DESC') ? 'DESC' : 'ASC';
      soql += ' ORDER BY ' + String.escapeSingleQuotes(sortField) + ' ' + dir;
    }

    System.debug(LoggingLevel.FINE, '[Selector] Query executed.');
    return Database.query(soql, AccessLevel.USER_MODE);
  }

  public List<AggregateResult> getAggregateRecords(String soql) {
    if (String.isBlank(soql)) {
      throw new SDTConfiguratorService.MatrixQueryException(
        'Aggregate SOQL blank nahi ho sakta.'
      );
    }

    System.debug(LoggingLevel.FINE, 'Executing aggregate SOQL:\n');

    try {
      return (List<AggregateResult>) Database.query(soql, AccessLevel.USER_MODE);
    } catch (QueryException qe) {
      System.debug(LoggingLevel.FINE, 'Aggregate query failed');
      throw new SDTConfiguratorService.MatrixQueryException(
        'Matrix query failed: ' + qe.getMessage()
      );
    }
  }

  /**
   * Fetches all Table_User_View__c records for a given table name belonging to the current user,
   * ordered by Is_Default__c DESC, Name ASC.
   */
  public static List<Table_User_View__c> getUserViewsByTableName(String tableName) {
    if (String.isBlank(tableName)) {
      return new List<Table_User_View__c>();
    }
    String trimmedName = tableName.trim();
    return [
      SELECT
        Id,
        Name,
        Table_Name__c,
        Filter_Payload_JSON__c,
        Column_State_JSON__c,
        Matrix_Config_JSON__c,
        Sort_Key__c,
        Sort_Direction__c,
        Is_Default__c,
        Description__c,
        OwnerId
      FROM Table_User_View__c
      WHERE Table_Name__c = :trimmedName
        AND OwnerId = :UserInfo.getUserId()
      ORDER BY Is_Default__c DESC, Name ASC
    ];
  }

  /**
   * Fetches a single Table_User_View__c by its Id.
   */
  public static Table_User_View__c getUserViewById(Id viewId) {
    if (viewId == null) {
      return null;
    }
    List<Table_User_View__c> results = [
      SELECT
        Id,
        Name,
        Table_Name__c,
        Filter_Payload_JSON__c,
        Column_State_JSON__c,
        Matrix_Config_JSON__c,
        Sort_Key__c,
        Sort_Direction__c,
        Is_Default__c,
        Description__c,
        OwnerId
      FROM Table_User_View__c
      WHERE Id = :viewId
      LIMIT 1
    ];
    return results.isEmpty() ? null : results[0];
  }
}
