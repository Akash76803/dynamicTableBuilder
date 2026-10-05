// [EXPORT FIX] - 2026-06-07 - Add USER_MODE to QueryLocator, validate field paths in buildSingleFilterClause
/**
 * SDTConfiguratorService
 * G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
 * Service layer G�� owns ALL business logic and orchestration.
 * Calls the Selector for data, transforms it, and returns DTOs.
 * Never called directly from LWC G�� goes through the Controller.
 *
 * Responsibilities:
 *   G�� Validate inputs
 *   G�� Resolve Schema metadata (relationship names, picklist values)
 *   G�� Build the dynamic SOQL field list (delegates execution to Selector)
 *   G�� Flatten SObject records into cell-based DTO rows
 *   G�� Filter by parentId when the component is placed on a record page
 *   G�� Orchestrate the lookup search flow
 *
 * Layer:  Service
 * Calls:  SDTConfiguratorSelector (data), Schema API (metadata)
 * Called by: SDTConfiguratorController (AuraEnabled entry point)
 */
public with sharing class SDTConfiguratorService {
  private static Map<String, List<Map<String, String>>> recordTypesCache = new Map<String, List<Map<String, String>>>();
  private static Map<String, Schema.SObjectType> sObjectTypeCache = new Map<String, Schema.SObjectType>();
  private static Map<String, Map<String, Schema.SObjectField>> fieldMapCache = new Map<String, Map<String, Schema.SObjectField>>();
  public static Boolean suppressErrorLogging = false;
  private static final Integer DEFAULT_MATRIX_PREVIEW_ROW_LIMIT = 200;
  private static final Integer DEFAULT_MATRIX_MAX_SUMMARY_FIELDS = 10;
  private String matrixObjectApiName;

  

  

  

  public static Schema.SObjectType getSObjectType(String objectName) {
    if (String.isBlank(objectName))
      return null;
    String lowerName = objectName.toLowerCase();
    if (!sObjectTypeCache.containsKey(lowerName)) {
      try {
        List<Schema.DescribeSObjectResult> describes = Schema.describeSObjects(
          new List<String>{ objectName }
        );
        if (!describes.isEmpty()) {
          sObjectTypeCache.put(lowerName, describes[0].getSObjectType());
        } else {
          sObjectTypeCache.put(lowerName, null);
        }
      } catch (Exception e) {
        sObjectTypeCache.put(lowerName, null);
      }
    }
    return sObjectTypeCache.get(lowerName);
  }

  public static Map<String, Schema.SObjectField> getFieldMap(
    String objectName
  ) {
    if (String.isBlank(objectName))
      return null;
    String lowerName = objectName.toLowerCase();
    if (!fieldMapCache.containsKey(lowerName)) {
      Schema.SObjectType objType = getSObjectType(objectName);
      if (objType != null) {
        fieldMapCache.put(lowerName, objType.getDescribe().fields.getMap());
      } else {
        fieldMapCache.put(lowerName, null);
      }
    }
    return fieldMapCache.get(lowerName);
  }

  

  

  // G��G�� Main table data method G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��

  /**
   * Builds column configs, executes the dynamic SOQL (filtered by parentId
   * when provided), and returns a fully flattened TableResult DTO.
   *
   * @param tableName   Name field on Table__c G�� identifies which config to use
   * @param parentId    Optional G�� when on a record page, filters child records
   *                    by this Id using the lookup field defined on the column config
   */
  

  

  // G��G�� Lookup search method G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��

  /**
   * Validates the object and field, then delegates search to Selector.
   * Returns a list of LookupSearchResult DTOs for the dropdown.
   */
  public static List<SDTConfiguratorDTO.LookupSearchResult> searchLookupRecords(
    String objectApiName,
    String searchTerm,
    String nameField
  ) {
    System.debug(LoggingLevel.FINE, '[Service] searchLookupRecords G�� object');

    List<SDTConfiguratorDTO.LookupSearchResult> results = new List<SDTConfiguratorDTO.LookupSearchResult>();

    if (String.isBlank(objectApiName) || String.isBlank(searchTerm)) {
      return results;
    }

    // Validate object exists
    Schema.SObjectType objType = getSObjectType(objectApiName);
    if (objType == null) {
      System.debug(LoggingLevel.FINE, '[Service] searchLookupRecords: unknown object');
      return results;
    }

    // Validate display field, fall back to Name
    String displayField = String.isNotBlank(nameField) ? nameField : 'Name';
    Map<String, Schema.SObjectField> fieldMap = getFieldMap(objectApiName);
    if (!fieldMap.containsKey(displayField.toLowerCase())) {
      System.debug(LoggingLevel.FINE, '[Service] searchLookupRecords: field');
      displayField = 'Name';
    }

    // Escape search term before passing to Selector
    String escapedTerm = String.escapeSingleQuotes(searchTerm);

    List<SObject> records;
    try {
      records = SDTConfiguratorSelector.searchLookup(
        objectApiName,
        displayField,
        escapedTerm
      );
    } catch (Exception ex) {
      System.debug(LoggingLevel.ERROR, '[SDTConfiguratorService.searchLookupRecords] ' + ex.getMessage() + ' | Stack: ' + ex.getStackTraceString());
      throw new AuraHandledException(
        'An unexpected error occurred while searching records. ' + ex.getMessage()
      );
    }

    for (SObject rec : records) {
      SDTConfiguratorDTO.LookupSearchResult res = new SDTConfiguratorDTO.LookupSearchResult();
      res.recordId = (String) rec.get('Id');
      res.displayName = (String) rec.get(displayField);
      results.add(res);
    }

    System.debug(LoggingLevel.FINE, '[Service] searchLookupRecords');
    return results;
  }

  // G��G�� Private: build one ColumnConfig DTO from a Table_Columns__c record G��G��G��

  

  // G��G�� Private: build the dynamic SOQL string G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��

  

  // G��G�� Private: flatten SObject records G�� DTO rows G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��

  

  

  /**
   * Executes a configurable Apex action.
   * Use reflection to instantiate the target handler class.
   */
  @AuraEnabled
  

  

  // G��G�� Private: Schema utilities G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��

  /**
   * Resolves the relationship name from a lookup field API name using Schema.Describe.
   * e.g. Contact__c G�� Contact__r,  AccountId G�� Account
   */
  

  /**
   * Helper to traverse dot-notation relationship fields and resolve the final target object and field name.
   */
  public static Map<String, String> resolveRelationshipField(
    String objectApiName,
    String fieldPath
  ) {
    Map<String, String> result = new Map<String, String>{
      'object' => objectApiName,
      'field' => fieldPath
    };
    if (
      String.isBlank(objectApiName) ||
      String.isBlank(fieldPath) ||
      !fieldPath.contains('.')
    ) {
      return result;
    }

    List<String> parts = fieldPath.split('\\.');
    String currentObject = objectApiName;

    for (Integer i = 0; i < parts.size() - 1; i++) {
      String relName = parts[i];
      Schema.SObjectType sot = getSObjectType(currentObject);
      if (sot == null) {
        return result;
      }
      Schema.DescribeSObjectResult describe = sot.getDescribe();
      Map<String, Schema.SObjectField> fieldsMap = describe.fields.getMap();

      String nextObject = null;
      for (Schema.SObjectField f : fieldsMap.values()) {
        Schema.DescribeFieldResult dfr = f.getDescribe();
        if (dfr.getType() == Schema.DisplayType.REFERENCE) {
          String rName = dfr.getRelationshipName();
          if (String.isNotBlank(rName) && rName.equalsIgnoreCase(relName)) {
            List<Schema.SObjectType> refs = dfr.getReferenceTo();
            if (refs != null && !refs.isEmpty()) {
              nextObject = refs[0].getDescribe().getName();
              break;
            }
          }
        }
      }

      if (nextObject == null) {
        // Fallback: relationship name might end with '__r' and field is '__c'
        String fieldCandidate = relName;
        if (relName.endsWithIgnoreCase('__r')) {
          fieldCandidate = relName.substring(0, relName.length() - 3) + '__c';
        } else {
          fieldCandidate = relName + 'Id';
        }
        Schema.SObjectField f = fieldsMap.get(fieldCandidate.toLowerCase());
        if (f != null) {
          Schema.DescribeFieldResult dfr = f.getDescribe();
          if (dfr.getType() == Schema.DisplayType.REFERENCE) {
            List<Schema.SObjectType> refs = dfr.getReferenceTo();
            if (refs != null && !refs.isEmpty()) {
              nextObject = refs[0].getDescribe().getName();
            }
          }
        }
      }

      if (nextObject != null) {
        currentObject = nextObject;
      } else {
        return result;
      }
    }

    result.put('object', currentObject);
    result.put('field', parts[parts.size() - 1]);
    return result;
  }

  /**
   * Returns active picklist values for a given object + field.
   */
  public static List<Map<String, String>> resolvePicklistValues(
    String objectApiName,
    String fieldApiName
  ) {
    List<Map<String, String>> options = new List<Map<String, String>>();
    if (String.isBlank(objectApiName) || String.isBlank(fieldApiName))
      return options;
    try {
      Map<String, String> resolved = resolveRelationshipField(objectApiName, fieldApiName);
      objectApiName = resolved.get('object');
      fieldApiName = resolved.get('field');
      if (fieldApiName.equalsIgnoreCase('RecordTypeId')) {
        String cacheKey = objectApiName.toLowerCase();
        if (recordTypesCache.containsKey(cacheKey)) {
          return recordTypesCache.get(cacheKey);
        }

        List<Map<String, String>> rtOptions = new List<Map<String, String>>();
        // Query all active record types for this object
        for (RecordType rt : [
          SELECT Id, Name
          FROM RecordType
          WHERE SobjectType = :objectApiName AND IsActive = TRUE
          ORDER BY Name
        ]) {
          rtOptions.add(
            new Map<String, String>{ 'label' => rt.Name, 'value' => rt.Id }
          );
        }
        recordTypesCache.put(cacheKey, rtOptions);
        return rtOptions;
      }

      Map<String, Schema.SObjectField> fieldMap = getFieldMap(objectApiName);
      if (fieldMap == null)
        return options;

      Schema.SObjectField sField = fieldMap.get(fieldApiName.toLowerCase());
      if (sField == null)
        return options;

      for (
        Schema.PicklistEntry entry : sField.getDescribe().getPicklistValues()
      ) {
        if (entry.isActive()) {
          options.add(
            new Map<String, String>{
              'label' => entry.getLabel(),
              'value' => entry.getValue()
            }
          );
        }
      }
      System.debug(LoggingLevel.FINE, '[Service] resolvePicklistValues');
    } catch (Exception ex) {
      System.debug(LoggingLevel.FINE, '[Service] resolvePicklistValues error');
    }
    return options;
  }

  

  /**
   * Traverses a resolved relationship on an SObject to read a parent field.
   * e.g. rec.getSObject('Contact__r').get('Name')
   */
  

  /**
   * Derives the SObject type name from a Salesforce record Id using prefix lookup.
   * e.g. '006...' G�� 'Opportunity', '003...' G�� 'Contact'
   * Falls back to Schema.describeSObjects for custom object prefix resolution.
   */
  

  // Add inside SDTConfiguratorService class

  /**
   * Receives a JSON array of SaveRequest from LWC.
   * Maps each request back to the real SObject + field names using
   * Table_Columns__c config (col.key G�� fieldName + lookupField).
   * Performs partial DML and returns a SaveResult.
   *
   * @param tableName   Same tableName used to load G�� needed to resolve col keys G�� fieldNames
   * @param recordsJson JSON-serialised List<SaveRequest>
   */
  

  

  // G��G�� Private: type-safe value casting G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��

  

  // G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
  // ADD these methods inside SDTConfiguratorService class
  // G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��

  /**
   * Server-side filtered table data.
   * Reuses ALL existing getTableData logic up to SOQL execution,
   * then appends dynamically built filter WHERE clauses.
   *
   * Called by: SDTConfiguratorController.getFilteredTableData
   *
   * @param tableName     Same tableName used to load the table
   * @param parentId      Optional parent record Id (same as getTableData)
   * @param filtersJson   JSON-serialised SDTConfiguratorDTO.FilterPayload
   *                      { logic: 'AND'|'OR', filters: [ FilterCriteriaGǪ ] }
   */
  

  // G��G�� Private: builds SOQL with both parent filter AND user filter criteria G��G��G��G��

  


  

  

  

  

  // G��G�� Private: builds a single SOQL clause for one FilterCriteria G��G��G��G��G��G��G��G��G��G��G��G��G��G��

  

  


  

  

  

  

  // G��G�� Private: filter clause helpers G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��

  

  

  /**
   * Converts an ISO date string from LWC into a SOQL-safe date/datetime literal.
   * Date:     2024-03-15              G�� 2024-03-15
   * DateTime: 2024-03-15T00:00:00Z   G�� 2024-03-15T00:00:00Z
   * No quotes G�� SOQL date literals are unquoted.
   */
  

  /**
   * Converts a comma-separated picklist value string into a
   * SOQL-safe IN list of quoted strings.
   * e.g. "Closed Won,Closed Lost" G�� ['Closed Won', 'Closed Lost']
   */
  

  // G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
  // Export QueryLocator & Record Counting
  // G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��

  /**
   * Returns the exact database record count for the given table and filters.
   * Avoids retrieving full records to prevent heap limit errors.
   */
  

  

  

  

  

  /**
   * Returns a Database.QueryLocator for batch export.
   * Reuses existing column config + query building logic.
   *
   * @param tableName    Table config name
   * @param parentId     Optional parent record Id
   * @param filtersJson  Optional filter payload JSON
   * @return Database.QueryLocator for batch processing
   */ 

  // G��G�� Custom exception G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��

  public class DynamicTableException extends Exception {
  }

  /**
   * Identifies all metadata required for a robust data import.
   * Includes all writable fields and available External IDs for relationships.
   */
  public static SDTConfiguratorDTO.ImportMetadata getImportMetadata(
    String tableName
  ) {
    Table__c table = SDTConfiguratorSelector.getTableByName(tableName);
    if (table == null)
      throw new DynamicTableException(
        'Table configuration "' + tableName + '" not found.'
      );

    SDTConfiguratorDTO.ImportMetadata result = new SDTConfiguratorDTO.ImportMetadata();
    result.objectApiName = table.Object_API_Name__c;
    result.allFields = new List<SDTConfiguratorDTO.ImportFieldInfo>();

    Schema.SObjectType sObjectType = getSObjectType(table.Object_API_Name__c);
    if (sObjectType == null)
      throw new DynamicTableException(
        'Object "' + result.objectApiName + '" not found in schema.'
      );

    Map<String, Schema.SObjectField> fieldsMap = getFieldMap(
      table.Object_API_Name__c
    );

    for (Schema.SObjectField field : fieldsMap.values()) {
      Schema.DescribeFieldResult dfr = field.getDescribe();

      // Allow Id for reference, but primary filter is createable/updateable
      Boolean isSystemId = dfr.getName().equalsIgnoreCase('Id');
      if (!isSystemId && !dfr.isCreateable() && !dfr.isUpdateable())
        continue;

      SDTConfiguratorDTO.ImportFieldInfo info = new SDTConfiguratorDTO.ImportFieldInfo();
      info.label = dfr.getLabel();
      info.apiName = dfr.getName();
      info.type = String.valueOf(dfr.getType());
      info.isLookup = (dfr.getType() == Schema.DisplayType.REFERENCE);

      if (info.isLookup) {
        info.relationshipName = dfr.getRelationshipName();
        List<Schema.SObjectType> refs = dfr.getReferenceTo();
        if (!refs.isEmpty()) {
          info.objectReference = refs[0].getDescribe().getName();
          info.externalIdFields = getExternalIdOptions(info.objectReference);
        }
      }
      result.allFields.add(info);
    }
    return result;
  }

  private static List<Map<String, String>> getExternalIdOptions(
    String objectName
  ) {
    List<Map<String, String>> results = new List<Map<String, String>>();
    Schema.SObjectType sObjectType = getSObjectType(objectName);
    if (sObjectType == null)
      return results;

    Map<String, Schema.SObjectField> fieldsMap = getFieldMap(objectName);
    for (Schema.SObjectField field : fieldsMap.values()) {
      Schema.DescribeFieldResult dfr = field.getDescribe();
      if (dfr.isExternalId()) {
        results.add(
          new Map<String, String>{
            'label' => dfr.getLabel(),
            'value' => dfr.getName()
          }
        );
      }
    }
    return results;
  }
  // G��G�� Table Configuration Management (NEW) G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��

  /**
   * Fetches the full metadata structure for a table.
   */
  

  /**
   * Saves the entire table configuration atomically.
   * Upserts the table, upserts the provided columns, and deletes the rest.
   */
  public static void saveMetadata(
    Table__c table,
    List<Table_Columns__c> columns,
    List<Table_Action__c> actions,
    List<String> deletedColumnIds,
    List<String> deletedActionIds
  ) {
    System.debug(LoggingLevel.FINE, '[Service] saveMetadata - Table');

    try {

          if (table == null) {
            throw new DynamicTableException('Table configuration cannot be empty.');
          }

          // 1. Save Table Header
          upsert as user table;

          // 2. Prepare Columns
          if (columns != null) {
            for (Table_Columns__c col : columns) {
              if (col == null) continue;
              if (col.Id == null) {
                col.Table_Name__c = table.Id;
              }
              // Ensure Data_Type__c is set (dropdown in LWC)
              if (String.isBlank(col.Data_Type__c)) {
                col.Data_Type__c = 'Text'; // safe fallback
              }
            }

            List<Table_Columns__c> colsToUpsert = new List<Table_Columns__c>();
            for (Table_Columns__c col : columns) {
              if (col != null) {
                colsToUpsert.add(col);
              }
            }
            if (!colsToUpsert.isEmpty()) {
              upsert as user colsToUpsert;
            }
          }

          // 3. Prepare Actions
          if (actions != null) {
            for (Table_Action__c action : actions) {
              if (action == null) continue;
              if (action.Id == null) {
                action.Table__c = table.Id;
              }
            }
            List<Table_Action__c> actionsToUpsert = new List<Table_Action__c>();
            for (Table_Action__c action : actions) {
              if (action != null) {
                actionsToUpsert.add(action);
              }
            }
            if (!actionsToUpsert.isEmpty()) {
              upsert as user actionsToUpsert;
            }
          }

          // 4. Handle Deletions (Columns)
          if (deletedColumnIds != null && !deletedColumnIds.isEmpty()) {
            List<Table_Columns__c> toDelete = [
              SELECT Id
              FROM Table_Columns__c
              WHERE Id IN :deletedColumnIds AND Table_Name__c = :table.Id
              WITH USER_MODE
            ];
            if (!toDelete.isEmpty()) {
              delete as user toDelete;
            }
          }

          // 5. Handle Deletions (Actions)
          if (deletedActionIds != null && !deletedActionIds.isEmpty()) {
            List<Table_Action__c> toDeleteActs = [
              SELECT Id
              FROM Table_Action__c
              WHERE Id IN :deletedActionIds AND Table__c = :table.Id
              WITH USER_MODE
            ];
            if (!toDeleteActs.isEmpty()) {
              delete as user toDeleteActs;
            }
          }

    } catch (DynamicTableException dex) {
      throw dex;
    } catch (Exception ex) {
      System.debug(LoggingLevel.ERROR, '[SDTConfiguratorService.saveMetadata] ' + ex.getMessage() + ' | Stack: ' + ex.getStackTraceString());
      throw new AuraHandledException(
        'An unexpected error occurred while saving table configuration. ' + ex.getMessage()
      );
    }
  }

  /**
   * Clones a table configuration, its columns, and its actions.
   */
  public static void cloneTableConfig(Id tableId) {
    Table__c tbl = SDTConfiguratorSelector.getTableById(tableId);
    if (tbl == null)
      throw new DynamicTableException('Table not found.');

    try {

          Table__c clonedTbl = tbl.clone(false, true, false, false);
          String newName = 'Copy - ' + tbl.Name;
          if (newName.length() > 80)
            newName = newName.substring(0, 80);
          clonedTbl.Name = newName;
          insert as user clonedTbl;

          List<Table_Columns__c> cols = SDTConfiguratorSelector.getColumnsByTableId(
            tableId
          );
          List<Table_Columns__c> clonedCols = new List<Table_Columns__c>();
          for (Table_Columns__c col : cols) {
            Table_Columns__c clonedCol = col.clone(false, true, false, false);
            clonedCol.Table_Name__c = clonedTbl.Id;
            clonedCols.add(clonedCol);
          }
          if (!clonedCols.isEmpty()) {
            insert as user clonedCols;
          }

          List<Table_Action__c> actions = SDTConfiguratorSelector.getActionsByTableId(
            tableId
          );
          List<Table_Action__c> clonedActions = new List<Table_Action__c>();
          for (Table_Action__c action : actions) {
            Table_Action__c clonedAction = action.clone(false, true, false, false);
            clonedAction.Table__c = clonedTbl.Id;
            clonedActions.add(clonedAction);
          }
          if (!clonedActions.isEmpty()) {
            insert as user clonedActions;
      
          }
    } catch (DynamicTableException dex) {
      throw dex;
    } catch (Exception ex) {
      System.debug(LoggingLevel.ERROR, '[SDTConfiguratorService.cloneTableConfig] ' + ex.getMessage() + ' | Stack: ' + ex.getStackTraceString());
      throw new AuraHandledException(
        'An unexpected error occurred while cloning table configuration. ' + ex.getMessage()
      );
    }
  }

  // G��G�� Helper: Resolve Access Overrides G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
  

  

  // -----------------------------------------------------------------
  // METHOD 1: buildWhereClause
  // -----------------------------------------------------------------
  

  

  

  

  

  // -----------------------------------------------------------------
  // METHOD 2: buildCsvString
  // -----------------------------------------------------------------
  

  

  

  // ============================================================
  
}
