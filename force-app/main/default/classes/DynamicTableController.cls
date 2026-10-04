// [EXPORT FIX] - 2026-06-07 - Merge exportGetData and exportSaveFile into exportAndSaveFile, add duplicate job guard
/**
 * DynamicTableController
 * ─────────────────────────────────────────────────────────────────────────────
 * Controller layer — thin AuraEnabled entry points ONLY.
 * No business logic, no SOQL, no data mapping.
 * Every method validates surface-level inputs then delegates to the Service.
 *
 * Layer:  Controller (AuraEnabled)
 * Calls:  DynamicTableService
 * Called by: LWC via @wire / imperative Apex
 */
public with sharing class DynamicTableController {
  /**
   * Returns column configs + flattened row data for the given table config.
   *
   * Used as @wire in LWC (cacheable=true).
   *
   * @param tableName   Name field on Table__c — which config to load
   * @param parentId    Optional record Id from the host record page.
   *                    When provided, the query is filtered to child records
   *                    of that parent via the matching lookup field.
   *                    Pass null or empty string for standalone / list views.
   */
  @AuraEnabled(cacheable=true)
  public static DynamicTableDTO.TableResult getTableData(
    String tableName,
    String parentId
  ) {
    Boolean previousSuppressErrorLogging = DynamicTableService.suppressErrorLogging;
    try {
      System.debug(LoggingLevel.FINE, '[Controller] getTableData → tableName');
      DynamicTableService.suppressErrorLogging = true;
      return DynamicTableService.getTableData(tableName, parentId);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (DynamicTableService.DynamicTableException dex) {
      throw new AuraHandledException(dex.getMessage());
    } catch (Exception ex) {
      System.debug(
        LoggingLevel.ERROR,
        'DynamicTableController.getTableData error: ' + ex.getMessage()
      );
      throw new AuraHandledException(
        'Failed to load table data: ' + ex.getMessage()
      );
    } finally {
      DynamicTableService.suppressErrorLogging = previousSuppressErrorLogging;
    }
  }

  /**
   * Entry point to fetch a chunk of data for Virtual Browse Mode.
   * NOT cacheable — returns changing chunks of data via cursor pagination.
   */
  @AuraEnabled
  public static DynamicTableDTO.TableChunkDTO getVirtualTableChunk(
    String tableName,
    String parentId,
    String filtersJson,
    String cursorJson,
    Integer chunkSize,
    String searchTerm
  ) {
    try {
      return DynamicTablePaginationService.getVirtualTableChunk(
        tableName,
        parentId,
        filtersJson,
        cursorJson,
        chunkSize,
        searchTerm
      );
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (DynamicTableService.DynamicTableException dex) {
      throw new AuraHandledException(dex.getMessage());
    } catch (Exception ex) {
      String errorRef = DynamicTableErrorLogger.logException(
        'DynamicTableController',
        'getVirtualTableChunk',
        ex,
        new Map<String, Object>{
          'methodName' => 'getVirtualTableChunk',
          'operation' => 'controllerFallback',
          'tableName' => tableName,
          'parentId' => parentId,
          'chunkSize' => chunkSize
        }
      );

      throw new AuraHandledException(
        'An unexpected error occurred. Please contact your administrator. Error Reference: ' +
        errorRef
      );
    }
  }

  /**
   * Asynchronously calculates and caches the record count for Virtual Browse Mode.
   */
  @AuraEnabled(cacheable=true)
  public static Integer getAsyncRecordCount(
    String tableName,
    String parentId,
    String filtersJson,
    String searchTerm
  ) {
    try {
      return DynamicTablePaginationService.getAsyncRecordCount(
        tableName,
        parentId,
        filtersJson,
        searchTerm
      );
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (DynamicTableService.DynamicTableException dex) {
      throw new AuraHandledException(dex.getMessage());
    } catch (Exception ex) {
      String errorRef = DynamicTableErrorLogger.logException(
        'DynamicTableController',
        'getAsyncRecordCount',
        ex,
        new Map<String, Object>{
          'methodName' => 'getAsyncRecordCount',
          'operation' => 'controllerFallback',
          'tableName' => tableName,
          'parentId' => parentId
        }
      );

      throw new AuraHandledException(
        'An unexpected error occurred. Please contact your administrator. Error Reference: ' +
        errorRef
      );
    }
  }

  /**
   * Searches records of a given object for use in editable lookup dropdowns.
   *
   * NOT cacheable — results change with every user keystroke.
   *
   * @param objectApiName   Object to search e.g. Contact, Account, My_Custom__c
   * @param searchTerm      Text the user typed — min 2 chars enforced in LWC
   * @param nameField       Field to search and display — defaults to Name
   */
  @AuraEnabled
  public static List<DynamicTableDTO.LookupSearchResult> searchLookupRecords(
    String objectApiName,
    String searchTerm,
    String nameField
  ) {
    try {
      System.debug(
        LoggingLevel.FINE,
        '[Controller] searchLookupRecords → object'
      );
      return DynamicTableService.searchLookupRecords(
        objectApiName,
        searchTerm,
        nameField
      );
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (DynamicTableService.DynamicTableException dex) {
      throw new AuraHandledException(dex.getMessage());
    } catch (Exception ex) {
      String errorRef = DynamicTableErrorLogger.logException(
        'DynamicTableController',
        'searchLookupRecords',
        ex,
        new Map<String, Object>{
          'methodName' => 'searchLookupRecords',
          'operation' => 'controllerFallback',
          'objectApiName' => objectApiName
        }
      );

      throw new AuraHandledException(
        'An unexpected error occurred. Please contact your administrator. Error Reference: ' +
        errorRef
      );
    }
  }

  /**
   * Saves edited rows back to Salesforce.
   * NOT cacheable — performs DML.
   *
   * @param tableName   Same tableName used to load the table (resolves col keys)
   * @param recordsJson JSON array of { recordId, fields: { colKey: value } }
   */
  @AuraEnabled
  public static DynamicTableDTO.SaveResult saveTableData(
    String tableName,
    String recordsJson
  ) {
    try {
      System.debug(LoggingLevel.FINE, '[Controller] saveTableData → tableName');
      System.debug(
        LoggingLevel.INFO,
        '[Controller] saveTableData request received.'
      );
      return DynamicTableService.saveTableData(tableName, recordsJson);
    } catch (DynamicTableService.DynamicTableException ex) {
      throw new AuraHandledException(
        'An internal server error occurred. Please contact support.'
      );
    } catch (Exception ex) {
      System.debug(
        LoggingLevel.FINE,
        '[Controller] saveTableData unexpected error'
      );
      throw new AuraHandledException(
        'An unexpected error occurred while saving. Please contact your administrator.'
      );
    }
  }

  /**
   * Returns column configs + filtered row data for the given table config.
   *
   * NOT cacheable — filter results change per user interaction.
   *
   * @param tableName     Name field on Table__c — which config to load
   * @param parentId      Optional parent record Id (same as getTableData)
   * @param filtersJson   JSON-serialised DynamicTableDTO.FilterPayload
   *                      { logic: 'AND'|'OR', filters: [ FilterCriteria… ] }
   *                      Pass null or '' to return all records (respects parentId filter only)
   */
  @AuraEnabled
  public static DynamicTableDTO.TableResult getFilteredTableData(
    String tableName,
    String parentId,
    String filtersJson
  ) {
    try {
      System.debug(
        LoggingLevel.FINE,
        '[Controller] getFilteredTableData → tableName'
      );

      return DynamicTableService.getFilteredTableData(
        tableName,
        parentId,
        filtersJson
      );
    } catch (DynamicTableService.DynamicTableException ex) {
      throw new AuraHandledException(
        'An internal server error occurred. Please contact support.'
      );
    } catch (Exception ex) {
      System.debug(
        LoggingLevel.FINE,
        '[Controller] getFilteredTableData unexpected error'
      );
      throw new AuraHandledException(
        'An unexpected error occurred loading filtered data. ' +
        'Please contact your administrator.'
      );
    }
  }

  /**
   * Retrieves the exact database record count for the given table/filters.
   * Used for export routing and accurate metrics without hitting heap limits.
   */
  @AuraEnabled
  public static Integer getRecordCount(
    String tableName,
    String parentId,
    String filtersJson
  ) {
    try {
      return DynamicTableService.getRecordCount(
        tableName,
        parentId,
        filtersJson
      );
    } catch (DynamicTableService.DynamicTableException ex) {
      throw new AuraHandledException(
        'An internal server error occurred. Please contact support.'
      );
    } catch (Exception ex) {
      System.debug(
        LoggingLevel.FINE,
        '[Controller] getRecordCount unexpected error'
      );
      throw new AuraHandledException('Failed to retrieve record count.');
    }
  }

  @AuraEnabled
  public static Map<String, Decimal> getGrandTotals(
    String tableName,
    String parentId,
    String filtersJson,
    String searchTerm
  ) {
    try {
      return DynamicTableService.getGrandTotals(
        tableName,
        parentId,
        filtersJson,
        searchTerm
      );
    } catch (DynamicTableService.DynamicTableException ex) {
      throw new AuraHandledException(
        'An internal server error occurred. Please contact support.'
      );
    } catch (Exception ex) {
      System.debug(
        LoggingLevel.FINE,
        '[Controller] getGrandTotals unexpected error'
      );
      throw new AuraHandledException('Failed to retrieve grand totals.');
    }
  }

  /**
   * Enqueues an async Batch Apex job to export table data as CSV
   * via ContentVersion chunks.
   *
   * @param tableName    Table config name
   * @param parentId     Optional parent record Id
   * @param filtersJson  Optional filter payload JSON
   * @param columnKeysJson Optional JSON array of visible column keys in UI order
   * @return String      The Batch Job ID for tracking
   */
  @AuraEnabled
  public static String exportTableViaEmail(
    String tableName,
    String parentId,
    String filtersJson,
    String matrixParamsJson,
    String searchTerm,
    String columnKeysJson
  ) {
    try {
      ExportOrchestrator.AsyncResult asyncResult = ExportOrchestrator.runAsync(
        tableName,
        parentId,
        filtersJson,
        matrixParamsJson,
        searchTerm,
        columnKeysJson
      );
      return asyncResult.jobId;
    } catch (ExportErrors.ExportException ex) {
      throw new AuraHandledException(ex.userMessage);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (DynamicTableService.DynamicTableException dex) {
      throw new AuraHandledException(dex.getMessage());
    } catch (Exception ex) {
      String errorRef = DynamicTableErrorLogger.logException(
        'DynamicTableController',
        'exportTableViaEmail',
        ex,
        new Map<String, Object>{
          'methodName' => 'exportTableViaEmail',
          'operation' => 'controllerFallback',
          'tableName' => tableName,
          'parentId' => parentId,
          'hasFilters' => String.isNotBlank(filtersJson)
        }
      );

      throw new AuraHandledException(
        'An unexpected error occurred. Please contact your administrator. Error Reference: ' +
        errorRef
      );
    }
  }

  /**
   * Logs a client-side export for audit tracking.
   */
  @AuraEnabled
  public static void logClientExport(
    String tableName,
    Integer recordCount,
    Boolean isMatrixMode
  ) {
    try {
      Table_Export_Log__c log = new Table_Export_Log__c(
        User__c = UserInfo.getUserId(),
        Table_Name__c = tableName,
        Record_Count__c = recordCount,
        Export_Type__c = isMatrixMode ? 'Matrix' : 'Client',
        Status__c = 'Completed',
        Progress_Percentage__c = 100,
        Started_Time__c = Datetime.now(),
        Completed_Time__c = Datetime.now()
      );
      insert log;
    } catch (Exception ex) {
      System.debug(LoggingLevel.FINE, '[Controller] logClientExport error');
    }
  }

  // ── Table Configuration Management ────────────────────────────────────────

  /**
   * Returns all configured tables for the dashboard.
   */
  @AuraEnabled(cacheable=true)
  public static List<Table__c> getAllTables() {
    try {
      return DynamicTableSelector.getAllTables();
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (DynamicTableService.DynamicTableException dex) {
      throw new AuraHandledException(dex.getMessage());
    } catch (Exception ex) {
      String errorRef = DynamicTableErrorLogger.logException(
        'DynamicTableController',
        'getAllTables',
        ex,
        new Map<String, Object>{
          'methodName' => 'getAllTables',
          'operation' => 'controllerFallback'
        }
      );

      throw new AuraHandledException(
        'An unexpected error occurred. Please contact your administrator. Error Reference: ' +
        errorRef
      );
    }
  }

  @AuraEnabled
  public static Map<String, Object> getTableMetadata(Id tableId) {
    try {
      Table__c table = DynamicTableSelector.getTableById(tableId);
      List<Table_Columns__c> columns = DynamicTableSelector.getColumnsByTableId(
        tableId
      );
      List<Table_Action__c> actions = DynamicTableSelector.getActionsByTableId(
        tableId
      );
      return new Map<String, Object>{
        'table' => table,
        'columns' => columns,
        'actions' => actions
      };
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (DynamicTableService.DynamicTableException dex) {
      throw new AuraHandledException(dex.getMessage());
    } catch (Exception ex) {
      String errorRef = DynamicTableErrorLogger.logException(
        'DynamicTableController',
        'getTableMetadata',
        ex,
        new Map<String, Object>{
          'methodName' => 'getTableMetadata',
          'operation' => 'controllerFallback',
          'tableId' => tableId
        }
      );

      throw new AuraHandledException(
        'An unexpected error occurred. Please contact your administrator. Error Reference: ' +
        errorRef
      );
    }
  }

  /**
   * Saves the entire table configuration.
   */
  @AuraEnabled
  public static void saveMetadata(
    Table__c table,
    List<Table_Columns__c> columns,
    List<Table_Action__c> actions,
    List<String> deletedIds,
    List<String> deletedActionIds
  ) {
    try {
      DynamicTableService.saveMetadata(
        table,
        columns,
        actions,
        deletedIds,
        deletedActionIds
      );
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (DynamicTableService.DynamicTableException dex) {
      throw new AuraHandledException(dex.getMessage());
    } catch (Exception ex) {
      String errorRef = DynamicTableErrorLogger.logException(
        'DynamicTableController',
        'saveMetadata',
        ex,
        new Map<String, Object>{
          'methodName' => 'saveMetadata',
          'operation' => 'controllerFallback'
        }
      );

      throw new AuraHandledException(
        'An unexpected error occurred. Please contact your administrator. Error Reference: ' +
        errorRef
      );
    }
  }

  @AuraEnabled
  public static DynamicTableDTO.ImportResult importTableData(
    String tableName,
    String dataMappingJson,
    String csvDataJson,
    String parentId,
    String operation,
    String upsertKey
  ) {
    try {
      System.debug(
        LoggingLevel.FINE,
        '[Controller] importTableData → tableName'
      );
      return DynamicTableImportService.importData(
        tableName,
        dataMappingJson,
        csvDataJson,
        parentId,
        operation,
        upsertKey
      );
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (DynamicTableService.DynamicTableException dex) {
      throw new AuraHandledException(dex.getMessage());
    } catch (Exception ex) {
      String errorRef = DynamicTableErrorLogger.logException(
        'DynamicTableController',
        'importTableData',
        ex,
        new Map<String, Object>{
          'methodName' => 'importTableData',
          'operation' => 'controllerFallback',
          'tableName' => tableName,
          'parentId' => parentId,
          'hasPayload' => String.isNotBlank(csvDataJson)
        }
      );

      throw new AuraHandledException(
        'An unexpected error occurred. Please contact your administrator. Error Reference: ' +
        errorRef
      );
    }
  }

  @AuraEnabled
  public static DynamicTableDTO.ImportMetadata getImportMetadata(
    String tableName
  ) {
    try {
      System.debug(
        LoggingLevel.FINE,
        '[Controller] getImportMetadata → tableName'
      );
      return DynamicTableService.getImportMetadata(tableName);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (DynamicTableService.DynamicTableException dex) {
      throw new AuraHandledException(dex.getMessage());
    } catch (Exception ex) {
      String errorRef = DynamicTableErrorLogger.logException(
        'DynamicTableController',
        'getImportMetadata',
        ex,
        new Map<String, Object>{
          'methodName' => 'getImportMetadata',
          'operation' => 'controllerFallback',
          'tableName' => tableName
        }
      );

      throw new AuraHandledException(
        'An unexpected error occurred. Please contact your administrator. Error Reference: ' +
        errorRef
      );
    }
  }
  /**
   * Executes a configurable Apex action for a set of records.
   *
   * @param actionId   The ID of the Table_Action__c record.
   * @param recordIds  IDs of the records selected in the UI.
   */
  @AuraEnabled
  public static DynamicTableDTO.ActionResponse executeTableAction(
    String actionId,
    List<Id> recordIds
  ) {
    try {
      return DynamicTableService.executeTableAction(actionId, recordIds);
    } catch (Exception ex) {
      throw new AuraHandledException(
        'An internal server error occurred. Please contact support.'
      );
    }
  }

  /**
   * Clones a Table__c record and its related configurations.
   */
  @AuraEnabled
  public static void cloneTableConfig(Id tableId) {
    try {
      DynamicTableService.cloneTableConfig(tableId);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (DynamicTableService.DynamicTableException dex) {
      throw new AuraHandledException(dex.getMessage());
    } catch (Exception ex) {
      String errorRef = DynamicTableErrorLogger.logException(
        'DynamicTableController',
        'cloneTableConfig',
        ex,
        new Map<String, Object>{
          'methodName' => 'cloneTableConfig',
          'operation' => 'controllerFallback',
          'tableId' => tableId
        }
      );

      throw new AuraHandledException(
        'An unexpected error occurred. Please contact your administrator. Error Reference: ' +
        errorRef
      );
    }
  }

  /**
   * Deletes a Table__c record and all its child Table_Columns__c via cascade.
   *
   * @param tableId  ID of the Table__c record to delete.
   */
  @AuraEnabled
  public static void deleteTableConfig(Id tableId) {
    try {
      Table__c tbl = [
        SELECT Id
        FROM Table__c
        WHERE Id = :tableId
        WITH USER_MODE
        LIMIT 1
      ];
      delete as user tbl;
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (DynamicTableService.DynamicTableException dex) {
      throw new AuraHandledException(dex.getMessage());
    } catch (Exception ex) {
      String errorRef = DynamicTableErrorLogger.logException(
        'DynamicTableController',
        'deleteTableConfig',
        ex,
        new Map<String, Object>{
          'methodName' => 'deleteTableConfig',
          'operation' => 'controllerFallback',
          'tableId' => tableId
        }
      );

      throw new AuraHandledException(
        'An unexpected error occurred. Please contact your administrator. Error Reference: ' +
        errorRef
      );
    }
  }

  /**
   * Returns a list of fields for a given object API name.
   * Used in configurator for lookup fields to show parent object fields.
   */
  @AuraEnabled(cacheable=true)
  public static List<Map<String, String>> getObjectFields(
    String objectApiName
  ) {
    try {
      List<Map<String, String>> fieldOptions = new List<Map<String, String>>();
      SObjectType sObjType = DynamicTableService.getSObjectType(objectApiName);
      if (sObjType != null) {
        if (!sObjType.getDescribe().isAccessible())
          throw new AuraHandledException('Object is not accessible.');
        Map<String, Schema.SObjectField> fieldMap = DynamicTableService.getFieldMap(
          objectApiName
        );
        for (String fieldName : fieldMap.keySet()) {
          Schema.DescribeFieldResult fieldDesc = fieldMap.get(fieldName)
            .getDescribe();
          if (!fieldDesc.isAccessible())
            continue;
          String relName = fieldDesc.getRelationshipName();
          String refTo = '';
          List<Schema.sObjectType> refs = fieldDesc.getReferenceTo();
          if (refs != null && !refs.isEmpty()) {
            refTo = String.valueOf(refs[0]);
          }
          fieldOptions.add(
            new Map<String, String>{
              'label' => fieldDesc.getLabel() +
              ' (' +
              fieldDesc.getName() +
              ')',
              'value' => fieldDesc.getName(),
              'dataType' => String.valueOf(fieldDesc.getType()),
              'relationshipName' => relName,
              'referenceTo' => refTo
            }
          );
        }
      }
      return fieldOptions;
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (DynamicTableService.DynamicTableException dex) {
      throw new AuraHandledException(dex.getMessage());
    } catch (Exception ex) {
      String errorRef = DynamicTableErrorLogger.logException(
        'DynamicTableController',
        'getObjectFields',
        ex,
        new Map<String, Object>{
          'methodName' => 'getObjectFields',
          'operation' => 'controllerFallback',
          'objectApiName' => objectApiName
        }
      );

      throw new AuraHandledException(
        'An unexpected error occurred. Please contact your administrator. Error Reference: ' +
        errorRef
      );
    }
  }

  @AuraEnabled
  public static List<Table_Feature_Override__c> getFeatureOverrides(
    Id tableId
  ) {
    try {
      return [
        SELECT
          Id,
          Context_Type__c,
          Context_Value__c,
          Override_Enable_Export__c,
          Override_Enable_Import__c,
          Override_Enable_Filters__c,
          Override_New_Record__c,
          Override_Hide_Row_Actions__c,
          Override_Enable_Matrix_View__c,
          Override_Enable_Column_Manager__c,
          Override_Enable_Views__c
        FROM Table_Feature_Override__c
        WHERE Table__c = :tableId
        WITH USER_MODE
      ];
    } catch (Exception e) {
      AuraHandledException ahe = new AuraHandledException(e.getMessage());
      ahe.setMessage(e.getMessage());
      throw ahe;
    }
  }

  @AuraEnabled
  public static void saveFeatureOverride(
    Table_Feature_Override__c featureOverride
  ) {
    try {
      upsert as user featureOverride;
    } catch (Exception e) {
      throw new AuraHandledException(
        'An internal server error occurred. Please contact support.'
      );
    }
  }

  @AuraEnabled
  public static void deleteFeatureOverride(Id overrideId) {
    try {
      delete as user [
        SELECT Id
        FROM Table_Feature_Override__c
        WHERE Id = :overrideId
        WITH USER_MODE
      ];
    } catch (Exception e) {
      throw new AuraHandledException(
        'An internal server error occurred. Please contact support.'
      );
    }
  }

  // -----------------------------------------------------------------
  // exportAndSaveFile
  // -----------------------------------------------------------------
  @AuraEnabled(cacheable=false)
  public static DynamicTableDTO.ExportResult exportAndSaveFile(
    String exportRequestJson
  ) {
    DynamicTableDTO.ExportResult result = new DynamicTableDTO.ExportResult();
    try {
      DynamicTableDTO.ExportRequest req = (DynamicTableDTO.ExportRequest) JSON.deserialize(
        exportRequestJson,
        DynamicTableDTO.ExportRequest.class
      );

      if (String.isBlank(req.objectApiName)) {
        throw new AuraHandledException('objectApiName is required.');
      }
      if (req.columns == null || req.columns.isEmpty()) {
        throw new AuraHandledException('Columns must be defined for export.');
      }

      DynamicTableService svc = new DynamicTableService();
      String whereClause;
      List<String> fieldNames = new List<String>();

      if (String.isNotBlank(req.matrixParamsJson)) {
        req.objectApiName = DynamicTableSecurity.validateObjectApiName(
          req.objectApiName,
          true
        );
        whereClause = svc.buildWhereClause(
          req.filters,
          req.logic,
          req.customLogic
        );
      } else {
        DynamicTableSecurity.ValidatedExportRequest safeReq = DynamicTableSecurity.validateExportRequest(
          req
        );
        req.objectApiName = safeReq.objectApiName;
        req.columns = safeReq.columns;
        req.filters = safeReq.filters;
        req.sortField = safeReq.sortField;
        fieldNames = safeReq.fieldApiNames;
        whereClause = svc.buildWhereClause(
          req.filters,
          req.logic,
          req.customLogic
        );
      }

      // Append Parent Record Filter (parentId) if present
      if (String.isNotBlank(req.parentId)) {
        try {
          Id pId = (Id) req.parentId;
          String parentObjName = pId.getSObjectType().getDescribe().getName();
          String parentFilterField = DynamicTableService.autoDetectParentLookup(
            req.objectApiName,
            parentObjName
          );
          if (String.isNotBlank(parentFilterField)) {
            String parentCondition =
              parentFilterField +
              ' = \'' +
              String.escapeSingleQuotes(req.parentId) +
              '\'';
            if (String.isNotBlank(whereClause)) {
              whereClause = parentCondition + ' AND (' + whereClause + ')';
            } else {
              whereClause = parentCondition;
            }
          }
        } catch (Exception ex) {
          System.debug(
            LoggingLevel.FINE,
            'Error resolving parent filter in export'
          );
        }
      }

      // Append Search Term Filter (searchTerm) if present
      List<String> searchClauses = new List<String>();
      if (String.isNotBlank(req.searchTerm)) {
        String escapedSearchTerm =
          '%' +
          String.escapeSingleQuotes(req.searchTerm.trim()) +
          '%';
        Schema.SObjectType objType = DynamicTableService.getSObjectType(
          req.objectApiName
        );
        if (objType != null) {
          Map<String, Schema.SObjectField> fieldMap = DynamicTableService.getFieldMap(
            req.objectApiName
          );
          for (DynamicTableDTO.ExportColumnConfig col : req.columns) {
            if (
              String.isNotBlank(col.fieldApiName) &&
              !col.fieldApiName.contains('.')
            ) {
              Schema.SObjectField sField = fieldMap.get(
                col.fieldApiName.toLowerCase()
              );
              if (sField != null && sField.getDescribe().isFilterable()) {
                searchClauses.add(
                  col.fieldApiName + ' LIKE \'' + escapedSearchTerm + '\''
                );
              }
            }
          }
        }
      }
      if (!searchClauses.isEmpty()) {
        String searchCondition = '(' + String.join(searchClauses, ' OR ') + ')';
        if (String.isNotBlank(whereClause)) {
          whereClause = '(' + whereClause + ') AND ' + searchCondition;
        } else {
          whereClause = searchCondition;
        }
      }

      String countSoql =
        'SELECT COUNT() FROM ' + String.escapeSingleQuotes(req.objectApiName);
      if (String.isNotBlank(whereClause)) {
        countSoql += ' WHERE ' + whereClause;
      }
      countSoql += ' LIMIT 45000';
      ExportSettings exportSettings = ExportSettings.load();
      Integer exportCount = Database.countQuery(
        countSoql,
        AccessLevel.USER_MODE
      );
      if (exportCount == 0) {
        throw new AuraHandledException(
          ExportErrors.userMessage(ExportErrors.ERR_EMPTY_DATASET, null)
        );
      }
      Boolean matrixExportRequested = String.isNotBlank(req.matrixParamsJson);
      if (
        !matrixExportRequested &&
        exportSettings.maxStandardExportRows != null &&
        exportSettings.maxStandardExportRows > 0 &&
        exportCount > exportSettings.maxStandardExportRows
      ) {
        String msg = ExportErrors.userMessage(
          ExportErrors.ERR_EXPORT_ROW_LIMIT_EXCEEDED,
          ExportErrors.rowLimitMessage(
            exportCount,
            exportSettings.maxStandardExportRows
          )
        );
        AuraHandledException ahe = new AuraHandledException(msg);
        ahe.setMessage(msg);
        throw ahe;
      }

      ExportOrchestrator.ExportDecision decision = ExportOrchestrator.resolve(
        exportCount,
        matrixExportRequested,
        exportCount <= exportSettings.syncRowLimit
      );
      if (decision.isAsync == true) {
        String msg = ExportErrors.backgroundRequiredMessage(exportCount);
        AuraHandledException ahe = new AuraHandledException(msg);
        ahe.setMessage(msg);
        throw ahe;
      }

      DynamicTableSelector sel = new DynamicTableSelector();
      String csvData;
      Integer totalRows = 0;

      if (String.isNotBlank(req.matrixParamsJson)) {
        DynamicTableDTO.MatrixRequest matrixReq = new DynamicTableDTO.MatrixRequest();
        matrixReq.objectApiName = req.objectApiName;
        matrixReq.parentId = req.parentId;
        matrixReq.logic = req.logic;

        DynamicTableDTO.MatrixParams matrixParams = (DynamicTableDTO.MatrixParams) JSON.deserialize(
          req.matrixParamsJson,
          DynamicTableDTO.MatrixParams.class
        );
        matrixReq.rowGroupFields = new List<DynamicTableDTO.MatrixGroupField>();
        if (matrixParams.rowFields != null) {
          for (String rf : matrixParams.rowFields) {
            if (String.isNotBlank(rf)) {
              DynamicTableDTO.MatrixGroupField mgf = new DynamicTableDTO.MatrixGroupField();
              mgf.fieldApiName = rf;
              if (matrixParams.granularityMap != null) {
                for (String key : matrixParams.granularityMap.keySet()) {
                  if (
                    key != null &&
                    (key.equalsIgnoreCase(rf) ||
                    key.replace('_', '').equalsIgnoreCase(rf.replace('_', '')))
                  ) {
                    mgf.granularity = matrixParams.granularityMap.get(key);
                    break;
                  }
                }
              }
              matrixReq.rowGroupFields.add(mgf);
            }
          }
        }
        matrixReq.colGroupFields = new List<DynamicTableDTO.MatrixGroupField>();
        if (matrixParams.columnFields != null) {
          for (String cf : matrixParams.columnFields) {
            if (String.isNotBlank(cf)) {
              DynamicTableDTO.MatrixGroupField mgf = new DynamicTableDTO.MatrixGroupField();
              mgf.fieldApiName = cf;
              if (matrixParams.granularityMap != null) {
                for (String key : matrixParams.granularityMap.keySet()) {
                  if (
                    key != null &&
                    (key.equalsIgnoreCase(cf) ||
                    key.replace('_', '').equalsIgnoreCase(cf.replace('_', '')))
                  ) {
                    mgf.granularity = matrixParams.granularityMap.get(key);
                    break;
                  }
                }
              }
              matrixReq.colGroupFields.add(mgf);
            }
          }
        }
        matrixReq.summaryFields = new List<DynamicTableDTO.MatrixSummaryField>();
        if (
          matrixParams.aggregateFields == null ||
          matrixParams.aggregateFields.isEmpty()
        ) {
          matrixParams.aggregateFields = new List<String>();
          if (String.isNotBlank(matrixParams.aggregateField)) {
            matrixParams.aggregateFields.add(matrixParams.aggregateField);
          } else {
            matrixParams.aggregateFields.add('_recordCount');
          }
        }
        for (String af : matrixParams.aggregateFields) {
          DynamicTableDTO.MatrixSummaryField msf = new DynamicTableDTO.MatrixSummaryField();
          msf.fieldApiName = (af == '_recordCount') ? 'Id' : af;
          msf.aggregateFunction = (af == '_recordCount') ? 'COUNT' : 'SUM';
          matrixReq.summaryFields.add(msf);
        }

        matrixReq.filters = req.filters;
        matrixReq.includeSubtotals = true;

        List<DynamicTableDTO.ColumnConfig> colConfigs = new List<DynamicTableDTO.ColumnConfig>();
        if (String.isNotBlank(req.tableName)) {
          DynamicTableDTO.TableResult tr = DynamicTableService.getTableData(
            req.tableName,
            req.parentId
          );
          colConfigs = tr.columns;
        }

        String aggregateSoql = svc.buildAggregateQuery(
          matrixReq,
          colConfigs,
          req.searchTerm
        );

        List<AggregateResult> aggregateRows = sel.getAggregateRecords(
          aggregateSoql
        );
        DynamicTableDTO.MatrixResult aggregateResult = svc.buildMatrixResult(
          aggregateRows,
          matrixReq
        );

        DynamicTableMatrixService.MatrixResult meta = new DynamicTableMatrixService.MatrixResult();
        meta.rowFields = aggregateResult.rowFieldLabels;
        meta.columnFields = aggregateResult.colFieldLabels;
        meta.aggregateField = matrixParams.aggregateField;
        meta.aggregateLabel = String.isNotBlank(matrixParams.aggregateField)
          ? matrixParams.aggregateField
          : 'Count';
        meta.aggregateFields = matrixParams.aggregateFields;
        meta.aggregateLabels = aggregateResult.summaryLabels;
        meta.pivotColumns = new List<String>();

        Map<String, String> aliasToAggregateField = new Map<String, String>();
        for (Integer i = 0; i < aggregateResult.summaryAliases.size(); i++) {
          aliasToAggregateField.put(
            aggregateResult.summaryAliases[i],
            matrixParams.aggregateFields[i]
          );
        }

        for (List<String> colParts : aggregateResult.colKeys) {
          meta.pivotColumns.add(String.join(colParts, '|'));
        }
        meta.pivotColumns.sort();

        Map<String, Map<String, Decimal>> csvDataMap = new Map<String, Map<String, Decimal>>();
        Map<String, List<String>> rowLabels = new Map<String, List<String>>();
        for (List<String> rowParts : aggregateResult.rowKeys) {
          String rowKey = String.join(rowParts, '|');
          rowLabels.put(rowKey, rowParts);
          csvDataMap.put(rowKey, new Map<String, Decimal>());
        }

        for (DynamicTableDTO.MatrixCell cell : aggregateResult.cells) {
          if (!csvDataMap.containsKey(cell.rowKey)) {
            csvDataMap.put(cell.rowKey, new Map<String, Decimal>());
          }
          String aggregateField = aliasToAggregateField.get(cell.alias);
          String dataKey = String.isBlank(cell.colKey)
            ? aggregateField
            : (cell.colKey + '|' + aggregateField);
          csvDataMap.get(cell.rowKey).put(dataKey, cell.value);
        }

        csvData = String.join(
          DynamicTableMatrixService.buildCSV(meta, csvDataMap, rowLabels),
          '\n'
        );
        totalRows = aggregateResult.rowKeys.size();
      } else {
        List<SObject> records = sel.getExportRecords(
          fieldNames,
          req.objectApiName,
          whereClause,
          req.sortField,
          req.sortDirection
        );
        csvData = svc.buildCsvString(records, req.columns);
        totalRows = records.size();
      }

      String safeName = String.isBlank(req.objectApiName)
        ? 'Export'
        : req.objectApiName;
      safeName = safeName.replaceAll('[^a-zA-Z0-9_\\-]', '_');

      String timestamp = DateTime.now().format('yyyyMMdd_HHmmss');
      String fullFileName = safeName + '_' + timestamp + '.csv';

      ContentVersion cv = new ContentVersion();
      cv.Title = fullFileName;
      cv.PathOnClient = fullFileName;
      cv.VersionData = Blob.valueOf(csvData);
      cv.IsMajorVersion = true;
      cv.SharingOption = 'R';

      insert cv;

      ContentVersion inserted = [
        SELECT Id, ContentDocumentId
        FROM ContentVersion
        WHERE Id = :cv.Id
        LIMIT 1
      ];

      result.success = true;
      result.contentVersionId = inserted.Id;
      result.fileName = fullFileName;
      result.totalRows = totalRows;
      result.outputFormat = 'CSV';
      result.decisionReason = decision.outputFormat == 'XLSX'
        ? 'XLSX rendering requires an approved Apex OpenXML library; generated CSV using the existing renderer.'
        : decision.decisionReason;
      result.matrixDowngraded = decision.matrixDowngraded;
      return result;
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (Exception e) {
      System.debug(LoggingLevel.FINE, 'Export and Save error');
      AuraHandledException ahe = new AuraHandledException(e.getMessage());
      ahe.setMessage(e.getMessage());
      throw ahe;
    }
  }

  @AuraEnabled(cacheable=true)
  public static DynamicTableDTO.MatrixResult getMatrixData(
    Id tableId,
    String parentId,
    String matrixConfigJson
  ) {
    try {
      return MatrixOrchestrator.getSyncMatrixData(
        tableId,
        parentId,
        matrixConfigJson
      );
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (MatrixProcessingException mpe) {
      AuraHandledException ahe = new AuraHandledException(mpe.getMessage());
      ahe.setMessage(mpe.getMessage());
      throw ahe;
    } catch (DynamicTableService.MatrixQueryException mqe) {
      AuraHandledException ahe = new AuraHandledException(mqe.getMessage());
      ahe.setMessage(mqe.getMessage());
      throw ahe;
    } catch (Exception e) {
      System.debug(LoggingLevel.FINE, 'getMatrixData error');
      String msg = 'Matrix data load failed: ' + e.getMessage();
      AuraHandledException ahe = new AuraHandledException(msg);
      ahe.setMessage(msg);
      throw ahe;
    }
  }

  @AuraEnabled
  public static DynamicTableDTO.MatrixResponse requestMatrixData(
    Id tableId,
    String parentId,
    String matrixConfigJson
  ) {
    try {
      return MatrixOrchestrator.requestMatrixData(
        tableId,
        parentId,
        matrixConfigJson
      );
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (MatrixProcessingException mpe) {
      AuraHandledException ahe = new AuraHandledException(mpe.getMessage());
      ahe.setMessage(mpe.getMessage());
      throw ahe;
    } catch (Exception ex) {
      String msg = 'Matrix request failed: ' + ex.getMessage();
      AuraHandledException ahe = new AuraHandledException(msg);
      ahe.setMessage(msg);
      throw ahe;
    }
  }

  @AuraEnabled
  public static DynamicTableDTO.MatrixJobStatus getMatrixJobStatus(
    String jobId
  ) {
    try {
      return MatrixCacheService.getJobStatus(jobId);
    } catch (MatrixProcessingException mpe) {
      throw new AuraHandledException(mpe.getMessage());
    }
  }

  @AuraEnabled(cacheable=true)
  public static DynamicTableDTO.MatrixResult getMatrixJobResult(String jobId) {
    try {
      return MatrixCacheService.getJobResult(jobId);
    } catch (MatrixProcessingException mpe) {
      throw new AuraHandledException(mpe.getMessage());
    }
  }

  @AuraEnabled
  public static DynamicTableDTO.BrowserDownloadResult exportMatrixJobCsv(
    String jobId
  ) {
    try {
      return MatrixBrowserExportService.exportJobCsv(jobId);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (MatrixProcessingException mpe) {
      throw new AuraHandledException(mpe.getMessage());
    } catch (Exception ex) {
      throw new AuraHandledException(
        'Matrix export failed: ' + ex.getMessage()
      );
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<Map<String, String>> getPicklistOptions(
    String objectApiName,
    String fieldApiName
  ) {
    try {
      return DynamicTableService.resolvePicklistValues(
        objectApiName,
        fieldApiName
      );
    } catch (Exception ex) {
      throw new AuraHandledException(
        'An internal server error occurred. Please contact support.'
      );
    }
  }

  /**
   * Dynamically queries and returns a map of ID to Name field for any Salesforce SObject.
   * Used to resolve lookup filter value record IDs into readable labels on load.
   */
  @AuraEnabled(cacheable=true)
  public static Map<String, String> getRecordNames(List<Id> recordIds) {
    Map<String, String> idToNameMap = new Map<String, String>();
    if (recordIds == null || recordIds.isEmpty()) {
      return idToNameMap;
    }

    // Group IDs by SObject Type
    Map<String, List<Id>> sObjectToIds = new Map<String, List<Id>>();
    for (Id recId : recordIds) {
      if (recId != null) {
        String objName = recId.getSObjectType().getDescribe().getName();
        if (!sObjectToIds.containsKey(objName)) {
          sObjectToIds.put(objName, new List<Id>());
        }
        sObjectToIds.get(objName).add(recId);
      }
    }

    if (sObjectToIds.size() > 20)
      throw new AuraHandledException('Too many object types.');

    // For each SObject Type, query the Name field
    for (String objName : sObjectToIds.keySet()) {
      List<Id> ids = sObjectToIds.get(objName);
      String nameField = 'Name';
      SObjectType sObjType = Schema.getGlobalDescribe().get(objName);
      if (sObjType == null)
        continue;
      if (!sObjType.getDescribe().isAccessible())
        continue;

      Map<String, Schema.SObjectField> fieldMap = sObjType.getDescribe()
        .fields.getMap();
      for (Schema.SObjectField field : fieldMap.values()) {
        Schema.DescribeFieldResult dfr = field.getDescribe();
        if (dfr.isNameField()) {
          nameField = dfr.getName();
          break;
        }
      }

      if (
        fieldMap.get(nameField.toLowerCase()) == null ||
        !fieldMap.get(nameField.toLowerCase()).getDescribe().isAccessible()
      )
        continue;

      String query =
        'SELECT Id, ' +
        nameField +
        ' FROM ' +
        objName +
        ' WHERE Id IN :ids';
      try {
        List<SObject> records = Database.query(query, AccessLevel.USER_MODE);
        for (SObject rec : records) {
          idToNameMap.put((String) rec.get('Id'), (String) rec.get(nameField));
        }
      } catch (Exception ex) {
        System.debug(LoggingLevel.FINE, 'Error querying names for');
      }
    }
    return idToNameMap;
  }

  /**
   * Retrieves all saved views for a given table name, belonging to the current user.
   */
  @AuraEnabled
  public static List<DynamicTableDTO.UserViewDTO> getUserViews(
    String tableName
  ) {
    try {
      List<Table_User_View__c> views = DynamicTableSelector.getUserViewsByTableName(
        tableName
      );
      List<DynamicTableDTO.UserViewDTO> dtos = new List<DynamicTableDTO.UserViewDTO>();
      for (Table_User_View__c view : views) {
        DynamicTableDTO.UserViewDTO dto = new DynamicTableDTO.UserViewDTO();
        dto.id = view.Id;
        dto.name = view.Name;
        dto.filterPayloadJson = view.Filter_Payload_JSON__c;
        dto.columnStateJson = view.Column_State_JSON__c;
        dto.matrixConfigJson = view.Matrix_Config_JSON__c;
        dto.sortKey = view.Sort_Key__c;
        dto.sortDirection = view.Sort_Direction__c;
        dto.isDefault = view.Is_Default__c;
        dto.description = view.Description__c;
        dtos.add(dto);
      }
      return dtos;
    } catch (Exception ex) {
      throw new AuraHandledException(
        'Failed to load user views: ' + ex.getMessage()
      );
    }
  }

  /**
   * Saves a user view. If isDefault is true, all other user views for this table name are unmarked as default.
   */
  @AuraEnabled
  public static DynamicTableDTO.UserViewDTO saveUserView(
    String tableName,
    String viewName,
    String filterPayloadJson,
    String columnStateJson,
    String matrixConfigJson,
    String sortKey,
    String sortDir,
    Boolean isDefault,
    String description
  ) {
    try {
      if (String.isBlank(tableName)) {
        throw new AuraHandledException('Table name is required.');
      }
      if (String.isBlank(viewName)) {
        throw new AuraHandledException('View name is required.');
      }

      // If isDefault is true, uncheck Is_Default__c on all existing views for this table name
      if (isDefault == true) {
        List<Table_User_View__c> existingViews = DynamicTableSelector.getUserViewsByTableName(
          tableName
        );
        List<Table_User_View__c> updates = new List<Table_User_View__c>();
        for (Table_User_View__c ev : existingViews) {
          if (ev.Is_Default__c == true) {
            ev.Is_Default__c = false;
            updates.add(ev);
          }
        }
        if (!updates.isEmpty()) {
          update updates;
        }
      }

      Table_User_View__c newView = new Table_User_View__c(
        Name = viewName.trim(),
        Table_Name__c = tableName.trim(),
        Filter_Payload_JSON__c = filterPayloadJson,
        Column_State_JSON__c = columnStateJson,
        Matrix_Config_JSON__c = matrixConfigJson,
        Sort_Key__c = sortKey,
        Sort_Direction__c = sortDir,
        Is_Default__c = (isDefault == true),
        Description__c = description
      );

      insert newView;

      DynamicTableDTO.UserViewDTO dto = new DynamicTableDTO.UserViewDTO();
      dto.id = newView.Id;
      dto.name = newView.Name;
      dto.filterPayloadJson = newView.Filter_Payload_JSON__c;
      dto.columnStateJson = newView.Column_State_JSON__c;
      dto.matrixConfigJson = newView.Matrix_Config_JSON__c;
      dto.sortKey = newView.Sort_Key__c;
      dto.sortDirection = newView.Sort_Direction__c;
      dto.isDefault = newView.Is_Default__c;
      dto.description = newView.Description__c;
      return dto;
    } catch (Exception ex) {
      throw new AuraHandledException(
        'Failed to save user view: ' + ex.getMessage()
      );
    }
  }

  /**
   * Updates an existing user view with the current table state.
   */
  @AuraEnabled
  public static DynamicTableDTO.UserViewDTO updateUserView(
    Id viewId,
    String tableName,
    String viewName,
    String filterPayloadJson,
    String columnStateJson,
    String matrixConfigJson,
    String sortKey,
    String sortDir,
    Boolean isDefault,
    String description
  ) {
    try {
      if (viewId == null) {
        throw new AuraHandledException('View Id is required.');
      }
      if (String.isBlank(tableName)) {
        throw new AuraHandledException('Table name is required.');
      }
      if (String.isBlank(viewName)) {
        throw new AuraHandledException('View name is required.');
      }

      Table_User_View__c view = DynamicTableSelector.getUserViewById(viewId);
      if (view == null) {
        throw new AuraHandledException('View not found.');
      }
      if (view.OwnerId != UserInfo.getUserId()) {
        throw new AuraHandledException(
          'You do not have permission to update this view.'
        );
      }

      if (isDefault == true) {
        List<Table_User_View__c> existingViews = DynamicTableSelector.getUserViewsByTableName(
          tableName
        );
        List<Table_User_View__c> updates = new List<Table_User_View__c>();
        for (Table_User_View__c ev : existingViews) {
          if (ev.Id != viewId && ev.Is_Default__c == true) {
            ev.Is_Default__c = false;
            updates.add(ev);
          }
        }
        if (!updates.isEmpty()) {
          update updates;
        }
      }

      view.Name = viewName.trim();
      view.Table_Name__c = tableName.trim();
      view.Filter_Payload_JSON__c = filterPayloadJson;
      view.Column_State_JSON__c = columnStateJson;
      view.Matrix_Config_JSON__c = matrixConfigJson;
      view.Sort_Key__c = sortKey;
      view.Sort_Direction__c = sortDir;
      view.Is_Default__c = (isDefault == true);
      view.Description__c = description;
      update view;

      DynamicTableDTO.UserViewDTO dto = new DynamicTableDTO.UserViewDTO();
      dto.id = view.Id;
      dto.name = view.Name;
      dto.filterPayloadJson = view.Filter_Payload_JSON__c;
      dto.columnStateJson = view.Column_State_JSON__c;
      dto.matrixConfigJson = view.Matrix_Config_JSON__c;
      dto.sortKey = view.Sort_Key__c;
      dto.sortDirection = view.Sort_Direction__c;
      dto.isDefault = view.Is_Default__c;
      dto.description = view.Description__c;
      return dto;
    } catch (Exception ex) {
      throw new AuraHandledException(
        'Failed to update user view: ' + ex.getMessage()
      );
    }
  }

  /**
   * Deletes a user view.
   */
  @AuraEnabled
  public static void deleteUserView(Id viewId) {
    try {
      if (viewId == null) {
        throw new AuraHandledException('View Id is required.');
      }
      Table_User_View__c view = DynamicTableSelector.getUserViewById(viewId);
      if (view == null) {
        throw new AuraHandledException('View not found.');
      }
      if (view.OwnerId != UserInfo.getUserId()) {
        throw new AuraHandledException(
          'You do not have permission to delete this view.'
        );
      }
      delete view;
    } catch (Exception ex) {
      throw new AuraHandledException(
        'Failed to delete user view: ' + ex.getMessage()
      );
    }
  }
}