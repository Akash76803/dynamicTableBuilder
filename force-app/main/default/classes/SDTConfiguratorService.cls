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

  private static Table_Virtual_Setting__mdt getVirtualSetting() {
    Table_Virtual_Setting__mdt setting = Table_Virtual_Setting__mdt.getInstance(
      'Default'
    );

    if (setting == null) {
      List<Table_Virtual_Setting__mdt> settings = [
        SELECT Matrix_Preview_Row_Limit__c, Matrix_Max_Summary_Fields__c
        FROM Table_Virtual_Setting__mdt
        LIMIT 1
      ];
      if (!settings.isEmpty()) {
        setting = settings[0];
      }
    }

    return setting;
  }

  public static Integer getMatrixPreviewRowLimit() {
    Integer configuredLimit;
    Table_Virtual_Setting__mdt setting = getVirtualSetting();

    if (setting != null && setting.Matrix_Preview_Row_Limit__c != null) {
      configuredLimit = setting.Matrix_Preview_Row_Limit__c.intValue();
    }

    return configuredLimit != null && configuredLimit > 0
      ? configuredLimit
      : DEFAULT_MATRIX_PREVIEW_ROW_LIMIT;
  }

  public static Integer getMatrixMaxSummaryFields() {
    Integer configuredLimit;
    Table_Virtual_Setting__mdt setting = getVirtualSetting();

    if (setting != null && setting.Matrix_Max_Summary_Fields__c != null) {
      configuredLimit = setting.Matrix_Max_Summary_Fields__c.intValue();
    }

    return configuredLimit != null && configuredLimit > 0
      ? configuredLimit
      : DEFAULT_MATRIX_MAX_SUMMARY_FIELDS;
  }

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

  private static Table__c validateAndFetchConfig(String tableName) {
    if (String.isBlank(tableName)) {
      throw new DynamicTableException(
        'Table Configuration Name (tableName) is required.'
      );
    }

    Table__c tableConfig = SDTConfiguratorSelector.resolveTableConfig(tableName);
    if (tableConfig == null) {
      throw new DynamicTableException(
        'No Table Configuration found with name: "' +
          tableName +
          '". Please check the Spelling in the App Builder "Table Configuration Name" property.'
      );
    }

    String baseObject = tableConfig.Object_API_Name__c;
    if (String.isBlank(baseObject)) {
      throw new DynamicTableException(
        'Object API Name is missing in Table Configuration: "' +
          tableName +
          '".'
      );
    }
    return tableConfig;
  }

  private static List<Table_Columns__c> fetchColumnConfigs(Id tableId) {
    List<Table_Columns__c> rawColumns = SDTConfiguratorSelector.getColumnsByTableId(
      tableId
    );
    if (rawColumns.isEmpty()) {
      throw new DynamicTableException(
        'No columns configured for table ID: ' + tableId
      );
    }
    return rawColumns;
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
  public static SDTConfiguratorDTO.TableResult getTableData(
    String tableName,
    String parentId
  ) {
    System.debug(LoggingLevel.FINE, '[Service] getTableData G�� tableName');

    // G��G�� 1. Validate & fetch Table__c config G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
    Table__c tableConfig = validateAndFetchConfig(tableName);
    String baseObject = tableConfig.Object_API_Name__c;
    System.debug(LoggingLevel.FINE, '[Service] Base object');

    // G��G�� 2. Fetch column configs G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
    List<Table_Columns__c> rawColumns = fetchColumnConfigs(tableConfig.Id);
    System.debug(LoggingLevel.FINE, '[Service] Column configs');

    // G��G�� 3. Build ColumnConfig DTOs + SOQL field list G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
    List<SDTConfiguratorDTO.ColumnConfig> columns = new List<SDTConfiguratorDTO.ColumnConfig>();
    List<String> soqlFields = new List<String>{ 'id' };
    Map<String, String> fieldNameToSoqlPath = new Map<String, String>();

    // Track the parent filter field G�� the lookup field on the base object
    // that points to the parent record (e.g. OpportunityId on OpportunityLineItem)
    String parentFilterField = null;
    String parentObjectType = String.isNotBlank(parentId)
      ? getObjectTypeFromId(parentId)
      : null;

    Integer colIndex = 0;

    for (Table_Columns__c col : rawColumns) {
      SDTConfiguratorDTO.ColumnConfig cc = buildColumnConfig(
        col,
        baseObject,
        colIndex
      );

      // =��� EXISTING METADATA-DRIVEN LOGIC
      if (
        String.isNotBlank(parentId) &&
        parentFilterField == null &&
        String.isNotBlank(col.Lookup_Field_API_Name__c) &&
        String.isNotBlank(parentObjectType) &&
        col.Object_Reference__c != null &&
        col.Object_Reference__c.equalsIgnoreCase(parentObjectType)
      ) {
        parentFilterField = col.Lookup_Field_API_Name__c;

        System.debug(LoggingLevel.FINE, '[Service] G�� Metadata Parent filter');
      }

      // Existing SOQL field logic (UNCHANGED)
      if (!col.Additional_Column__c) {
        if (String.isNotBlank(cc.relationshipName)) {
          // If Column_API_Name__c already has a dot (e.g. Contact.Name), use it directly
          String dotField;
          if (
            col.Column_API_Name__c != null &&
            col.Column_API_Name__c.contains('.')
          ) {
            dotField = col.Column_API_Name__c.toLowerCase();
          } else {
            dotField = (cc.relationshipName +
              '.' +
              col.Column_API_Name__c)
              .toLowerCase();
          }

          if (!soqlFields.contains(dotField)) {
            soqlFields.add(dotField);
          }
          cc.soqlFieldPath = dotField;

          if (String.isNotBlank(col.Lookup_Field_API_Name__c)) {
            String lookupField = col.Lookup_Field_API_Name__c.toLowerCase();
            if (!soqlFields.contains(lookupField)) {
              soqlFields.add(lookupField);
            }
          }
        } else {
          String baseField = col.Column_API_Name__c != null
            ? col.Column_API_Name__c.toLowerCase()
            : '';
          if (!soqlFields.contains(baseField)) {
            soqlFields.add(baseField);
          }
          cc.soqlFieldPath = baseField;

          if (String.isNotBlank(col.Lookup_Field_API_Name__c)) {
            String lookupField = col.Lookup_Field_API_Name__c.toLowerCase();
            if (!soqlFields.contains(lookupField)) {
              soqlFields.add(lookupField);
            }
          }
        }
      }

      if (cc.dataType == 'Lookup' && String.isNotBlank(cc.lookupField)) {
        fieldNameToSoqlPath.put(cc.fieldName, cc.lookupField);
        fieldNameToSoqlPath.put(cc.key, cc.lookupField);
      } else if (String.isNotBlank(cc.soqlFieldPath)) {
        fieldNameToSoqlPath.put(cc.fieldName, cc.soqlFieldPath);
        fieldNameToSoqlPath.put(cc.key, cc.soqlFieldPath);
      }

      columns.add(cc);
      colIndex++;
    }

    // =��� AUTO-DETECT fallback
    if (String.isNotBlank(parentId) && String.isBlank(parentFilterField)) {
      parentFilterField = autoDetectParentLookup(baseObject, parentObjectType);

      System.debug(LoggingLevel.FINE, '[Service] G�� Fallback Parent filter');
    }

    System.debug(LoggingLevel.FINE, '[Service] FINAL parentFilterField');

    // G��G�� 4. Build SOQL with optional parent WHERE filter and default filters G��G��G��G��
    SDTConfiguratorDTO.FilterPayload defaultFilterPayload = buildDefaultFilterPayload(
      rawColumns,
      columns
    );
    String soql = buildFilteredDataQuery(
      baseObject,
      soqlFields,
      parentId,
      parentFilterField,
      defaultFilterPayload,
      fieldNameToSoqlPath
    );

    // G��G�� 5. Execute query via Selector G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
    List<SObject> records = new List<SObject>();
    Boolean isVirtual = 'Virtual'.equalsIgnoreCase(tableConfig.Data_Load_Mode__c) || 
                        tableConfig.Enable_Infinite_Scroll__c == true;

    if (!isVirtual) {
      try {
        records = SDTConfiguratorSelector.queryRecords(soql);
      } catch (Exception ex) {
        if (!suppressErrorLogging) {
          DynamicTableErrorLogger.logException(
            'SDTConfiguratorService',
            'getTableData',
            ex,
            new Map<String, Object>{
              'tableName' => tableName,
              'parentId' => parentId,
              'baseObject' => baseObject
            }
          );
        }
        System.debug(LoggingLevel.ERROR, 'SDTConfiguratorService.getTableData query error: ' + ex.getMessage());
        throw new AuraHandledException(
          'Failed to load table data: ' + ex.getMessage()
        );
      }
    }

    // G��G�� 6. Flatten records G�� DTO rows G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
    List<SDTConfiguratorDTO.RowData> rows = isVirtual ? new List<SDTConfiguratorDTO.RowData>() : flattenRecords(records, columns);

    // G��G�� 7. Assemble result G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
    SDTConfiguratorDTO.TableResult result = new SDTConfiguratorDTO.TableResult();
    result.columns = columns;
    result.rows = rows;
    result.objectApiName = baseObject;
    result.tableName = tableConfig.Name;
    result.tableId = tableConfig.Id;
    result.parentId = parentId;
    result.parentFilterField = parentFilterField;
    result.defaultFilterPayload = defaultFilterPayload;

    // Map new UI Toggles
    result.hideRowActions = tableConfig.Hide_Row_Actions__c;
    result.illustrationName = tableConfig.Empty_State_Illustration__c;
    result.enableFilters = tableConfig.Enable_Filters__c != null
      ? tableConfig.Enable_Filters__c
      : true;
    result.enableMatrixView = tableConfig.Enable_Matrix_View__c != null
      ? tableConfig.Enable_Matrix_View__c
      : true;
    result.enableColumnManager = tableConfig.Enable_Column_Manager__c != null
      ? tableConfig.Enable_Column_Manager__c
      : true;
    result.enableViews = tableConfig.Enable_Views__c != null
      ? tableConfig.Enable_Views__c
      : true;
    result.enableImport = tableConfig.Enable_Import__c != null
      ? tableConfig.Enable_Import__c
      : true;
    result.enableExport = tableConfig.Enable_Export__c != null
      ? tableConfig.Enable_Export__c
      : true;
    result.enableNewRecord = tableConfig.Enable_New_Record__c != null
      ? tableConfig.Enable_New_Record__c
      : true;

    result.enableInfiniteScroll = tableConfig.Enable_Infinite_Scroll__c != null
      ? tableConfig.Enable_Infinite_Scroll__c
      : false;
    result.dataLoadMode = tableConfig.Data_Load_Mode__c != null
      ? tableConfig.Data_Load_Mode__c
      : 'Standard';
    result.matrixPreviewRowLimit = getMatrixPreviewRowLimit();

    // Map Custom Actions
    result.actions = new List<SDTConfiguratorDTO.TableAction>();
    for (
      Table_Action__c act : SDTConfiguratorSelector.getActionsByTableId(
        tableConfig.Id
      )
    ) {
      SDTConfiguratorDTO.TableAction dto = new SDTConfiguratorDTO.TableAction();
      dto.id = act.Id;
      dto.label = act.Label__c;
      dto.icon = String.isNotBlank(act.Icon__c)
        ? act.Icon__c
        : 'utility:forward';
      dto.type = act.Action_Type__c;
      dto.target = act.Target__c;
      dto.requiresSelection = act.Requires_Selection__c;
      result.actions.add(dto);
    }

    applyAccessOverrides(result, tableConfig);

    System.debug(LoggingLevel.FINE, '[Service] getTableData complete');
    return result;
  }

  public static String autoDetectParentLookup(
    String childObject,
    String parentObject
  ) {
    Schema.SObjectType objType = getSObjectType(childObject);
    if (objType == null)
      return null;

    Map<String, Schema.SObjectField> fieldMap = getFieldMap(childObject);

    for (String fieldName : fieldMap.keySet()) {
      Schema.DescribeFieldResult dfr = fieldMap.get(fieldName).getDescribe();

      if (dfr.getType() == Schema.DisplayType.REFERENCE) {
        for (Schema.SObjectType refObj : dfr.getReferenceTo()) {
          if (refObj.getDescribe().getName().equalsIgnoreCase(parentObject)) {
            System.debug(LoggingLevel.FINE, '[Service] =��� Auto detected lookup');
            return fieldName;
          }
        }
      }
    }

    return null;
  }

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
      
      throw new AuraHandledException(
        'An unexpected error occurred. Please contact your administrator. Error Reference: ' + ex.getMessage()
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

  public static SDTConfiguratorDTO.ColumnConfig buildColumnConfig(
    Table_Columns__c col,
    String baseObject,
    Integer colIndex
  ) {
    SDTConfiguratorDTO.ColumnConfig cc = new SDTConfiguratorDTO.ColumnConfig();
    cc.key = 'col' + colIndex;
    cc.label = col.Name;
    cc.fieldName = col.Column_API_Name__c;
    cc.dataType = col.Data_Type__c;
    cc.editable = col.Is_Editable__c;
    cc.sortable = col.Is_Sortable__c;
    cc.isGroupable = col.Is_Groupable__c == true;
    cc.additional = col.Additional_Column__c;
    cc.lookupField = col.Lookup_Field_API_Name__c;
    cc.objectReference = col.Object_Reference__c;
    cc.order = col.Index__c != null
      ? ((Decimal) col.Index__c).intValue()
      : colIndex;
    // =��� NEW: Map visibility, search, and filter fields
    cc.isVisible = col.Is_Visible__c != null ? col.Is_Visible__c : true; // default true
    cc.isSearchable = col.Is_Searchable__c != null
      ? col.Is_Searchable__c
      : false;
    cc.isFilterable = col.Is_Filterable__c != null
      ? col.Is_Filterable__c
      : false;
    cc.filterType = col.Filter_Type__c;
    cc.defaultFilterValue = col.Default_Filter_Value__c;

    // G��G�� SECURITY HARDENING: Bypass metadata if permissions are missing G��G��
    if (!col.Additional_Column__c) {
      Map<String, Schema.SObjectField> fieldMap = getFieldMap(baseObject);
      if (fieldMap != null) {
        // For lookups with dot paths (e.g. Contact.Name), check the lookup field itself
        String fieldToCheck = (col.Column_API_Name__c != null &&
          col.Column_API_Name__c.contains('.'))
          ? col.Lookup_Field_API_Name__c
          : col.Column_API_Name__c;
        Schema.SObjectField sField = fieldToCheck != null
          ? fieldMap.get(fieldToCheck.toLowerCase())
          : null;
        if (sField != null) {
          Schema.DescribeFieldResult dfr = sField.getDescribe();
          // If the user doesn't have Read access, hide the column entirely
          cc.isVisible = cc.isVisible && dfr.isAccessible();
          // If the user doesn't have Edit access, force Read-Only mode
          cc.editable = cc.editable && dfr.isUpdateable();
          // If the field is not filterable in SOQL, force isSearchable and isFilterable to false
          cc.isSearchable = cc.isSearchable && dfr.isFilterable();
          cc.isFilterable = cc.isFilterable && dfr.isFilterable();
        }
      }
    }

    // Type flags
    cc.isText = (col.Data_Type__c == 'Text');
    cc.isNumber = (col.Data_Type__c == 'Number');
    cc.isCurrency = (col.Data_Type__c == 'Currency');
    cc.isPercentage = (col.Data_Type__c == 'Percentage'); // =��� NEW
    cc.isDate = (col.Data_Type__c == 'Date');
    cc.isDateTime = (col.Data_Type__c == 'DateTime');
    cc.isBoolean = (col.Data_Type__c == 'Boolean');
    cc.isPicklist = (col.Data_Type__c == 'Picklist');
    cc.isNumeric = (cc.isNumber || cc.isCurrency || cc.isPercentage);
    cc.isLookup = (col.Data_Type__c == 'Lookup');
    cc.isPhone = (col.Data_Type__c == 'Phone'); // =��� NEW
    cc.isEmail = (col.Data_Type__c == 'Email'); // =��� NEW
    cc.isUrl = (col.Data_Type__c == 'Url'); // =��� NEW
    cc.isRichText = (col.Data_Type__c == 'RichText'); // =��� NEW
    cc.isLongText = (col.Data_Type__c == 'LongText');

    // Resolve relationship name for lookup/parent fields via Schema Describe
    if (
      String.isNotBlank(col.Lookup_Field_API_Name__c) &&
      String.isNotBlank(col.Object_Reference__c) &&
      !col.Additional_Column__c
    ) {
      cc.relationshipName = resolveRelationshipName(
        baseObject,
        col.Lookup_Field_API_Name__c
      );
      if (String.isBlank(cc.relationshipName)) {
        System.debug(LoggingLevel.FINE, '[Service] WARNING: could not resolve relationship for');
      }
    }

    // Picklist values
    if (cc.isPicklist && !col.Additional_Column__c) {
      String picklistObject = String.isNotBlank(col.Object_Reference__c)
        ? col.Object_Reference__c
        : baseObject;
      String picklistField = col.Column_API_Name__c;
      if (String.isNotBlank(picklistField) && picklistField.contains('.')) {
        picklistObject = baseObject;
      }
      cc.picklistOptions = resolvePicklistValues(
        picklistObject,
        picklistField
      );
    }

    System.debug(LoggingLevel.FINE, '[Service] buildColumnConfig');
    return cc;
  }

  // G��G�� Private: build the dynamic SOQL string G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��

  public static String buildDataQuery(
    String baseObject,
    List<String> soqlFields,
    String parentId,
    String parentFilterField
  ) {
    String soql =
      'SELECT ' +
      String.join(soqlFields, ', ') +
      ' FROM ' +
      baseObject;

    // Apply parent filter when both parentId and a matching lookup field are available
    if (String.isNotBlank(parentId) && String.isNotBlank(parentFilterField)) {
      String safeId = String.escapeSingleQuotes(parentId);
      soql += ' WHERE ' + parentFilterField + ' = \'' + safeId + '\'';
      System.debug(LoggingLevel.FINE, '[Service] Applied parent filter');
    }

    soql += ' LIMIT 2000';
    System.debug(LoggingLevel.FINE, '[Service] Final SOQL');
    return soql;
  }

  // G��G�� Private: flatten SObject records G�� DTO rows G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��

  public static List<SDTConfiguratorDTO.RowData> flattenRecords(
    List<SObject> records,
    List<SDTConfiguratorDTO.ColumnConfig> columns
  ) {
    List<SDTConfiguratorDTO.RowData> rows = new List<SDTConfiguratorDTO.RowData>();

    for (SObject rec : records) {
      SDTConfiguratorDTO.RowData row = new SDTConfiguratorDTO.RowData();
      row.recordId = (String) rec.get('Id');
      row.cells = new List<SDTConfiguratorDTO.CellData>();

      for (SDTConfiguratorDTO.ColumnConfig cc : columns) {
        row.cells.add(buildCellData(rec, cc));
      }

      rows.add(row);
    }

    System.debug(LoggingLevel.FINE, '[Service] flattenRecords');
    return rows;
  }

  private static SDTConfiguratorDTO.CellData buildCellData(
    SObject rec,
    SDTConfiguratorDTO.ColumnConfig cc
  ) {
    SDTConfiguratorDTO.CellData cell = new SDTConfiguratorDTO.CellData();
    cell.key = cc.key;
    cell.fieldName = cc.fieldName;
    cell.objectReference = cc.objectReference;
    cell.editable = cc.editable;
    cell.isText = cc.isText;
    cell.isNumber = cc.isNumber;
    cell.isCurrency = cc.isCurrency;
    cell.isDate = cc.isDate;
    cell.isDateTime = cc.isDateTime;
    cell.isBoolean = cc.isBoolean;
    cell.isPicklist = cc.isPicklist;
    cell.isLookup = cc.isLookup;

    cell.isPercentage = cc.isPercentage;
    cell.isPhone = cc.isPhone;
    cell.isEmail = cc.isEmail;
    cell.isUrl = cc.isUrl;
    cell.isRichText = cc.isRichText;
    cell.isLongText = cc.isLongText;
    cell.options = cc.picklistOptions != null
      ? cc.picklistOptions
      : new List<Map<String, String>>();

    // Resolve cell value
    if (cc.additional) {
      cell.value = '';
    } else if (
      String.isNotBlank(cc.relationshipName) ||
      cc.soqlFieldPath.contains('.')
    ) {
      // Traverse to get display value (handles both 1-level and multi-level)
      Object val = traverseSObject(rec, cc.soqlFieldPath);
      cell.value = formatValue(val);

      // Capture raw Id for lookup pill seeding
      if (String.isNotBlank(cc.lookupField)) {
        Object rawId = traverseSObject(rec, cc.lookupField);
        cell.lookupId = rawId != null ? String.valueOf(rawId) : null;
      }
    } else {
      Object val = rec.get(cc.soqlFieldPath);
      cell.value = formatValue(val);
    }

    return cell;
  }

  /**
   * Executes a configurable Apex action.
   * Use reflection to instantiate the target handler class.
   */
  @AuraEnabled
  public static SDTConfiguratorDTO.ActionResponse executeTableAction(
    String actionId,
    List<Id> recordIds
  ) {
    System.debug(LoggingLevel.FINE, '[Service] executeTableAction G�� actionId');
    SDTConfiguratorDTO.ActionResponse response = new SDTConfiguratorDTO.ActionResponse();

    try {
      // 1. Fetch the action metadata
      Table_Action__c action = [
        SELECT Target__c, Action_Type__c
        FROM Table_Action__c
        WHERE Id = :actionId
        WITH USER_MODE
        LIMIT 1
      ];
      if (action.Action_Type__c != 'Apex') {
        throw new DynamicTableException(
          'Only Apex actions can be executed via this endpoint.'
        );
      }

      // 2. Instantiate the processor
      DynamicTableActionHandler processor = resolveActionProcessor(
        action.Target__c
      );

      // 3. Delegate execution
      return null;
    } catch (DynamicTableException dex) {
      throw dex;
    } catch (Exception ex) {
      

      response.success = false;
      response.message = 'Action failed due to an unexpected error. Please contact your administrator. Error Reference: ' + ex.getMessage();
      return response;
    }
  }

  private static DynamicTableActionHandler resolveActionProcessor(
    String className
  ) {
    try {
      // DynamicTableActionRegistry.assertAllowed(className);
      Type t = Type.forName(className);
      if (t == null)
        throw new DynamicTableException('Apex class not found: ' + className);

      Object instance = t.newInstance();
      if (!(instance instanceof DynamicTableActionHandler)) {
        throw new DynamicTableException(
          'Class "' +
            className +
            '" must implement DynamicTableActionHandler interface.'
        );
      }
      return (DynamicTableActionHandler) instance;
    } catch (Exception ex) {
      throw new DynamicTableException(
        'Failed to resolve action processor [' +
          className +
          ']: ' +
          ex.getMessage()
      );
    }
  }

  // G��G�� Private: Schema utilities G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��

  /**
   * Resolves the relationship name from a lookup field API name using Schema.Describe.
   * e.g. Contact__c G�� Contact__r,  AccountId G�� Account
   */
  private static String resolveRelationshipName(
    String objectApiName,
    String lookupFieldApiName
  ) {
    try {
      if (String.isBlank(objectApiName) || String.isBlank(lookupFieldApiName))
        return null;
      Map<String, Schema.SObjectField> fieldMap = getFieldMap(objectApiName);
      if (fieldMap == null)
        return null;

      Schema.SObjectField sField = fieldMap.get(
        lookupFieldApiName.toLowerCase()
      );
      if (sField == null)
        return null;

      String relName = sField.getDescribe().getRelationshipName();
      System.debug(LoggingLevel.FINE, '[Service] resolveRelationshipName');
      return relName;
    } catch (Exception ex) {
      System.debug(LoggingLevel.FINE, '[Service] resolveRelationshipName error');
      return null;
    }
  }

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

  public static String formatValue(Object val) {
    if (val == null)
      return '';

    if (val instanceof Date) {
      return String.valueOf((Date) val);
    }

    if (val instanceof Datetime) {
      return ((Datetime) val).format('yyyy-MM-dd\'T\'HH:mm:ss');
    }

    return String.valueOf(val);
  }

  /**
   * Traverses a resolved relationship on an SObject to read a parent field.
   * e.g. rec.getSObject('Contact__r').get('Name')
   */
  public static Object traverseSObject(SObject rec, String dotPath) {
    if (rec == null || String.isBlank(dotPath))
      return null;
    if (!dotPath.contains('.')) {
      try {
        return rec.get(dotPath);
      } catch (Exception ex) {
        return null;
      }
    }
    try {
      List<String> parts = dotPath.split('\\.');
      SObject currentObj = rec;
      for (Integer i = 0; i < parts.size() - 1; i++) {
        if (currentObj == null)
          return null;
        currentObj = currentObj.getSObject(parts[i]);
      }
      if (currentObj == null)
        return null;
      return currentObj.get(parts[parts.size() - 1]);
    } catch (Exception ex) {
      System.debug(LoggingLevel.FINE, '[Service] traverseSObject error G�� path');
      return null;
    }
  }

  /**
   * Derives the SObject type name from a Salesforce record Id using prefix lookup.
   * e.g. '006...' G�� 'Opportunity', '003...' G�� 'Contact'
   * Falls back to Schema.describeSObjects for custom object prefix resolution.
   */
  private static String getObjectTypeFromId(String recordId) {
    try {
      if (String.isBlank(recordId) || recordId.length() < 3)
        return null;
      Id sfId = (Id) recordId;
      return sfId.getSObjectType().getDescribe().getName();
    } catch (Exception ex) {
      System.debug(LoggingLevel.FINE, '[Service] getObjectTypeFromId error');
      return null;
    }
  }

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
  public static SDTConfiguratorDTO.SaveResult saveTableData(
    String tableName,
    String recordsJson
  ) {
    System.debug(LoggingLevel.FINE, '[Service] saveTableData G�� tableName');
    System.debug(LoggingLevel.INFO, '[Service] saveTableData request received.');

    SDTConfiguratorDTO.SaveResult result = new SDTConfiguratorDTO.SaveResult();
    result.failedRecordIds = new List<String>();

    try {

          // G��G�� 1. Validate inputs G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
          if (String.isBlank(tableName)) {
            throw new DynamicTableException('tableName is required for save.');
          }
          if (String.isBlank(recordsJson)) {
            throw new DynamicTableException('No records provided for save.');
          }

          // G��G�� 2. Parse payload G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
          List<SDTConfiguratorDTO.SaveRequest> saveRequests;
          try {
            saveRequests = (List<SDTConfiguratorDTO.SaveRequest>) JSON.deserialize(
              recordsJson,
              List<SDTConfiguratorDTO.SaveRequest>.class
            );
          } catch (Exception ex) {
            throw new DynamicTableException(
              'Invalid save payload: ' + ex.getMessage()
            );
          }

          if (saveRequests == null || saveRequests.isEmpty()) {
            result.success = true;
            result.message = 'Nothing to save.';
            return result;
          }

          // G��G�� 3. Load table config to resolve col key G�� real fieldName G��G��G��G��G��G��G��G��G��G��G��G��
          Table__c tableConfig = SDTConfiguratorSelector.resolveTableConfig(tableName);
          if (tableConfig == null) {
            throw new DynamicTableException('No Table__c found for: ' + tableName);
          }

          List<Table_Columns__c> rawColumns = SDTConfiguratorSelector.getColumnsByTableId(
            tableConfig.Id
          );

          String baseObject = tableConfig.Object_API_Name__c;

          // Build key G�� column map  (key = col0, col1 GǪ matches what LWC sends)
          Map<String, Table_Columns__c> keyToCol = new Map<String, Table_Columns__c>();
          Integer idx = 0;
          for (Table_Columns__c col : rawColumns) {
            keyToCol.put('col' + idx, col);
            idx++;
          }

          System.debug(LoggingLevel.FINE, '[Service] saveTableData keyToCol');

          // G��G�� 4. Get SObject type once G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
          Schema.SObjectType objType = getSObjectType(baseObject);
          if (objType == null) {
            throw new DynamicTableException('Unknown SObject: ' + baseObject);
          }
          Map<String, Schema.SObjectField> fieldMap = getFieldMap(baseObject);

          // G��G�� 5. Build SObjects for DML G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
          List<SObject> toUpdate = new List<SObject>();

          for (SDTConfiguratorDTO.SaveRequest req : saveRequests) {
            if (
              String.isBlank(req.recordId) ||
              req.fields == null ||
              req.fields.isEmpty()
            ) {
              System.debug('[Service] saveTableData: skipping empty request');
              continue;
            }

            SObject record = objType.newSObject(req.recordId);

            applyFieldValues(record, req.fields, keyToCol, fieldMap);

            toUpdate.add(record);
          }

          if (toUpdate.isEmpty()) {
            result.success = true;
            result.message = 'Nothing to update after field resolution.';
            return result;
          }

          // G��G�� 6. DML via Selector G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
          List<String> failedIds = SDTConfiguratorSelector.saveRecords(toUpdate);
          result.failedRecordIds = failedIds;

          if (failedIds.isEmpty()) {
            result.success = true;
            result.message = 'All records saved successfully.';
          } else {
            result.success = false;
            result.message = failedIds.size() + ' record(s) failed to save.';
          }

          System.debug(LoggingLevel.FINE, '[Service] saveTableData complete');
    } catch (DynamicTableException dex) {
      throw dex;
    } catch (Exception ex) {
      

      result.success = false;
      result.message = 'Save failed due to an unexpected error. Please contact your administrator. Error Reference: ' + ex.getMessage();
      return result;
    }
    return result;
  }

  private static void applyFieldValues(
    SObject record,
    Map<String, String> fieldsMap,
    Map<String, Table_Columns__c> keyToCol,
    Map<String, Schema.SObjectField> fieldMap
  ) {
    for (String colKey : fieldsMap.keySet()) {
      Table_Columns__c col = keyToCol.get(colKey);
      if (col == null) {
        System.debug(LoggingLevel.FINE, '[Service] saveTableData: unknown colKey');
        continue;
      }

      // Additional (UI-only) columns are never written
      if (col.Additional_Column__c)
        continue;

      // Lookup G�� write to the Id field (e.g. Contact__c), not the rel field
      String targetField = String.isNotBlank(col.Lookup_Field_API_Name__c)
        ? col.Lookup_Field_API_Name__c
        : col.Column_API_Name__c;

      // Resolve dot paths for lookups (e.g., "Account.Id" or "Shree_Tech__Contact__r.Id" -> "AccountId", "Shree_Tech__Contact__c")
      if (targetField != null && targetField.contains('.')) {
        String firstRelation = targetField.split('\\.')[0];
        if (firstRelation.endsWith('__r')) {
          String candidate =
            firstRelation.substring(0, firstRelation.length() - 3) + '__c';
          if (fieldMap.containsKey(candidate.toLowerCase())) {
            targetField = candidate;
          }
        } else {
          String candidate = firstRelation + 'Id';
          if (fieldMap.containsKey(candidate.toLowerCase())) {
            targetField = candidate;
          }
        }
      }

      String rawValue = fieldsMap.get(colKey);

      // Validate field exists on object
      if (!fieldMap.containsKey(targetField.toLowerCase())) {
        System.debug(LoggingLevel.FINE, '[Service] saveTableData: field');
        continue;
      }

      Schema.SObjectField sField = fieldMap.get(targetField.toLowerCase());
      Schema.DescribeFieldResult dfr = sField.getDescribe();
      if (!dfr.isUpdateable() && !dfr.isCreateable()) {
        System.debug(LoggingLevel.FINE, '[Service] saveTableData: user lacks permissions to update/create field');
        continue;
      }

      Schema.DisplayType fieldType = dfr.getType();

      try {
        record.put(targetField, castValue(rawValue, fieldType));
      } catch (Exception ex) {
        System.debug(LoggingLevel.FINE, '[Service] saveTableData: cast error on field');
      }
    }
  }

  // G��G�� Private: type-safe value casting G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��

  private static Object castValue(String raw, Schema.DisplayType fieldType) {
    if (raw == null || raw == '')
      return null;

    if (fieldType == Schema.DisplayType.BOOLEAN) {
      return Boolean.valueOf(raw);
    }
    if (fieldType == Schema.DisplayType.INTEGER) {
      return Integer.valueOf(raw);
    }
    if (
      fieldType == Schema.DisplayType.DOUBLE ||
      fieldType == Schema.DisplayType.CURRENCY ||
      fieldType == Schema.DisplayType.PERCENT
    ) {
      return Decimal.valueOf(raw);
    }
    if (fieldType == Schema.DisplayType.DATE) {
      return Date.valueOf(raw); // expects ISO: yyyy-MM-dd
    }
    if (fieldType == Schema.DisplayType.DATETIME) {
      return DateTime.valueOf(raw.replace('T', ' ')); // ISO G�� Apex format
    }
    if (fieldType == Schema.DisplayType.REFERENCE) {
      return (Id) raw; // lookup Id
    }

    return raw; // String, Picklist, etc.
  }

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
  public static SDTConfiguratorDTO.TableResult getFilteredTableData(
    String tableName,
    String parentId,
    String filtersJson
  ) {
    System.debug(LoggingLevel.FINE, '[Service] getFilteredTableData G�� tableName');

    // G��G�� 1. Validate & fetch Table__c config G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
    Table__c tableConfig = validateAndFetchConfig(tableName);
    String baseObject = tableConfig.Object_API_Name__c;

    // G��G�� 2. Fetch column configs G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
    List<Table_Columns__c> rawColumns = fetchColumnConfigs(tableConfig.Id);

    // G��G�� 3. Build ColumnConfig DTOs + SOQL field list G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
    //      (identical to getTableData G�� reuse same logic)
    List<SDTConfiguratorDTO.ColumnConfig> columns = new List<SDTConfiguratorDTO.ColumnConfig>();
    List<String> soqlFields = new List<String>{ 'Id' };
    String parentFilterField = null;
    String parentObjectType = String.isNotBlank(parentId)
      ? getObjectTypeFromId(parentId)
      : null;

    // Build fieldName G�� soqlFieldPath map for filter clause resolution
    // Key: column fieldName (e.g. StageName), Value: soqlFieldPath (e.g. StageName or Account.Name)
    Map<String, String> fieldNameToSoqlPath = new Map<String, String>();

    Integer colIndex = 0;
    for (Table_Columns__c col : rawColumns) {
      SDTConfiguratorDTO.ColumnConfig cc = buildColumnConfig(
        col,
        baseObject,
        colIndex
      );

      // Detect parent filter field (same logic as getTableData)
      if (
        String.isNotBlank(parentId) &&
        parentFilterField == null &&
        String.isNotBlank(col.Lookup_Field_API_Name__c) &&
        String.isNotBlank(parentObjectType) &&
        col.Object_Reference__c != null &&
        col.Object_Reference__c.equalsIgnoreCase(parentObjectType)
      ) {
        parentFilterField = col.Lookup_Field_API_Name__c;
      }

      // Build SOQL field list (same logic as getTableData)
      if (!col.Additional_Column__c) {
        if (String.isNotBlank(cc.relationshipName)) {
          // If Column_API_Name__c already has a dot (e.g. Contact.Name), use it directly
          String dotField;
          if (
            col.Column_API_Name__c != null &&
            col.Column_API_Name__c.contains('.')
          ) {
            dotField = col.Column_API_Name__c;
          } else {
            dotField = cc.relationshipName + '.' + col.Column_API_Name__c;
          }
          soqlFields.add(dotField);
          cc.soqlFieldPath = dotField;
          if (!soqlFields.contains(col.Lookup_Field_API_Name__c)) {
            soqlFields.add(col.Lookup_Field_API_Name__c);
          }
        } else {
          if (!soqlFields.contains(col.Column_API_Name__c)) {
            soqlFields.add(col.Column_API_Name__c);
          }
          cc.soqlFieldPath = col.Column_API_Name__c;
        }
      }

      if (cc.dataType == 'Lookup' && String.isNotBlank(cc.lookupField)) {
        fieldNameToSoqlPath.put(cc.fieldName, cc.lookupField);
        fieldNameToSoqlPath.put(cc.key, cc.lookupField);
      } else if (String.isNotBlank(cc.soqlFieldPath)) {
        fieldNameToSoqlPath.put(cc.fieldName, cc.soqlFieldPath);
        fieldNameToSoqlPath.put(cc.key, cc.soqlFieldPath);
      }

      columns.add(cc);
      colIndex++;
    }

    // Auto-detect parent lookup fallback (same as getTableData)
    if (String.isNotBlank(parentId) && String.isBlank(parentFilterField)) {
      parentFilterField = autoDetectParentLookup(baseObject, parentObjectType);
    }

    // G��G�� 4. Parse filter payload G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
    SDTConfiguratorDTO.FilterPayload filterPayload = null;
    if (String.isNotBlank(filtersJson)) {
      try {
        filterPayload = (SDTConfiguratorDTO.FilterPayload) JSON.deserialize(
          filtersJson,
          SDTConfiguratorDTO.FilterPayload.class
        );
      } catch (Exception ex) {
        System.debug(LoggingLevel.FINE, '[Service] getFilteredTableData: invalid filtersJson');
        // Degrade gracefully G�� run without filters rather than throwing
        filterPayload = null;
      }
    }

    if (filterPayload != null && filterPayload.filters != null) {
      Filter_Framework_Setting__mdt setting = Filter_Framework_Setting__mdt.getInstance(
        'Default'
      );
      Integer maxFilters = (setting != null &&
        setting.Max_Filters__c != null)
        ? setting.Max_Filters__c.intValue()
        : 10;
      if (filterPayload.filters.size() > maxFilters) {
        throw new DynamicTableException(
          'The number of filters (' +
            filterPayload.filters.size() +
            ') exceeds the maximum limit allowed (' +
            maxFilters +
            ').'
        );
      }
    }

    // G��G�� 5. Build SOQL with parent WHERE + filter WHERE G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
    String soql = buildFilteredDataQuery(
      baseObject,
      soqlFields,
      parentId,
      parentFilterField,
      filterPayload,
      fieldNameToSoqlPath
    );

    // G��G�� 6. Execute via Selector G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
    List<SObject> records;
    try {
      records = SDTConfiguratorSelector.queryRecords(soql);
    } catch (Exception ex) {
      if (Test.isRunningTest()) {
        throw ex;
      }
      
      throw new AuraHandledException(
        'An unexpected error occurred. Please contact your administrator. Error Reference: ' + ex.getMessage()
      );
    }

    // G��G�� 7. Flatten G�� DTO rows (reuse existing private method) G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
    List<SDTConfiguratorDTO.RowData> rows = flattenRecords(records, columns);

    // G��G�� 8. Assemble result G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
    SDTConfiguratorDTO.TableResult result = new SDTConfiguratorDTO.TableResult();
    result.columns = columns;
    result.rows = rows;
    result.objectApiName = baseObject;
    result.parentId = parentId;

    System.debug(LoggingLevel.FINE, '[Service] getFilteredTableData complete');
    return result;
  }

  // G��G�� Private: builds SOQL with both parent filter AND user filter criteria G��G��G��G��

  public static String buildFilteredDataQuery(
    String baseObject,
    List<String> soqlFields,
    String parentId,
    String parentFilterField,
    SDTConfiguratorDTO.FilterPayload filterPayload,
    Map<String, String> fieldNameToSoqlPath
  ) {
    List<String> whereClauses = new List<String>();

    // G��G�� Parent record filter (existing behaviour, unchanged) G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
    if (String.isNotBlank(parentId) && String.isNotBlank(parentFilterField)) {
      String safeId = String.escapeSingleQuotes(parentId);
      whereClauses.add(parentFilterField + ' = \'' + safeId + '\'');
      System.debug(LoggingLevel.FINE, '[Service] buildFilteredDataQuery: parent clause');
    }

    // G��G�� User filter criteria G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
    if (
      filterPayload != null &&
      filterPayload.filters != null &&
      !filterPayload.filters.isEmpty()
    ) {
      if ('CUSTOM'.equalsIgnoreCase(filterPayload.logic) && String.isNotBlank(filterPayload.customLogic)) {
        Map<Integer, String> indexToClause = new Map<Integer, String>();
        Integer defaultIdx = 1;
        for (SDTConfiguratorDTO.FilterCriteria f : filterPayload.filters) {
          if (String.isBlank(f.fieldName) || String.isBlank(f.operator))
            continue;
          String soqlField = String.isNotBlank(f.soqlFieldPath) ? f.soqlFieldPath : fieldNameToSoqlPath.get(f.fieldName);
          if (String.isBlank(soqlField))
            continue;
          String clause = buildSingleFilterClause(soqlField, f, fieldNameToSoqlPath);
          if (String.isNotBlank(clause)) {
            Integer idx = f.filterIndex != null ? f.filterIndex : defaultIdx;
            indexToClause.put(idx, clause);
          }
          defaultIdx++;
        }
        String customWhere = resolveCustomLogicExpression(indexToClause, filterPayload.customLogic);
        if (String.isNotBlank(customWhere)) {
          whereClauses.add('(' + customWhere + ')');
        }
      } else {
        String filterLogic = (filterPayload.logic == 'OR') ? ' OR ' : ' AND ';
        List<String> filterClauses = new List<String>();
        for (SDTConfiguratorDTO.FilterCriteria f : filterPayload.filters) {
          if (String.isBlank(f.fieldName) || String.isBlank(f.operator))
            continue;
          String soqlField = String.isNotBlank(f.soqlFieldPath) ? f.soqlFieldPath : fieldNameToSoqlPath.get(f.fieldName);
          if (String.isBlank(soqlField))
            continue;
          String clause = buildSingleFilterClause(soqlField, f, fieldNameToSoqlPath);
          if (String.isNotBlank(clause)) {
            filterClauses.add(clause);
          }
        }
        if (!filterClauses.isEmpty()) {
          whereClauses.add('(' + String.join(filterClauses, filterLogic) + ')');
        }
      }
    }

    // G��G�� Assemble final SOQL G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
    String soql =
      'SELECT ' +
      String.join(soqlFields, ', ') +
      ' FROM ' +
      baseObject;

    if (!whereClauses.isEmpty()) {
      // Parent filter is always AND-joined with the filter group
      soql += ' WHERE ' + String.join(whereClauses, ' AND ');
    }

    soql += ' LIMIT 2000';

    System.debug(LoggingLevel.FINE, '[Service] Query built.');
    return soql;
  }


  private static void applyExactFilter(
    SDTConfiguratorDTO.FilterCriteria f,
    String val,
    List<String> values
  ) {
    if (val.startsWith('{') && val.endsWith('}')) {
      try {
        Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(val);
        if (m.containsKey('operator') && m.containsKey('value')) {
          f.operator = String.valueOf(m.get('operator'));
          values.add(m.get('value') != null ? String.valueOf(m.get('value')) : '');
        } else {
          f.operator = 'EQUALS';
          values.add(val);
        }
      } catch (Exception e) {
        f.operator = 'EQUALS';
        values.add(val);
      }
    } else {
      f.operator = 'EQUALS';
      values.add(val);
    }
  }

  private static void applyRangeFilter(
    SDTConfiguratorDTO.FilterCriteria f,
    String val,
    List<String> values,
    String type
  ) {
    f.operator = 'BETWEEN';
    try {
      Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(val);
      if (type == 'range') {
        values.add(m.containsKey('min') && m.get('min') != null ? String.valueOf(m.get('min')) : '');
        values.add(m.containsKey('max') && m.get('max') != null ? String.valueOf(m.get('max')) : '');
      } else {
        values.add(m.containsKey('from') && m.get('from') != null ? String.valueOf(m.get('from')) : '');
        values.add(m.containsKey('to') && m.get('to') != null ? String.valueOf(m.get('to')) : '');
      }
    } catch (Exception e) {
      System.debug(LoggingLevel.FINE, 'Error parsing JSON default range filter');
    }
  }

  private static void applyMultiSelectFilter(
    SDTConfiguratorDTO.FilterCriteria f,
    String val,
    List<String> values
  ) {
    try {
      Object parsed = JSON.deserializeUntyped(val);
      if (parsed instanceof Map<String, Object>) {
        Map<String, Object> m = (Map<String, Object>) parsed;
        f.operator = m.containsKey('operator') ? String.valueOf(m.get('operator')) : 'IN';
        List<Object> lst = (List<Object>) m.get('values');
        for (Object obj : lst) {
          if (obj != null) values.add(String.valueOf(obj));
        }
      } else if (parsed instanceof List<Object>) {
        f.operator = 'IN';
        List<Object> lst = (List<Object>) parsed;
        for (Object obj : lst) {
          if (obj != null) values.add(String.valueOf(obj));
        }
      } else {
        f.operator = 'IN';
        values.add(val);
      }
    } catch (Exception e) {
      f.operator = 'IN';
      values.add(val);
    }
  }

  public static SDTConfiguratorDTO.FilterPayload buildDefaultFilterPayload(
    List<Table_Columns__c> rawColumns,
    List<SDTConfiguratorDTO.ColumnConfig> columns
  ) {
    SDTConfiguratorDTO.FilterPayload payload = new SDTConfiguratorDTO.FilterPayload();
    payload.logic = 'AND';
    payload.filters = new List<SDTConfiguratorDTO.FilterCriteria>();

    Map<String, SDTConfiguratorDTO.ColumnConfig> fieldToConfig = new Map<String, SDTConfiguratorDTO.ColumnConfig>();
    for (SDTConfiguratorDTO.ColumnConfig cc : columns) {
      if (String.isNotBlank(cc.fieldName)) {
        fieldToConfig.put(cc.fieldName.toLowerCase(), cc);
      }
    }

    Integer index = 1;
    for (Table_Columns__c col : rawColumns) {
      if (
        col.Is_Filterable__c == true &&
        String.isNotBlank(col.Filter_Type__c) &&
        String.isNotBlank(col.Default_Filter_Value__c)
      ) {
        SDTConfiguratorDTO.ColumnConfig cc = fieldToConfig.get(
          col.Column_API_Name__c.toLowerCase()
        );
        if (cc == null)
          continue;

        SDTConfiguratorDTO.FilterCriteria f = new SDTConfiguratorDTO.FilterCriteria();
        f.filterIndex = index++;
        f.fieldName = cc.fieldName;
        f.soqlFieldPath = cc.soqlFieldPath;
        if (cc.dataType == 'Lookup' && String.isNotBlank(cc.lookupField)) {
          f.soqlFieldPath = cc.lookupField;
        }
        f.dataType = cc.dataType;

        String type = col.Filter_Type__c.toLowerCase();
        String val = col.Default_Filter_Value__c;
        String operator = '';
        List<String> values = new List<String>();

        if (type == 'text') {
          f.operator = 'CONTAINS';
          values.add(val);
        } else if (type == 'exact') {
          applyExactFilter(f, val, values);
        } else if (type == 'starts_with') {
          f.operator = 'STARTS_WITH';
          values.add(val);
        } else if (type == 'range' || type == 'date_range') {
          applyRangeFilter(f, val, values, type);
        } else if (type == 'multi_select') {
          applyMultiSelectFilter(f, val, values);
        } else if (type == 'boolean') {
          f.operator = val.equalsIgnoreCase('true') ? 'IS_TRUE' : 'IS_FALSE';
        }

        if (String.isNotBlank(f.operator)) {
          f.values = values;
          payload.filters.add(f);
        }
      }
    }

    return payload.filters.isEmpty() ? null : payload;
  }

  // G��G�� Private: builds a single SOQL clause for one FilterCriteria G��G��G��G��G��G��G��G��G��G��G��G��G��G��

  private static String formatSoqlValue(Object rawVal, String dataType) {
    if (rawVal == null)
      return 'null';
    String strVal = String.valueOf(rawVal);

    if (isNumericType(dataType)) {
      try {
        Decimal.valueOf(strVal);
        return strVal;
      } catch (Exception e) {
        return 'null';
      }
    }
    if (dataType == 'Boolean') {
      return strVal.equalsIgnoreCase('true') ? 'true' : 'false';
    }
    if (isDateType(dataType)) {
      return toSoqlDateLiteral(strVal, dataType);
    }
    return '\'' + String.escapeSingleQuotes(strVal) + '\'';
  }

  private static String buildSingleFilterClause(
    String soqlField,
    SDTConfiguratorDTO.FilterCriteria f,
    Map<String, String> fieldNameToSoqlPath
  ) {
    if (f == null || String.isBlank(f.operator))
      return '';

    // Validate field path is allowed to prevent SOQL injection
    Map<String, String> allowedFieldPaths = new Map<String, String>();
    if (fieldNameToSoqlPath != null) {
      for (String key : fieldNameToSoqlPath.keySet()) {
        allowedFieldPaths.put(key.toLowerCase(), fieldNameToSoqlPath.get(key));
        String val = fieldNameToSoqlPath.get(key);
        if (val != null) {
          allowedFieldPaths.put(val.toLowerCase(), val);
        }
      }
    }
    if (String.isNotBlank(soqlField)) {
      if (!allowedFieldPaths.containsKey(soqlField.toLowerCase())) {
        throw new DynamicTableException(
          'Unauthorized field in filter: ' + soqlField
        );
      }
    }
    String op = f.operator.toUpperCase().trim();

    // Operators that need no value input
    if (op == 'IS_BLANK') {
      return soqlField + ' = null';
    }
    if (op == 'IS_NOT_BLANK') {
      return soqlField + ' != null';
    }
    if (op == 'IS_TRUE' || op == 'TRUE') {
      return soqlField + ' = true';
    }
    if (op == 'IS_FALSE' || op == 'FALSE') {
      return soqlField + ' = false';
    }

    // If no values provided, ignore the filter clause
    if (f.values == null || f.values.isEmpty())
      return '';

    // IN and NOT_IN operators
    if (op == 'IN' || op == 'INCLUDES' || op == 'NOT_IN' || op == 'EXCLUDES') {
      List<String> formattedList = new List<String>();
      for (Object v : f.values) {
        if (v != null && String.isNotBlank(String.valueOf(v))) {
          formattedList.add(formatSoqlValue(v, f.dataType));
        }
      }
      if (formattedList.isEmpty())
        return '';
      String operatorKeyword = (op == 'IN' ||
        op == 'INCLUDES')
        ? 'IN'
        : 'NOT IN';
      return soqlField +
        ' ' +
        operatorKeyword +
        ' (' +
        String.join(formattedList, ', ') +
        ')';
    }

    // BETWEEN and RANGE operators
    if (op == 'BETWEEN' || op == 'RANGE') {
      if (f.values.size() < 2 || f.values[0] == null || f.values[1] == null)
        return '';
      String valMinStr = formatSoqlValue(f.values[0], f.dataType);
      String valMaxStr = formatSoqlValue(f.values[1], f.dataType);
      return '(' +
        soqlField +
        ' >= ' +
        valMinStr +
        ' AND ' +
        soqlField +
        ' <= ' +
        valMaxStr +
        ')';
    }

    // Single-value operators
    Object firstValue = f.values[0];
    if (firstValue == null || String.isBlank(String.valueOf(firstValue)))
      return '';
    String valStr = String.valueOf(firstValue);

    if (op == 'CONTAINS') {
      return soqlField +
        ' LIKE \'%' +
        String.escapeSingleQuotes(valStr) +
        '%\'';
    }
    if (op == 'NOT_CONTAINS') {
      return '(NOT ' +
        soqlField +
        ' LIKE \'%' +
        String.escapeSingleQuotes(valStr) +
        '%\')';
    }
    if (op == 'STARTS_WITH') {
      return soqlField + ' LIKE \'' + String.escapeSingleQuotes(valStr) + '%\'';
    }
    if (op == 'ENDS_WITH') {
      return soqlField + ' LIKE \'%' + String.escapeSingleQuotes(valStr) + '\'';
    }
    if (op == 'EQUALS') {
      return soqlField + ' = ' + formatSoqlValue(firstValue, f.dataType);
    }
    if (op == 'NOT_EQUALS') {
      return soqlField + ' != ' + formatSoqlValue(firstValue, f.dataType);
    }
    if (op == 'GREATER_THAN') {
      return soqlField + ' > ' + formatSoqlValue(firstValue, f.dataType);
    }
    if (op == 'LESS_THAN') {
      return soqlField + ' < ' + formatSoqlValue(firstValue, f.dataType);
    }
    if (op == 'GREATER_OR_EQUAL' || op == 'GTE') {
      return soqlField + ' >= ' + formatSoqlValue(firstValue, f.dataType);
    }
    if (op == 'LESS_OR_EQUAL' || op == 'LTE') {
      return soqlField + ' <= ' + formatSoqlValue(firstValue, f.dataType);
    }
    if (op == 'BEFORE') {
      return soqlField + ' < ' + formatSoqlValue(firstValue, f.dataType);
    }
    if (op == 'AFTER') {
      return soqlField + ' > ' + formatSoqlValue(firstValue, f.dataType);
    }

    System.debug(LoggingLevel.FINE, '[Service] buildSingleFilterClause: unrecognised operator');
    return '';
  }


  private static String buildInOperatorClause(String soqlField, SDTConfiguratorDTO.FilterCriteria f, String op) {
    List<String> formattedList = new List<String>();
    for (Object v : f.values) {
      if (v != null && String.isNotBlank(String.valueOf(v))) {
        formattedList.add(formatSoqlValue(v, f.dataType));
      }
    }
    if (formattedList.isEmpty()) return '';
    String operatorKeyword = (op == 'IN' || op == 'INCLUDES') ? 'IN' : 'NOT IN';
    return soqlField + ' ' + operatorKeyword + ' (' + String.join(formattedList, ', ') + ')';
  }

  private static String buildRangeOperatorClause(String soqlField, SDTConfiguratorDTO.FilterCriteria f) {
    if (f.values.size() < 2 || f.values[0] == null || f.values[1] == null) return '';
    String valMinStr = formatSoqlValue(f.values[0], f.dataType);
    String valMaxStr = formatSoqlValue(f.values[1], f.dataType);
    return '(' + soqlField + ' >= ' + valMinStr + ' AND ' + soqlField + ' <= ' + valMaxStr + ')';
  }

  private static String buildStringFilterClause(String soqlField, String valStr, String op) {
    if (op == 'CONTAINS') {
      return soqlField + ' LIKE \'%\' + String.escapeSingleQuotes(valStr) + \'%\'';
    }
    if (op == 'NOT_CONTAINS') {
      return '(NOT ' + soqlField + ' LIKE \'%\' + String.escapeSingleQuotes(valStr) + \'%\')';
    }
    if (op == 'STARTS_WITH') {
      return soqlField + ' LIKE \'' + String.escapeSingleQuotes(valStr) + '%\'';
    }
    if (op == 'ENDS_WITH') {
      return soqlField + ' LIKE \'%\' + String.escapeSingleQuotes(valStr) + \'\'';
    }
    return '';
  }

  private static String buildComparisonFilterClause(String soqlField, Object firstValue, String dataType, String op) {
    if (op == 'EQUALS') {
      return soqlField + ' = ' + formatSoqlValue(firstValue, dataType);
    }
    if (op == 'NOT_EQUALS') {
      return soqlField + ' != ' + formatSoqlValue(firstValue, dataType);
    }
    if (op == 'GREATER_THAN' || op == 'AFTER') {
      return soqlField + ' > ' + formatSoqlValue(firstValue, dataType);
    }
    if (op == 'LESS_THAN' || op == 'BEFORE') {
      return soqlField + ' < ' + formatSoqlValue(firstValue, dataType);
    }
    if (op == 'GREATER_OR_EQUAL' || op == 'GTE') {
      return soqlField + ' >= ' + formatSoqlValue(firstValue, dataType);
    }
    if (op == 'LESS_OR_EQUAL' || op == 'LTE') {
      return soqlField + ' <= ' + formatSoqlValue(firstValue, dataType);
    }
    return '';
  }

  // G��G�� Private: filter clause helpers G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��

  private static Boolean isNumericType(String dataType) {
    return dataType == 'Number' ||
      dataType == 'Currency' ||
      dataType == 'Percentage';
  }

  private static Boolean isDateType(String dataType) {
    return dataType == 'Date' || dataType == 'DateTime';
  }

  /**
   * Converts an ISO date string from LWC into a SOQL-safe date/datetime literal.
   * Date:     2024-03-15              G�� 2024-03-15
   * DateTime: 2024-03-15T00:00:00Z   G�� 2024-03-15T00:00:00Z
   * No quotes G�� SOQL date literals are unquoted.
   */
  private static String toSoqlDateLiteral(String isoValue, String dataType) {
    if (String.isBlank(isoValue))
      return 'null';

    // Check for standard Salesforce Date Literals (bypass formatting)
    Set<String> literals = new Set<String>{
      'TODAY',
      'YESTERDAY',
      'TOMORROW',
      'THIS_WEEK',
      'LAST_WEEK',
      'NEXT_WEEK',
      'THIS_MONTH',
      'LAST_MONTH',
      'NEXT_MONTH',
      'THIS_QUARTER',
      'LAST_QUARTER',
      'NEXT_QUARTER',
      'THIS_YEAR',
      'LAST_YEAR',
      'NEXT_YEAR'
    };
    if (literals.contains(isoValue.toUpperCase())) {
      return isoValue.toUpperCase();
    }

    // DateTime: ensure T separator and Z suffix
    if (dataType == 'DateTime') {
      String dt = isoValue.replace(' ', 'T');
      if (!dt.endsWith('Z') && !dt.contains('+'))
        dt += 'Z';
      return dt;
    }
    // Date: strip any time component
    return isoValue.split('T')[0];
  }

  /**
   * Converts a comma-separated picklist value string into a
   * SOQL-safe IN list of quoted strings.
   * e.g. "Closed Won,Closed Lost" G�� ['Closed Won', 'Closed Lost']
   */
  private static List<String> buildInList(String commaSeparated) {
    List<String> result = new List<String>();
    if (String.isBlank(commaSeparated))
      return result;
    for (String v : commaSeparated.split(',')) {
      String trimmed = v.trim();
      if (String.isNotBlank(trimmed)) {
        result.add('\'' + String.escapeSingleQuotes(trimmed) + '\'');
      }
    }
    return result;
  }

  // G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
  // Export QueryLocator & Record Counting
  // G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��

  /**
   * Returns the exact database record count for the given table and filters.
   * Avoids retrieving full records to prevent heap limit errors.
   */
  public static Integer getRecordCount(
    String tableName,
    String parentId,
    String filtersJson
  ) {
    return getRecordCount(tableName, parentId, filtersJson, null);
  }

  public static Integer getRecordCount(
    String tableName,
    String parentId,
    String filtersJson,
    String searchTerm
  ) {
    return getRecordCountInternal(tableName, parentId, filtersJson, searchTerm, true);
  }

  public static Integer getExportRecordCount(
    String tableName,
    String parentId,
    String filtersJson,
    String searchTerm
  ) {
    return getRecordCountInternal(tableName, parentId, filtersJson, searchTerm, false);
  }

  private static Integer getRecordCountInternal(
    String tableName,
    String parentId,
    String filtersJson,
    String searchTerm,
    Boolean applySafetyLimit
  ) {
    System.debug(LoggingLevel.FINE, '[Service] getRecordCount G�� tableName');

    if (String.isBlank(tableName)) {
      throw new DynamicTableException('tableName is required for counting.');
    }

    Table__c tableConfig = SDTConfiguratorSelector.getTableByName(tableName);
    if (tableConfig == null) {
      throw new DynamicTableException(
        'No Table__c found for name: ' + tableName
      );
    }

    String baseObject = tableConfig.Object_API_Name__c;
    List<Table_Columns__c> rawColumns = SDTConfiguratorSelector.getColumnsByTableId(
      tableConfig.Id
    );

    if (rawColumns.isEmpty()) {
      throw new DynamicTableException(
        'No columns configured for table: ' + tableName
      );
    }

    // Build column paths just like export
    String parentFilterField = null;
    String parentObjectType = String.isNotBlank(parentId)
      ? getObjectTypeFromId(parentId)
      : null;
    Map<String, String> fieldNameToSoqlPath = new Map<String, String>();
    List<SDTConfiguratorDTO.ColumnConfig> columnConfigs = new List<SDTConfiguratorDTO.ColumnConfig>();

    Integer colIndex = 0;
    for (Table_Columns__c col : rawColumns) {
      SDTConfiguratorDTO.ColumnConfig cc = buildColumnConfig(
        col,
        baseObject,
        colIndex
      );
      columnConfigs.add(cc);

      if (
        String.isNotBlank(parentId) &&
        parentFilterField == null &&
        String.isNotBlank(col.Lookup_Field_API_Name__c) &&
        String.isNotBlank(parentObjectType) &&
        col.Object_Reference__c != null &&
        col.Object_Reference__c.equalsIgnoreCase(parentObjectType)
      ) {
        parentFilterField = col.Lookup_Field_API_Name__c;
      }

      if (!col.Additional_Column__c) {
        if (String.isNotBlank(cc.relationshipName)) {
          cc.soqlFieldPath = cc.relationshipName + '.' + col.Column_API_Name__c;
        } else {
          cc.soqlFieldPath = col.Column_API_Name__c;
        }
      }

      if (cc.dataType == 'Lookup' && String.isNotBlank(cc.lookupField)) {
        fieldNameToSoqlPath.put(cc.fieldName, cc.lookupField);
        fieldNameToSoqlPath.put(cc.key, cc.lookupField);
      } else if (String.isNotBlank(cc.soqlFieldPath)) {
        fieldNameToSoqlPath.put(cc.fieldName, cc.soqlFieldPath);
        fieldNameToSoqlPath.put(cc.key, cc.soqlFieldPath);
      }
      colIndex++;
    }

    if (String.isNotBlank(parentId) && String.isBlank(parentFilterField)) {
      parentFilterField = autoDetectParentLookup(baseObject, parentObjectType);
    }

    SDTConfiguratorDTO.FilterPayload filterPayload = null;
    if (String.isNotBlank(filtersJson)) {
      try {
        filterPayload = (SDTConfiguratorDTO.FilterPayload) JSON.deserialize(
          filtersJson,
          SDTConfiguratorDTO.FilterPayload.class
        );
      } catch (Exception ex) {
        System.debug(LoggingLevel.FINE, '[Service] getRecordCount: invalid filtersJson');
      }
    }

    if (filterPayload != null && filterPayload.filters != null) {
      Filter_Framework_Setting__mdt setting = Filter_Framework_Setting__mdt.getInstance(
        'Default'
      );
      Integer maxFilters = (setting != null &&
        setting.Max_Filters__c != null)
        ? setting.Max_Filters__c.intValue()
        : 10;
      if (filterPayload.filters.size() > maxFilters) {
        throw new DynamicTableException(
          'The number of filters (' +
            filterPayload.filters.size() +
            ') exceeds the maximum limit allowed (' +
            maxFilters +
            ').'
        );
      }
    }

    List<String> whereClauses = new List<String>();

    if (String.isNotBlank(parentId) && String.isNotBlank(parentFilterField)) {
      String safeId = String.escapeSingleQuotes(parentId);
      whereClauses.add(parentFilterField + ' = \'' + safeId + '\'');
    }

    if (
      filterPayload != null &&
      filterPayload.filters != null &&
      !filterPayload.filters.isEmpty()
    ) {
      String filterLogic = (filterPayload.logic == 'OR') ? ' OR ' : ' AND ';
      List<String> filterClauses = new List<String>();

      for (SDTConfiguratorDTO.FilterCriteria f : filterPayload.filters) {
        if (String.isBlank(f.fieldName) || String.isBlank(f.operator))
          continue;
        String soqlField = String.isNotBlank(f.soqlFieldPath)
          ? f.soqlFieldPath
          : fieldNameToSoqlPath.get(f.fieldName);
        if (String.isBlank(soqlField))
          continue;

        String clause = buildSingleFilterClause(
          soqlField,
          f,
          fieldNameToSoqlPath
        );
        if (String.isNotBlank(clause))
          filterClauses.add(clause);
      }

      if (!filterClauses.isEmpty()) {
        whereClauses.add('(' + String.join(filterClauses, filterLogic) + ')');
      }
    }

    List<String> searchClauses = new List<String>();
    if (String.isNotBlank(searchTerm)) {
      String escapedSearchTerm =
        '%' +
        String.escapeSingleQuotes(searchTerm.trim()) +
        '%';
      for (SDTConfiguratorDTO.ColumnConfig cc : columnConfigs) {
        if (
          cc.isSearchable != false &&
          !cc.additional &&
          String.isNotBlank(cc.soqlFieldPath)
        ) {
          searchClauses.add(
            cc.soqlFieldPath + ' LIKE \'' + escapedSearchTerm + '\''
          );
        }
      }
    }

    if (!searchClauses.isEmpty()) {
      whereClauses.add('(' + String.join(searchClauses, ' OR ') + ')');
    }

    String soql = 'SELECT COUNT() FROM ' + baseObject;
    if (!whereClauses.isEmpty()) {
      soql += ' WHERE ' + String.join(whereClauses, ' AND ');
    }

    // Cap at 45,005 G�� strictly above matrixAggregateLimit (45,000) but safely below the
    // 50,000 governor limit (accounting for ~50 metadata query rows in the same transaction).
    // Using 45,000 here would cause the Orchestrator to see rowCount == limit and treat it as
    // "within bounds", proceeding to a synchronous GROUP BY scan that crashes on 50,001+ records.
    soql += ' LIMIT 49500';

    try {
      return SDTConfiguratorSelector.getRecordCount(soql);
    } catch (Exception ex) {
      
      throw new AuraHandledException(
        'An unexpected error occurred. Please contact your administrator. Error Reference: ' + ex.getMessage()
      );
    }
  }

  public static Map<String, Decimal> getGrandTotals(
    String tableName,
    String parentId,
    String filtersJson,
    String searchTerm
  ) {
    if (String.isBlank(tableName)) {
      throw new DynamicTableException('tableName is required for totals.');
    }

    Table__c tableConfig = SDTConfiguratorSelector.getTableByName(tableName);
    if (tableConfig == null) {
      throw new DynamicTableException(
        'No Table__c found for name: ' + tableName
      );
    }

    String baseObject = tableConfig.Object_API_Name__c;
    List<Table_Columns__c> rawColumns = SDTConfiguratorSelector.getColumnsByTableId(
      tableConfig.Id
    );
    if (rawColumns.isEmpty()) {
      return new Map<String, Decimal>();
    }

    String parentFilterField = null;
    String parentObjectType = String.isNotBlank(parentId)
      ? getObjectTypeFromId(parentId)
      : null;
    Map<String, String> fieldNameToSoqlPath = new Map<String, String>();
    List<SDTConfiguratorDTO.ColumnConfig> columnConfigs = new List<SDTConfiguratorDTO.ColumnConfig>();
    Map<String, String> aliasToKey = new Map<String, String>();
    List<String> selectParts = new List<String>();

    Integer colIndex = 0;
    Integer totalIndex = 0;
    for (Table_Columns__c col : rawColumns) {
      SDTConfiguratorDTO.ColumnConfig cc = buildColumnConfig(
        col,
        baseObject,
        colIndex
      );

      if (
        String.isNotBlank(parentId) &&
        parentFilterField == null &&
        String.isNotBlank(col.Lookup_Field_API_Name__c) &&
        String.isNotBlank(parentObjectType) &&
        col.Object_Reference__c != null &&
        col.Object_Reference__c.equalsIgnoreCase(parentObjectType)
      ) {
        parentFilterField = col.Lookup_Field_API_Name__c;
      }

      if (!col.Additional_Column__c) {
        if (String.isNotBlank(cc.relationshipName)) {
          cc.soqlFieldPath = cc.relationshipName + '.' + col.Column_API_Name__c;
        } else {
          cc.soqlFieldPath = col.Column_API_Name__c;
        }
      }

      if (cc.dataType == 'Lookup' && String.isNotBlank(cc.lookupField)) {
        fieldNameToSoqlPath.put(cc.fieldName, cc.lookupField);
        fieldNameToSoqlPath.put(cc.key, cc.lookupField);
      } else if (String.isNotBlank(cc.soqlFieldPath)) {
        fieldNameToSoqlPath.put(cc.fieldName, cc.soqlFieldPath);
        fieldNameToSoqlPath.put(cc.key, cc.soqlFieldPath);
      }

      columnConfigs.add(cc);

      String normalizedType = String.valueOf(cc.dataType).toUpperCase();
      Boolean isSummable =
        cc.isVisible != false &&
        !cc.additional &&
        String.isNotBlank(cc.soqlFieldPath) &&
        !cc.soqlFieldPath.contains('.') &&
        (cc.isNumber ||
        cc.isCurrency ||
        normalizedType == 'NUMBER' ||
        normalizedType == 'CURRENCY' ||
        normalizedType == 'PERCENT' ||
        normalizedType == 'PERCENTAGE' ||
        normalizedType == 'DOUBLE' ||
        normalizedType == 'INTEGER' ||
        normalizedType == 'LONG' ||
        normalizedType == 'DECIMAL');

      if (isSummable) {
        String alias = 'total' + totalIndex++;
        selectParts.add('SUM(' + cc.soqlFieldPath + ') ' + alias);
        aliasToKey.put(alias, cc.key);
      }

      colIndex++;
    }

    if (selectParts.isEmpty()) {
      return new Map<String, Decimal>();
    }

    if (String.isNotBlank(parentId) && String.isBlank(parentFilterField)) {
      parentFilterField = autoDetectParentLookup(baseObject, parentObjectType);
    }

    SDTConfiguratorDTO.FilterPayload filterPayload = null;
    if (String.isNotBlank(filtersJson)) {
      try {
        filterPayload = (SDTConfiguratorDTO.FilterPayload) JSON.deserialize(
          filtersJson,
          SDTConfiguratorDTO.FilterPayload.class
        );
      } catch (Exception ex) {
        System.debug(LoggingLevel.FINE, '[Service] getGrandTotals: invalid filtersJson');
      }
    }

    List<String> whereClauses = new List<String>();
    if (String.isNotBlank(parentId) && String.isNotBlank(parentFilterField)) {
      whereClauses.add(
        parentFilterField +
        ' = \'' +
        String.escapeSingleQuotes(parentId) +
        '\''
      );
    }

    if (
      filterPayload != null &&
      filterPayload.filters != null &&
      !filterPayload.filters.isEmpty()
    ) {
      String filterLogic = (filterPayload.logic == 'OR') ? ' OR ' : ' AND ';
      List<String> filterClauses = new List<String>();
      for (SDTConfiguratorDTO.FilterCriteria f : filterPayload.filters) {
        if (String.isBlank(f.fieldName) || String.isBlank(f.operator))
          continue;
        String soqlField = String.isNotBlank(f.soqlFieldPath)
          ? f.soqlFieldPath
          : fieldNameToSoqlPath.get(f.fieldName);
        if (String.isBlank(soqlField))
          continue;
        String clause = buildSingleFilterClause(
          soqlField,
          f,
          fieldNameToSoqlPath
        );
        if (String.isNotBlank(clause))
          filterClauses.add(clause);
      }
      if (!filterClauses.isEmpty()) {
        whereClauses.add('(' + String.join(filterClauses, filterLogic) + ')');
      }
    }

    List<String> searchClauses = new List<String>();
    if (String.isNotBlank(searchTerm)) {
      String escapedSearchTerm =
        '%' +
        String.escapeSingleQuotes(searchTerm.trim()) +
        '%';
      for (SDTConfiguratorDTO.ColumnConfig cc : columnConfigs) {
        if (
          cc.isSearchable != false &&
          !cc.additional &&
          String.isNotBlank(cc.soqlFieldPath)
        ) {
          searchClauses.add(
            cc.soqlFieldPath + ' LIKE \'' + escapedSearchTerm + '\''
          );
        }
      }
    }
    if (!searchClauses.isEmpty()) {
      whereClauses.add('(' + String.join(searchClauses, ' OR ') + ')');
    }

    String soql =
      'SELECT ' +
      String.join(selectParts, ', ') +
      ' FROM ' +
      String.escapeSingleQuotes(baseObject);
    if (!whereClauses.isEmpty()) {
      soql += ' WHERE ' + String.join(whereClauses, ' AND ');
    }

    List<AggregateResult> rows;
    try {
      rows = new SDTConfiguratorSelector().getAggregateRecords(soql);
    } catch (Exception ex) {
      
      throw new AuraHandledException(
        'An unexpected error occurred. Please contact your administrator. Error Reference: ' + ex.getMessage()
      );
    }
    Map<String, Decimal> totals = new Map<String, Decimal>();
    if (!rows.isEmpty()) {
      AggregateResult row = rows[0];
      for (String alias : aliasToKey.keySet()) {
        Object rawValue = row.get(alias);
        totals.put(
          aliasToKey.get(alias),
          rawValue == null ? 0 : Decimal.valueOf(String.valueOf(rawValue))
        );
      }
    }
    return totals;
  }

  /**
   * Returns a Database.QueryLocator for batch export.
   * Reuses existing column config + query building logic.
   *
   * @param tableName    Table config name
   * @param parentId     Optional parent record Id
   * @param filtersJson  Optional filter payload JSON
   * @return Database.QueryLocator for batch processing
   */ public static Database.QueryLocator getExportQueryLocator(
    String tableName,
    String parentId,
    String filtersJson,
    String matrixParamsJson,
    String searchTerm
  ) {
    System.debug(LoggingLevel.FINE, '[Service] getExportQueryLocator G�� tableName');

    // G��G�� 1. Fetch config G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
    if (String.isBlank(tableName)) {
      throw new DynamicTableException('tableName is required for export.');
    }

    Table__c tableConfig = SDTConfiguratorSelector.getTableByName(tableName);
    if (tableConfig == null) {
      throw new DynamicTableException(
        'No Table__c found for name: ' + tableName
      );
    }

    String baseObject = tableConfig.Object_API_Name__c;

    // G��G�� 2. Fetch columns G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
    List<Table_Columns__c> rawColumns = SDTConfiguratorSelector.getColumnsByTableId(
      tableConfig.Id
    );

    if (rawColumns.isEmpty()) {
      throw new DynamicTableException(
        'No columns configured for table: ' + tableName
      );
    }

    // G��G�� 3. Build column configs + SOQL fields (same as getTableData) G��G��G��G��G��G��G��G��G��
    List<SDTConfiguratorDTO.ColumnConfig> columns = new List<SDTConfiguratorDTO.ColumnConfig>();
    List<String> soqlFields = new List<String>{ 'id' };
    String parentFilterField = null;
    String parentObjectType = String.isNotBlank(parentId)
      ? getObjectTypeFromId(parentId)
      : null;
    Map<String, String> fieldNameToSoqlPath = new Map<String, String>();

    Integer colIndex = 0;
    for (Table_Columns__c col : rawColumns) {
      SDTConfiguratorDTO.ColumnConfig cc = buildColumnConfig(
        col,
        baseObject,
        colIndex
      );

      if (
        String.isNotBlank(parentId) &&
        parentFilterField == null &&
        String.isNotBlank(col.Lookup_Field_API_Name__c) &&
        String.isNotBlank(parentObjectType) &&
        col.Object_Reference__c != null &&
        col.Object_Reference__c.equalsIgnoreCase(parentObjectType)
      ) {
        parentFilterField = col.Lookup_Field_API_Name__c;
      }

      if (!col.Additional_Column__c) {
        if (String.isNotBlank(cc.relationshipName)) {
          String dotField;
          if (
            col.Column_API_Name__c != null &&
            col.Column_API_Name__c.contains('.')
          ) {
            dotField = col.Column_API_Name__c.toLowerCase();
          } else {
            dotField = (cc.relationshipName +
              '.' +
              col.Column_API_Name__c)
              .toLowerCase();
          }

          if (!soqlFields.contains(dotField)) {
            soqlFields.add(dotField);
          }
          cc.soqlFieldPath = dotField;

          if (String.isNotBlank(col.Lookup_Field_API_Name__c)) {
            String lookupField = col.Lookup_Field_API_Name__c.toLowerCase();
            if (!soqlFields.contains(lookupField)) {
              soqlFields.add(lookupField);
            }
          }
        } else {
          String baseField = col.Column_API_Name__c != null
            ? col.Column_API_Name__c.toLowerCase()
            : '';
          if (!soqlFields.contains(baseField)) {
            soqlFields.add(baseField);
          }
          cc.soqlFieldPath = baseField;

          if (String.isNotBlank(col.Lookup_Field_API_Name__c)) {
            String lookupField = col.Lookup_Field_API_Name__c.toLowerCase();
            if (!soqlFields.contains(lookupField)) {
              soqlFields.add(lookupField);
            }
          }
        }
      }

      if (cc.dataType == 'Lookup' && String.isNotBlank(cc.lookupField)) {
        fieldNameToSoqlPath.put(cc.fieldName, cc.lookupField);
        fieldNameToSoqlPath.put(cc.key, cc.lookupField);
      } else if (String.isNotBlank(cc.soqlFieldPath)) {
        fieldNameToSoqlPath.put(cc.fieldName, cc.soqlFieldPath);
        fieldNameToSoqlPath.put(cc.key, cc.soqlFieldPath);
      }

      columns.add(cc);
      colIndex++;
    }

    if (String.isNotBlank(parentId) && String.isBlank(parentFilterField)) {
      parentFilterField = autoDetectParentLookup(baseObject, parentObjectType);
    }

    // G��G�� 4. Parse filters & Matrix params G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
    SDTConfiguratorDTO.FilterPayload filterPayload = null;
    if (String.isNotBlank(filtersJson)) {
      try {
        filterPayload = (SDTConfiguratorDTO.FilterPayload) JSON.deserialize(
          filtersJson,
          SDTConfiguratorDTO.FilterPayload.class
        );
      } catch (Exception ex) {
        System.debug(LoggingLevel.FINE, '[Service] getExportQueryLocator: invalid filtersJson');
      }
    }

    if (filterPayload != null && filterPayload.filters != null) {
      Filter_Framework_Setting__mdt setting = Filter_Framework_Setting__mdt.getInstance(
        'Default'
      );
      Integer maxFilters = (setting != null &&
        setting.Max_Filters__c != null)
        ? setting.Max_Filters__c.intValue()
        : 10;
      if (filterPayload.filters.size() > maxFilters) {
        throw new DynamicTableException(
          'The number of filters (' +
            filterPayload.filters.size() +
            ') exceeds the maximum limit allowed (' +
            maxFilters +
            ').'
        );
      }
    }

    if (String.isNotBlank(matrixParamsJson)) {
      try {
        SDTConfiguratorDTO.MatrixParams mParams = (SDTConfiguratorDTO.MatrixParams) JSON.deserialize(
          matrixParamsJson,
          SDTConfiguratorDTO.MatrixParams.class
        );

        // Collect all potential fields from Matrix Config
        Set<String> matrixKeys = new Set<String>();
        if (mParams.rowFields != null)
          matrixKeys.addAll(mParams.rowFields);
        if (mParams.columnFields != null)
          matrixKeys.addAll(mParams.columnFields);
        if (String.isNotBlank(mParams.aggregateField))
          matrixKeys.add(mParams.aggregateField);
        if (mParams.aggregateFields != null)
          matrixKeys.addAll(mParams.aggregateFields);

        for (String key : matrixKeys) {
          if (key == '_recordCount') continue;
          String soqlPath = fieldNameToSoqlPath.containsKey(key)
            ? fieldNameToSoqlPath.get(key)
            : key;
          if (String.isNotBlank(soqlPath)) {
            String lowercasePath = soqlPath.toLowerCase();
            if (!soqlFields.contains(lowercasePath)) {
              soqlFields.add(lowercasePath);
            }
          }
        }
      } catch (Exception ex) {
        System.debug(LoggingLevel.FINE, '[Service] getExportQueryLocator: invalid matrixParamsJson');
      }
    }

    // G��G�� 5. Build SOQL (no LIMIT for batch) G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
    List<String> whereClauses = new List<String>();

    if (String.isNotBlank(parentId) && String.isNotBlank(parentFilterField)) {
      String safeId = String.escapeSingleQuotes(parentId);
      whereClauses.add(parentFilterField + ' = \'' + safeId + '\'');
    }

    if (
      filterPayload != null &&
      filterPayload.filters != null &&
      !filterPayload.filters.isEmpty()
    ) {
      String filterLogic = (filterPayload.logic == 'OR') ? ' OR ' : ' AND ';
      List<String> filterClauses = new List<String>();

      for (SDTConfiguratorDTO.FilterCriteria f : filterPayload.filters) {
        if (String.isBlank(f.fieldName) || String.isBlank(f.operator))
          continue;

        String soqlField = String.isNotBlank(f.soqlFieldPath)
          ? f.soqlFieldPath
          : fieldNameToSoqlPath.get(f.fieldName);

        if (String.isBlank(soqlField))
          continue;

        String clause = buildSingleFilterClause(
          soqlField,
          f,
          fieldNameToSoqlPath
        );
        if (String.isNotBlank(clause)) {
          filterClauses.add(clause);
        }
      }

      if (!filterClauses.isEmpty()) {
        whereClauses.add('(' + String.join(filterClauses, filterLogic) + ')');
      }
    }

    List<String> searchClauses = new List<String>();
    if (String.isNotBlank(searchTerm)) {
      String escapedSearchTerm =
        '%' +
        String.escapeSingleQuotes(searchTerm.trim()) +
        '%';
      for (SDTConfiguratorDTO.ColumnConfig cc : columns) {
        if (
          cc.isSearchable != false &&
          !cc.additional &&
          String.isNotBlank(cc.soqlFieldPath)
        ) {
          searchClauses.add(
            cc.soqlFieldPath + ' LIKE \'' + escapedSearchTerm + '\''
          );
        }
      }
    }

    if (!searchClauses.isEmpty()) {
      whereClauses.add('(' + String.join(searchClauses, ' OR ') + ')');
    }

    String soql =
      'SELECT ' +
      String.join(soqlFields, ', ') +
      ' FROM ' +
      baseObject;

    if (!whereClauses.isEmpty()) {
      soql += ' WHERE ' + String.join(whereClauses, ' AND ');
    }

    // NO LIMIT G�� batch handles all records
    System.debug(LoggingLevel.FINE, '[Service] getExportQueryLocator SOQL');
    return Database.getQueryLocator(soql, AccessLevel.USER_MODE);
  }

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
  public List<Table_Columns__c> getTableColumns(Id tableId) {
    return SDTConfiguratorSelector.getColumnsByTableId(tableId);
  }

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
      

      throw new AuraHandledException(
        'An unexpected error occurred. Please contact your administrator. Error Reference: ' + ex.getMessage()
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
      

      throw new AuraHandledException(
        'An unexpected error occurred. Please contact your administrator. Error Reference: ' + ex.getMessage()
      );
    }
  }

  // G��G�� Helper: Resolve Access Overrides G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��G��
  private static void applyAccessOverrides(
    SDTConfiguratorDTO.TableResult result,
    Table__c tableConfig
  ) {
    Id userId = UserInfo.getUserId();
    Id profileId = UserInfo.getProfileId();
    Id roleId = UserInfo.getUserRoleId();

    Set<Id> groupIds = new Set<Id>();
    for (GroupMember gm : [
      SELECT GroupId
      FROM GroupMember
      WHERE UserOrGroupId = :userId
    ]) {
      groupIds.add(gm.GroupId);
    }

    // 1. Table Feature Overrides
    List<Table_Feature_Override__c> featureOverrides = [
      SELECT
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
      WHERE Table__c = :tableConfig.Id
    ];

    Table_Feature_Override__c winningFeatureOverride = null;
    Integer highestFeaturePriority = 0;

    for (Table_Feature_Override__c fo : featureOverrides) {
      Integer priority = getOverridePriority(
        fo.Context_Type__c,
        fo.Context_Value__c,
        userId,
        profileId,
        roleId,
        groupIds
      );
      if (priority > highestFeaturePriority) {
        highestFeaturePriority = priority;
        winningFeatureOverride = fo;
      }
    }

    if (winningFeatureOverride != null) {
      if (winningFeatureOverride.Override_Enable_Export__c == 'Enabled')
        result.enableExport = true;
      else if (winningFeatureOverride.Override_Enable_Export__c == 'Disabled')
        result.enableExport = false;

      if (winningFeatureOverride.Override_Enable_Import__c == 'Enabled')
        result.enableImport = true;
      else if (winningFeatureOverride.Override_Enable_Import__c == 'Disabled')
        result.enableImport = false;

      if (winningFeatureOverride.Override_Enable_Filters__c == 'Enabled')
        result.enableFilters = true;
      else if (winningFeatureOverride.Override_Enable_Filters__c == 'Disabled')
        result.enableFilters = false;

      if (winningFeatureOverride.Override_New_Record__c == 'Enabled')
        result.enableNewRecord = true;
      else if (winningFeatureOverride.Override_New_Record__c == 'Disabled')
        result.enableNewRecord = false;

      if (winningFeatureOverride.Override_Hide_Row_Actions__c == 'Enabled')
        result.hideRowActions = true;
      else if (
        winningFeatureOverride.Override_Hide_Row_Actions__c == 'Disabled'
      )
        result.hideRowActions = false;

      if (winningFeatureOverride.Override_Enable_Matrix_View__c == 'Enabled')
        result.enableMatrixView = true;
      else if (
        winningFeatureOverride.Override_Enable_Matrix_View__c == 'Disabled'
      )
        result.enableMatrixView = false;

      if (winningFeatureOverride.Override_Enable_Column_Manager__c == 'Enabled')
        result.enableColumnManager = true;
      else if (
        winningFeatureOverride.Override_Enable_Column_Manager__c == 'Disabled'
      )
        result.enableColumnManager = false;

      if (winningFeatureOverride.Override_Enable_Views__c == 'Enabled')
        result.enableViews = true;
      else if (winningFeatureOverride.Override_Enable_Views__c == 'Disabled')
        result.enableViews = false;
    }

    // 2. Action Overrides
    if (result.actions != null && !result.actions.isEmpty()) {
      List<Table_Action_Override__c> actionOverrides = [
        SELECT
          Table_Action__c,
          Context_Type__c,
          Context_Value__c,
          Action_Visibility__c
        FROM Table_Action_Override__c
        WHERE Table_Action__r.Table__c = :tableConfig.Id
      ];

      Map<Id, List<Table_Action_Override__c>> overridesByAction = new Map<Id, List<Table_Action_Override__c>>();
      for (Table_Action_Override__c ao : actionOverrides) {
        if (!overridesByAction.containsKey(ao.Table_Action__c)) {
          overridesByAction.put(
            ao.Table_Action__c,
            new List<Table_Action_Override__c>()
          );
        }
        overridesByAction.get(ao.Table_Action__c).add(ao);
      }

      List<SDTConfiguratorDTO.TableAction> visibleActions = new List<SDTConfiguratorDTO.TableAction>();
      for (SDTConfiguratorDTO.TableAction act : result.actions) {
        List<Table_Action_Override__c> actsOverrides = overridesByAction.get(
          act.id
        );
        if (actsOverrides == null || actsOverrides.isEmpty()) {
          visibleActions.add(act); // No override, so visible
          continue;
        }

        Integer highestActPriority = 0;
        Table_Action_Override__c winningActOverride = null;
        for (Table_Action_Override__c ao : actsOverrides) {
          Integer priority = getOverridePriority(
            ao.Context_Type__c,
            ao.Context_Value__c,
            userId,
            profileId,
            roleId,
            groupIds
          );
          if (priority > highestActPriority) {
            highestActPriority = priority;
            winningActOverride = ao;
          }
        }

        // If winning override hides the action, skip it. Otherwise include.
        if (
          winningActOverride != null &&
          winningActOverride.Action_Visibility__c == 'Hidden'
        ) {
          // hidden
        } else {
          visibleActions.add(act);
        }
      }
      result.actions = visibleActions;
    }
  }

  private static Integer getOverridePriority(
    String contextType,
    String contextValue,
    Id userId,
    Id profileId,
    Id roleId,
    Set<Id> groupIds
  ) {
    if (contextType == 'User' && contextValue == userId)
      return 40;
    if (contextType == 'Profile' && contextValue == profileId)
      return 30;
    if (contextType == 'Role' && contextValue == roleId)
      return 20;
    if (contextType == 'Public Group' && groupIds.contains(contextValue))
      return 10;
    return 0; // Not applicable
  }

  // -----------------------------------------------------------------
  // METHOD 1: buildWhereClause
  // -----------------------------------------------------------------
  public String buildWhereClause(
    List<SDTConfiguratorDTO.ExportFilterConfig> filters
  ) {
    return buildWhereClause(filters, 'AND');
  }

  public String buildWhereClause(
    List<SDTConfiguratorDTO.ExportFilterConfig> filters,
    String logic
  ) {
    return buildWhereClause(filters, logic, null);
  }

  public String buildWhereClause(
    List<SDTConfiguratorDTO.ExportFilterConfig> filters,
    String logic,
    String customLogic
  ) {
    if (filters == null || filters.isEmpty()) {
      return '';
    }

    Map<Integer, String> indexToClause = new Map<Integer, String>();
    List<String> conditions = new List<String>();
    Integer defaultIdx = 1;

    for (SDTConfiguratorDTO.ExportFilterConfig f : filters) {
      Integer oldSize = conditions.size();
      if (String.isBlank(f.fieldApiName) || String.isBlank(f.operator)) {
        continue;
      }

      String field = String.escapeSingleQuotes(f.fieldApiName);
      String op = f.operator.toUpperCase().trim();
      String fieldType = String.isNotBlank(f.fieldType)
        ? f.fieldType.toUpperCase().trim()
        : '';
      if (op == 'EQUALS')
        op = '=';
      else if (op == 'NOT_EQUALS')
        op = '!=';
      else if (op == 'GREATER_THAN')
        op = '>';
      else if (op == 'LESS_THAN')
        op = '<';
      else if (op == 'GREATER_OR_EQUAL' || op == 'GTE')
        op = '>=';
      else if (op == 'LESS_OR_EQUAL' || op == 'LTE')
        op = '<=';
      else if (op == 'NOT_IN' || op == 'EXCLUDES')
        op = 'NOT IN';
      else if (op == 'INCLUDES')
        op = 'IN';

      // Fallback for single value check: if value is blank but values has a value, use values[0]
      String checkValue = f.value;
      if (
        String.isBlank(checkValue) &&
        f.values != null &&
        !f.values.isEmpty()
      ) {
        checkValue = f.values[0];
      }

      if (op == 'IS_BLANK') {
        conditions.add(field + ' = null');
      } else if (op == 'IS_NOT_BLANK') {
        conditions.add(field + ' != null');
      } else if (op == 'IS_TRUE' || op == 'TRUE') {
        conditions.add(field + ' = true');
      } else if (op == 'IS_FALSE' || op == 'FALSE') {
        conditions.add(field + ' = false');
      } else if (op == 'IN' || op == 'NOT IN') {
        if (f.values == null || f.values.isEmpty())
          continue;
        List<String> escaped = new List<String>();
        for (String v : f.values) {
          if (String.isNotBlank(v)) {
            escaped.add(formatSoqlFilterLiteral(v, fieldType));
          }
        }
        if (escaped.isEmpty())
          continue;
        conditions.add(
          field + ' ' + op + ' (' + String.join(escaped, ',') + ')'
        );
      } else if (op == 'CONTAINS' || op == 'NOT_CONTAINS') {
        if (String.isBlank(checkValue))
          continue;
        if (op == 'NOT_CONTAINS') {
          conditions.add(
            '(NOT ' +
              field +
              ' LIKE \'%' +
              String.escapeSingleQuotes(checkValue) +
              '%\')'
          );
        } else {
          conditions.add(
            field + ' LIKE \'%' + String.escapeSingleQuotes(checkValue) + '%\''
          );
        }
      } else if (op == 'STARTS_WITH') {
        if (String.isBlank(checkValue))
          continue;
        conditions.add(
          field + ' LIKE \'' + String.escapeSingleQuotes(checkValue) + '%\''
        );
      } else if (op == 'ENDS_WITH') {
        if (String.isBlank(checkValue))
          continue;
        conditions.add(
          field + ' LIKE \'%' + String.escapeSingleQuotes(checkValue) + '\''
        );
      } else if (op == 'BETWEEN' || op == 'RANGE') {
        if (f.values == null || f.values.size() < 2)
          continue;
        conditions.add(
          '(' +
            field +
            ' >= ' +
            formatSoqlFilterLiteral(f.values[0], fieldType) +
            ' AND ' +
            field +
            ' <= ' +
            formatSoqlFilterLiteral(f.values[1], fieldType) +
            ')'
        );
      } else if (op == 'BEFORE') {
        if (String.isBlank(checkValue))
          continue;
        conditions.add(
          field + ' < ' + formatSoqlFilterLiteral(checkValue, fieldType)
        );
      } else if (op == 'AFTER') {
        if (String.isBlank(checkValue))
          continue;
        conditions.add(
          field + ' > ' + formatSoqlFilterLiteral(checkValue, fieldType)
        );
      } else if (op == 'LIKE' || op == 'NOT LIKE') {
        if (String.isBlank(checkValue))
          continue;
        if (op == 'NOT LIKE') {
          conditions.add(
            '(NOT ' +
              field +
              ' LIKE \'' +
              String.escapeSingleQuotes(checkValue) +
              '\')'
          );
        } else {
          conditions.add(
            field + ' LIKE \'' + String.escapeSingleQuotes(checkValue) + '\''
          );
        }
      } else if (
        new Set<String>{ '=', '!=', '>=', '<=', '>', '<' }.contains(op)
      ) {
        if (String.isBlank(checkValue))
          continue;
        if (checkValue.equalsIgnoreCase('null')) {
          conditions.add(field + ' ' + op + ' NULL');
        } else {
          conditions.add(
            field +
              ' ' +
              op +
              ' ' +
              formatSoqlFilterLiteral(checkValue, fieldType)
          );
        }
      }
      if (conditions.size() > oldSize) {
        String clause = conditions[conditions.size() - 1];
        Integer idx = f.filterIndex != null ? f.filterIndex : defaultIdx;
        indexToClause.put(idx, clause);
      }
      defaultIdx++;
    }
    if ('CUSTOM'.equalsIgnoreCase(logic) && String.isNotBlank(customLogic)) {
      String resolved = resolveCustomLogicExpression(indexToClause, customLogic);
      if (String.isNotBlank(resolved)) {
        return resolved;
      }
    }
    String joinLogic = (logic == 'OR' || logic == 'ANY') ? ' OR ' : ' AND ';
    return conditions.isEmpty() ? '' : String.join(conditions, joinLogic);
  }

  private static String resolveCustomLogicExpression(
    Map<Integer, String> indexToClause,
    String customLogic
  ) {
    if (String.isBlank(customLogic)) {
      return '';
    }
    String customExpr = customLogic.toUpperCase();
    customExpr = customExpr.replaceAll('\\bAND\\b', ' AND ')
                           .replaceAll('\\bOR\\b', ' OR ')
                           .replaceAll('\\bNOT\\b', ' NOT ');

    Pattern p = Pattern.compile('\\b\\d+\\b');
    Matcher m = p.matcher(customExpr);
    Set<Integer> indicesSet = new Set<Integer>();
    while (m.find()) {
      indicesSet.add(Integer.valueOf(m.group()));
    }

    List<Integer> sortedIndices = new List<Integer>(indicesSet);
    sortedIndices.sort();
    List<Integer> descIndices = new List<Integer>();
    for (Integer i = sortedIndices.size() - 1; i >= 0; i--) {
      descIndices.add(sortedIndices[i]);
    }

    for (Integer idx : descIndices) {
      String clause = indexToClause.get(idx);
      if (String.isBlank(clause)) {
        clause = '1=1';
      }
      String safeClause = clause.replace('\\', '\\\\').replace('$', '\\$');
      customExpr = customExpr.replaceAll('\\b' + idx + '\\b', '(' + safeClause + ')');
    }

    return customExpr;
  }

  private String formatSoqlFilterLiteral(String value, String fieldType) {
    if (value == null) {
      return 'NULL';
    }

    String trimmedValue = value.trim();
    String normalizedType = String.isNotBlank(fieldType)
      ? fieldType.toUpperCase().trim()
      : '';

    if (normalizedType == 'DATE') {
      if (
        Pattern.matches('^\\d{4}-\\d{2}-\\d{2}$', trimmedValue) ||
        Pattern.matches('^[A-Z_]+(:\\d+)?$', trimmedValue.toUpperCase())
      ) {
        return String.escapeSingleQuotes(trimmedValue);
      }
      throw new DynamicTableException('Invalid date filter value: ' + value);
    }

    if (normalizedType == 'DATETIME') {
      if (
        Pattern.matches(
          '^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(\\.\\d{3})?(Z|[+-]\\d{2}:\\d{2})?$',
          trimmedValue
        ) || Pattern.matches('^[A-Z_]+(:\\d+)?$', trimmedValue.toUpperCase())
      ) {
        return String.escapeSingleQuotes(trimmedValue);
      }
      throw new DynamicTableException(
        'Invalid datetime filter value: ' + value
      );
    }

    if (normalizedType == 'TIME') {
      if (Pattern.matches('^\\d{2}:\\d{2}:\\d{2}(\\.\\d{3})?$', trimmedValue)) {
        return String.escapeSingleQuotes(trimmedValue);
      }
      throw new DynamicTableException('Invalid time filter value: ' + value);
    }

    if (
      normalizedType == 'NUMBER' ||
      normalizedType == 'CURRENCY' ||
      normalizedType == 'PERCENT' ||
      normalizedType == 'PERCENTAGE' ||
      normalizedType == 'DOUBLE' ||
      normalizedType == 'INTEGER' ||
      normalizedType == 'LONG' ||
      normalizedType == 'DECIMAL'
    ) {
      if (Pattern.matches('^-?\\d+(\\.\\d+)?$', trimmedValue)) {
        return String.escapeSingleQuotes(trimmedValue);
      }
      throw new DynamicTableException('Invalid numeric filter value: ' + value);
    }

    if (
      normalizedType == 'BOOLEAN' &&
      (trimmedValue.equalsIgnoreCase('true') ||
      trimmedValue.equalsIgnoreCase('false'))
    ) {
      return trimmedValue.toLowerCase();
    }

    return '\'' + String.escapeSingleQuotes(trimmedValue) + '\'';
  }

  // -----------------------------------------------------------------
  // METHOD 2: buildCsvString
  // -----------------------------------------------------------------
  public String buildCsvString(
    List<SObject> records,
    List<SDTConfiguratorDTO.ExportColumnConfig> columns
  ) {
    List<String> lines = new List<String>();
    List<String> headers = new List<String>();
    for (SDTConfiguratorDTO.ExportColumnConfig col : columns) {
      headers.add(DynamicTableCsvSecurity.escapeCsv(col.label));
    }
    lines.add(String.join(headers, ','));

    for (SObject rec : records) {
      List<String> cells = new List<String>();
      for (SDTConfiguratorDTO.ExportColumnConfig col : columns) {
        Object rawVal = traverseSObject(rec, col.fieldApiName);
        cells.add(DynamicTableCsvSecurity.escapeCsv(formatCellValue(rawVal, col.fieldType)));
      }
      lines.add(String.join(cells, ','));
    }
    return String.join(lines, '\n');
  }

  private String formatCellValue(Object val, String fieldType) {
    if (val == null)
      return '';

    if (val instanceof Datetime) {
      return ((Datetime) val).format('yyyy-MM-dd HH:mm:ss');
    } else if (val instanceof Date) {
      return String.valueOf((Date) val);
    }

    String fType = (fieldType != null) ? fieldType.toUpperCase() : 'STRING';
    if (fType == 'BOOLEAN') {
      return (Boolean) val ? 'TRUE' : 'FALSE';
    }
    if (fType == 'CURRENCY' || fType == 'DOUBLE' || fType == 'NUMBER') {
      return String.valueOf(val);
    }
    return String.valueOf(val);
  }

  

  // ============================================================
  // MATRIX GROUPING LOGIC
  // ============================================================
  public String buildAggregateQuery(SDTConfiguratorDTO.MatrixRequest req) {
    return buildAggregateQuery(req, null, null);
  }

  public String buildAggregateQuery(
    SDTConfiguratorDTO.MatrixRequest req,
    List<SDTConfiguratorDTO.ColumnConfig> searchColumns,
    String searchTerm
  ) {
    validateMatrixRequest(req);
    this.matrixObjectApiName = DynamicTableSecurity.validateObjectApiName(
      req.objectApiName,
      true
    );

    List<SDTConfiguratorDTO.MatrixGroupField> allGroupFields = new List<SDTConfiguratorDTO.MatrixGroupField>();
    allGroupFields.addAll(req.rowGroupFields);
    if (req.colGroupFields != null) {
      allGroupFields.addAll(req.colGroupFields);
    }

    List<String> selectParts = new List<String>();
    Integer grpIdx = 0;

    for (SDTConfiguratorDTO.MatrixGroupField gf : allGroupFields) {
      List<String> expressions = buildGroupExpressions(gf);
      for (Integer i = 0; i < expressions.size(); i++) {
        selectParts.add(
          expressions[i] + ' ' + buildGroupAlias(grpIdx, i, expressions.size())
        );
      }
      grpIdx++;
    }

    List<String> summaryAliases = new List<String>();
    Integer aggIdx = 0;
    for (SDTConfiguratorDTO.MatrixSummaryField sf : req.summaryFields) {
      String alias = 'agg' + aggIdx++;
      String aggFunc = buildAggregateFunction(sf, alias);
      selectParts.add(aggFunc);
      summaryAliases.add(alias);
    }

    Set<String> groupByPartsSet = new Set<String>();
    for (SDTConfiguratorDTO.MatrixGroupField gf : allGroupFields) {
      groupByPartsSet.addAll(buildGroupExpressions(gf));
    }
    List<String> groupByParts = new List<String>(groupByPartsSet);

    String whereClause = buildMatrixWhereClause(req);
    String searchClause = buildMatrixSearchClause(searchColumns, searchTerm);
    if (String.isNotBlank(searchClause)) {
      whereClause = String.isNotBlank(whereClause)
        ? '(' + whereClause + ') AND (' + searchClause + ')'
        : searchClause;
    }

    List<String> orderByParts = new List<String>();
    for (SDTConfiguratorDTO.MatrixGroupField gf : req.rowGroupFields) {
      for (String expression : buildGroupExpressions(gf)) {
        orderByParts.add(expression + ' ASC NULLS LAST');
      }
    }
    if (req.colGroupFields != null) {
      for (SDTConfiguratorDTO.MatrixGroupField gf : req.colGroupFields) {
        for (String expression : buildGroupExpressions(gf)) {
          orderByParts.add(expression + ' ASC NULLS LAST');
        }
      }
    }

    String soql =
      'SELECT ' +
      String.join(selectParts, ', ') +
      ' FROM ' +
      this.matrixObjectApiName;

    if (String.isNotBlank(whereClause)) {
      soql += ' WHERE ' + whereClause;
    }

    soql += ' GROUP BY ' + String.join(groupByParts, ', ');
    soql += ' ORDER BY ' + String.join(orderByParts, ', ');

    System.debug(LoggingLevel.FINE, '[Service] Matrix Query built.');
    return soql;
  }

  private String buildMatrixSearchClause(
    List<SDTConfiguratorDTO.ColumnConfig> searchColumns,
    String searchTerm
  ) {
    if (String.isBlank(searchTerm) || searchColumns == null || searchColumns.isEmpty()) {
      return '';
    }

    String escapedSearchTerm =
      '%' +
      String.escapeSingleQuotes(searchTerm.trim()) +
      '%';
    List<String> searchClauses = new List<String>();
    for (SDTConfiguratorDTO.ColumnConfig cc : searchColumns) {
      if (
        cc != null &&
        cc.isSearchable != false &&
        !cc.additional &&
        String.isNotBlank(cc.soqlFieldPath)
      ) {
        String fieldPath = DynamicTableSecurity.validateFieldPath(
          this.matrixObjectApiName,
          cc.soqlFieldPath
        );
        searchClauses.add(fieldPath + ' LIKE \'' + escapedSearchTerm + '\'');
      }
    }

    return searchClauses.isEmpty() ? '' : String.join(searchClauses, ' OR ');
  }

  public Integer getMatrixSourceRecordCount(SDTConfiguratorDTO.MatrixRequest req) {
    validateMatrixRequest(req);
    this.matrixObjectApiName = DynamicTableSecurity.validateObjectApiName(
      req.objectApiName,
      true
    );

    String soql =
      'SELECT COUNT() FROM ' + this.matrixObjectApiName;
    String whereClause = buildMatrixWhereClause(req);
    if (String.isNotBlank(whereClause)) {
      soql += ' WHERE ' + whereClause;
    }
    // Cap at 45,005 G�� strictly above matrixAggregateLimit (45,000) so the Orchestrator
    // correctly detects oversized datasets (sourceRecordCount >= 45,000 G�� ASYNC_REQUIRED),
    // while staying safely below the 50,000 governor limit (~50 metadata rows also consumed).
    // LIMIT 50001 was the original crash point: COUNT() would scan all 50,001 rows G�� LimitException.
    soql += ' LIMIT 49500';

    return SDTConfiguratorSelector.getRecordCount(soql);
  }

  private String buildMatrixWhereClause(SDTConfiguratorDTO.MatrixRequest req) {
    String whereClause = buildWhereClause(req.filters, req.logic);

    if (String.isNotBlank(req.parentId)) {
      try {
        Id pId = (Id) req.parentId;
        String parentObjName = pId.getSObjectType().getDescribe().getName();
        String parentFilterField = autoDetectParentLookup(
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
        System.debug(LoggingLevel.FINE, 'Error resolving parent filter in matrix aggregation');
      }
    }

    return whereClause;
  }

  private String buildGroupExpression(SDTConfiguratorDTO.MatrixGroupField gf) {
    return buildGroupExpressions(gf)[0];
  }

  private List<String> buildGroupExpressions(
    SDTConfiguratorDTO.MatrixGroupField gf
  ) {
    String field = DynamicTableSecurity.validateFieldPath(
      this.matrixObjectApiName,
      gf.fieldApiName
    );

    if (String.isBlank(gf.granularity)) {
      return new List<String>{ field };
    }

    Set<String> allowedGranularities = new Set<String>{
      'CALENDAR_YEAR',
      'CALENDAR_MONTH',
      'CALENDAR_QUARTER',
      'DAY_IN_MONTH',
      'DAY_IN_WEEK',
      'DAY_IN_YEAR',
      'WEEK_IN_MONTH',
      'WEEK_IN_YEAR',
      'FISCAL_YEAR',
      'FISCAL_QUARTER',
      'HOUR_IN_DAY'
    };

    String gran = gf.granularity.toUpperCase().trim();

    if (!allowedGranularities.contains(gran)) {
      throw new MatrixQueryException(
        'Invalid granularity: ' +
          gf.granularity +
          '. Allowed: ' +
          String.join(new List<String>(allowedGranularities), ', ')
      );
    }

    if (gran == 'CALENDAR_MONTH') {
      return new List<String>{
        'CALENDAR_YEAR(' + field + ')',
        'CALENDAR_MONTH(' + field + ')'
      };
    }
    if (gran == 'CALENDAR_QUARTER') {
      return new List<String>{
        'CALENDAR_YEAR(' + field + ')',
        'CALENDAR_QUARTER(' + field + ')'
      };
    }

    return new List<String>{ gran + '(' + field + ')' };
  }

  private String buildGroupAlias(
    Integer groupIndex,
    Integer partIndex,
    Integer partCount
  ) {
    if (partCount == 1) {
      return 'grp' + groupIndex;
    }
    return 'grp' + groupIndex + (partIndex == 0 ? 'a' : 'b');
  }

  private String buildAggregateFunction(
    SDTConfiguratorDTO.MatrixSummaryField sf,
    String alias
  ) {
    Set<String> allowedFunctions = new Set<String>{
      'SUM',
      'COUNT',
      'AVG',
      'MIN',
      'MAX',
      'COUNT_DISTINCT'
    };

    if (String.isBlank(sf.aggregateFunction)) {
      throw new MatrixQueryException('aggregateFunction is required.');
    }

    String func = sf.aggregateFunction.toUpperCase().trim();

    if (!allowedFunctions.contains(func)) {
      throw new MatrixQueryException(
        'Invalid aggregate function: ' + sf.aggregateFunction
      );
    }

    String field = DynamicTableSecurity.validateFieldPath(
      this.matrixObjectApiName,
      sf.fieldApiName
    );
    return func + '(' + field + ') ' + alias;
  }

  private void validateMatrixRequest(SDTConfiguratorDTO.MatrixRequest req) {
    if (req == null) {
      throw new MatrixQueryException('MatrixRequest cannot be null.');
    }
    if (String.isBlank(req.objectApiName)) {
      throw new MatrixQueryException('objectApiName is required.');
    }
    if (req.rowGroupFields == null || req.rowGroupFields.isEmpty()) {
      throw new MatrixQueryException(
        'At least one row group field is required.'
      );
    }
    if (req.summaryFields == null || req.summaryFields.isEmpty()) {
      throw new MatrixQueryException(
        'At least one summary field is required.'
      );
    }

    Integer totalGroupFields =
      req.rowGroupFields.size() +
      (req.colGroupFields != null ? req.colGroupFields.size() : 0);

    if (totalGroupFields > 10) {
      throw new MatrixQueryException(
        'Total group fields limit exceeded (Max 10).'
      );
    }

    Integer maxSummaryFields = getMatrixMaxSummaryFields();
    if (req.summaryFields.size() > maxSummaryFields) {
      throw new MatrixQueryException(
        'Maximum ' + maxSummaryFields + ' summary fields are allowed.'
      );
    }
  }

  public SDTConfiguratorDTO.MatrixResult buildMatrixResult(
    List<AggregateResult> aggResults,
    SDTConfiguratorDTO.MatrixRequest req
  ) {
    return buildMatrixResult(aggResults, req, req != null ? req.previewRowLimit : null);
  }

  public SDTConfiguratorDTO.MatrixResult buildMatrixResult(
    List<AggregateResult> aggResults,
    SDTConfiguratorDTO.MatrixRequest req,
    Integer previewRowLimit
  ) {
    validateMatrixRequest(req);
    this.matrixObjectApiName = DynamicTableSecurity.validateObjectApiName(
      req.objectApiName,
      true
    );

    SDTConfiguratorDTO.MatrixResult result = new SDTConfiguratorDTO.MatrixResult();
    result.cells = new List<SDTConfiguratorDTO.MatrixCell>();

    result.rowFieldLabels = extractLabels(req.rowGroupFields);
    result.colFieldLabels = extractLabels(req.colGroupFields);
    result.summaryAliases = new List<String>();
    result.summaryLabels = new List<String>();

    Integer aggIdx = 0;
    for (SDTConfiguratorDTO.MatrixSummaryField sf : req.summaryFields) {
      String alias = 'agg' + aggIdx++;
      result.summaryAliases.add(alias);
      result.summaryLabels.add(
        String.isNotBlank(sf.label)
          ? sf.label
          : sf.aggregateFunction + '(' + sf.fieldApiName + ')'
      );
    }

    List<List<String>> rowKeysList = new List<List<String>>();
    List<List<String>> colKeysList = new List<List<String>>();
    Set<String> rowKeysSet = new Set<String>();
    Set<String> colKeysSet = new Set<String>();
    List<MatrixColumnWrapper> colWrappersList = new List<MatrixColumnWrapper>();

    Integer rowFieldCount = req.rowGroupFields.size();
    Integer colFieldCount = req.colGroupFields != null
      ? req.colGroupFields.size()
      : 0;

    // [CPU FIX] Pre-compute expression counts ONCE before the loop
    // to avoid calling buildGroupExpressions (and validateFieldPath) per row
    Map<Integer, Integer> groupExprCountCache = new Map<Integer, Integer>();
    for (Integer i = 0; i < rowFieldCount; i++) {
      groupExprCountCache.put(i, getGroupExpressionCount(req.rowGroupFields[i]));
    }
    for (Integer i = 0; i < colFieldCount; i++) {
      groupExprCountCache.put(rowFieldCount + i, getGroupExpressionCount(req.colGroupFields[i]));
    }

    Map<String, Map<String, List<Decimal>>> grandTotalValues = new Map<String, Map<String, List<Decimal>>>();
    Map<String, String> summaryAliasToFunction = new Map<String, String>();
    for (Integer s = 0; s < result.summaryAliases.size(); s++) {
      summaryAliasToFunction.put(
        result.summaryAliases[s],
        req.summaryFields[s].aggregateFunction
      );
    }

    for (AggregateResult ar : aggResults) {
      List<String> rowParts = new List<String>();
      for (Integer i = 0; i < rowFieldCount; i++) {
        SDTConfiguratorDTO.MatrixGroupField gf = req.rowGroupFields[i];
        rowParts.add(formatGroupValueFast(ar, i, gf, groupExprCountCache.get(i)));
      }

      List<String> colParts = new List<String>();
      for (Integer i = 0; i < colFieldCount; i++) {
        SDTConfiguratorDTO.MatrixGroupField gf = req.colGroupFields[i];
        Integer gIdx = rowFieldCount + i;
        colParts.add(formatGroupValueFast(ar, gIdx, gf, groupExprCountCache.get(gIdx)));
      }

      String rowKey = String.join(rowParts, '|');
      String colKey = String.join(colParts, '|');

      if (!rowKeysSet.contains(rowKey)) {
        rowKeysSet.add(rowKey);
        rowKeysList.add(rowParts);
      }

      List<Object> rawColValues = new List<Object>();
      for (Integer i = 0; i < colFieldCount; i++) {
        SDTConfiguratorDTO.MatrixGroupField gf = req.colGroupFields[i];
        Integer gIdx = rowFieldCount + i;
        Integer exprCount = groupExprCountCache.get(gIdx);
        for (Integer e = 0; e < exprCount; e++) {
          rawColValues.add(ar.get(buildGroupAlias(gIdx, e, exprCount)));
        }
      }

      if (!colKeysSet.contains(colKey)) {
        colKeysSet.add(colKey);
        colWrappersList.add(new MatrixColumnWrapper(rawColValues, colParts, req.colGroupFields));
      }

      for (Integer s = 0; s < result.summaryAliases.size(); s++) {
        String alias = result.summaryAliases[s];
        Object rawVal = ar.get(alias);
        Decimal decimalValue = rawVal != null
          ? Decimal.valueOf(String.valueOf(rawVal))
          : null;

        if (!grandTotalValues.containsKey(colKey)) {
          grandTotalValues.put(colKey, new Map<String, List<Decimal>>());
        }
        if (!grandTotalValues.get(colKey).containsKey(alias)) {
          grandTotalValues.get(colKey).put(alias, new List<Decimal>());
        }
        if (decimalValue != null) {
          grandTotalValues.get(colKey).get(alias).add(decimalValue);
        }

        SDTConfiguratorDTO.MatrixCell cell = new SDTConfiguratorDTO.MatrixCell();
        cell.rowKey = rowKey;
        cell.colKey = colKey;
        cell.alias = alias;
        cell.value = decimalValue;
        result.cells.add(cell);
      }
    }

    colWrappersList.sort();
    for (MatrixColumnWrapper wrapper : colWrappersList) {
      colKeysList.add(wrapper.formattedColParts);
    }

    Integer totalRowCount = rowKeysList.size();
    Integer effectiveLimit = previewRowLimit != null && previewRowLimit > 0
      ? previewRowLimit
      : totalRowCount;
    Boolean isTruncated = totalRowCount > effectiveLimit;

    Set<String> previewRowKeySet = new Set<String>();
    List<List<String>> previewRowKeys = new List<List<String>>();
    for (Integer i = 0; i < rowKeysList.size() && i < effectiveLimit; i++) {
      previewRowKeys.add(rowKeysList[i]);
      previewRowKeySet.add(String.join(rowKeysList[i], '|'));
    }

    if (isTruncated) {
      List<SDTConfiguratorDTO.MatrixCell> previewCells = new List<SDTConfiguratorDTO.MatrixCell>();
      for (SDTConfiguratorDTO.MatrixCell cell : result.cells) {
        if (previewRowKeySet.contains(cell.rowKey)) {
          previewCells.add(cell);
        }
      }
      result.cells = previewCells;
    }

    result.rowKeys = previewRowKeys;
    result.colKeys = colKeysList;
    result.totalCellCount = result.cells.size();
    result.totalMatrixRowCount = totalRowCount;
    result.previewRowLimit = effectiveLimit;
    result.isPreviewTruncated = isTruncated;
    result.grandTotalCells = buildMatrixGrandTotalCells(
      colKeysList,
      result.summaryAliases,
      summaryAliasToFunction,
      grandTotalValues
    );

    return result;
  }

  private List<SDTConfiguratorDTO.MatrixCell> buildMatrixGrandTotalCells(
    List<List<String>> colKeysList,
    List<String> summaryAliases,
    Map<String, String> summaryAliasToFunction,
    Map<String, Map<String, List<Decimal>>> grandTotalValues
  ) {
    List<SDTConfiguratorDTO.MatrixCell> cells = new List<SDTConfiguratorDTO.MatrixCell>();
    for (List<String> colParts : colKeysList) {
      String colKey = String.join(colParts, '|');
      for (String alias : summaryAliases) {
        List<Decimal> values = grandTotalValues.containsKey(colKey) &&
          grandTotalValues.get(colKey).containsKey(alias)
          ? grandTotalValues.get(colKey).get(alias)
          : new List<Decimal>();

        SDTConfiguratorDTO.MatrixCell cell = new SDTConfiguratorDTO.MatrixCell();
        cell.rowKey = 'Grand Total';
        cell.colKey = colKey;
        cell.alias = alias;
        cell.value = aggregateMatrixGrandTotalValues(
          values,
          summaryAliasToFunction.get(alias)
        );
        cells.add(cell);
      }
    }
    return cells;
  }

  private Decimal aggregateMatrixGrandTotalValues(
    List<Decimal> values,
    String aggregateFunction
  ) {
    if (values == null || values.isEmpty()) {
      return null;
    }

    String func = String.isNotBlank(aggregateFunction)
      ? aggregateFunction.toUpperCase().trim()
      : 'SUM';
    if (func == 'MIN') {
      Decimal minVal = values[0];
      for (Decimal val : values) {
        if (val < minVal) minVal = val;
      }
      return minVal;
    }
    if (func == 'MAX') {
      Decimal maxVal = values[0];
      for (Decimal val : values) {
        if (val > maxVal) maxVal = val;
      }
      return maxVal;
    }
    if (func == 'AVG') {
      Decimal total = 0;
      for (Decimal val : values) {
        total += val;
      }
      return total / values.size();
    }

    Decimal sum = 0;
    for (Decimal val : values) {
      sum += val;
    }
    return sum;
  }

  // [CPU FIX] Lightweight method G�� returns expression count based on granularity
  // without performing heavy Schema.getGlobalDescribe / validateFieldPath calls
  private Integer getGroupExpressionCount(SDTConfiguratorDTO.MatrixGroupField gf) {
    if (String.isBlank(gf.granularity)) {
      return 1;
    }
    String gran = gf.granularity.toUpperCase().trim();
    // CALENDAR_MONTH and CALENDAR_QUARTER produce 2 expressions (Year + Month/Quarter)
    if (gran == 'CALENDAR_MONTH' || gran == 'CALENDAR_QUARTER') {
      return 2;
    }
    return 1;
  }

  // [CPU FIX] Fast version that uses pre-computed expression count instead of
  // calling buildGroupExpressions (which triggers validateFieldPath) per row
  private String formatGroupValueFast(
    AggregateResult ar,
    Integer groupIndex,
    SDTConfiguratorDTO.MatrixGroupField gf,
    Integer expressionCount
  ) {
    if (expressionCount == 1) {
      return formatGroupValue(ar.get(buildGroupAlias(groupIndex, 0, 1)), gf);
    }

    Object first = ar.get(buildGroupAlias(groupIndex, 0, expressionCount));
    Object second = ar.get(buildGroupAlias(groupIndex, 1, expressionCount));
    if (first == null || second == null) {
      return '(blank)';
    }

    String gran = gf.granularity != null ? gf.granularity.toUpperCase() : '';
    if (gran == 'CALENDAR_MONTH') {
      Integer yearValue = Integer.valueOf(String.valueOf(first));
      Integer monthValue = Integer.valueOf(String.valueOf(second));
      return formatMonthYear(monthValue, yearValue);
    }
    if (gran == 'CALENDAR_QUARTER') {
      return 'Q' + String.valueOf(second) + ' ' + String.valueOf(first);
    }

    return String.valueOf(first) + ' ' + String.valueOf(second);
  }

  // Original formatGroupValue G�� retained for backward compatibility in query building
  private String formatGroupValue(
    AggregateResult ar,
    Integer groupIndex,
    SDTConfiguratorDTO.MatrixGroupField gf
  ) {
    List<String> expressions = buildGroupExpressions(gf);
    if (expressions.size() == 1) {
      return formatGroupValue(ar.get(buildGroupAlias(groupIndex, 0, 1)), gf);
    }

    Object first = ar.get(buildGroupAlias(groupIndex, 0, expressions.size()));
    Object second = ar.get(buildGroupAlias(groupIndex, 1, expressions.size()));
    if (first == null || second == null) {
      return '(blank)';
    }

    String gran = gf.granularity != null ? gf.granularity.toUpperCase() : '';
    if (gran == 'CALENDAR_MONTH') {
      Integer yearValue = Integer.valueOf(String.valueOf(first));
      Integer monthValue = Integer.valueOf(String.valueOf(second));
      return formatMonthYear(monthValue, yearValue);
    }
    if (gran == 'CALENDAR_QUARTER') {
      return 'Q' + String.valueOf(second) + ' ' + String.valueOf(first);
    }

    return String.valueOf(first) + ' ' + String.valueOf(second);
  }

  private String formatGroupValue(
    Object val,
    SDTConfiguratorDTO.MatrixGroupField gf
  ) {
    if (val == null)
      return '(blank)';

    if (String.isBlank(gf.granularity)) {
      return String.valueOf(val);
    }

    String gran = gf.granularity.toUpperCase();

    if (gran == 'CALENDAR_MONTH') {
      Integer m = Integer.valueOf(String.valueOf(val));
      return formatMonthYear(m, null);
    }
    if (gran == 'CALENDAR_QUARTER')
      return 'Q' + String.valueOf(val);
    if (gran == 'FISCAL_QUARTER')
      return 'FQ' + String.valueOf(val);
    if (gran == 'DAY_IN_WEEK') {
      Integer d = Integer.valueOf(String.valueOf(val));
      String[] days = new List<String>{
        'Sun',
        'Mon',
        'Tue',
        'Wed',
        'Thu',
        'Fri',
        'Sat'
      };
      return (d >= 1 && d <= 7) ? days[d - 1] : String.valueOf(val);
    }

    return String.valueOf(val);
  }

  private String formatMonthYear(Integer monthValue, Integer yearValue) {
    String[] months = new List<String>{
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    };
    String monthLabel = (monthValue >= 1 && monthValue <= 12)
      ? months[monthValue - 1]
      : String.valueOf(monthValue);
    return yearValue == null
      ? monthLabel
      : monthLabel + ' ' + String.valueOf(yearValue);
  }

  private List<String> extractLabels(
    List<SDTConfiguratorDTO.MatrixGroupField> fields
  ) {
    List<String> labels = new List<String>();
    if (fields == null)
      return labels;
    for (SDTConfiguratorDTO.MatrixGroupField gf : fields) {
      labels.add(String.isNotBlank(gf.label) ? gf.label : gf.fieldApiName);
    }
    return labels;
  }

  public class MatrixColumnWrapper implements Comparable {
    public List<Object> rawExpressionValues;
    public List<String> formattedColParts;
    public List<SDTConfiguratorDTO.MatrixGroupField> colGroupFields;

    public MatrixColumnWrapper(
      List<Object> rawValues,
      List<String> formattedParts,
      List<SDTConfiguratorDTO.MatrixGroupField> colGroupFields
    ) {
      this.rawExpressionValues = rawValues;
      this.formattedColParts = formattedParts;
      this.colGroupFields = colGroupFields;
    }

    public Integer compareTo(Object compareTo) {
      MatrixColumnWrapper other = (MatrixColumnWrapper) compareTo;
      for (Integer i = 0; i < this.rawExpressionValues.size(); i++) {
        if (i >= other.rawExpressionValues.size()) {
          return 1;
        }
        Object v1 = this.rawExpressionValues[i];
        Object v2 = other.rawExpressionValues[i];

        if (v1 == v2) {
          continue;
        }
        if (v1 == null) return 1; // nulls last
        if (v2 == null) return -1;

        if (v1 instanceof Integer && v2 instanceof Integer) {
          Integer res = (Integer)v1 - (Integer)v2;
          if (res != 0) return res < 0 ? -1 : 1;
        }
        if (v1 instanceof Decimal && v2 instanceof Decimal) {
          if ((Decimal)v1 != (Decimal)v2) {
            return (Decimal)v1 < (Decimal)v2 ? -1 : 1;
          }
        }
        if (v1 instanceof Date && v2 instanceof Date) {
          if ((Date)v1 != (Date)v2) {
            return (Date)v1 < (Date)v2 ? -1 : 1;
          }
        }
        if (v1 instanceof DateTime && v2 instanceof DateTime) {
          if ((DateTime)v1 != (DateTime)v2) {
            return (DateTime)v1 < (DateTime)v2 ? -1 : 1;
          }
        }
        Integer strComp = String.valueOf(v1).compareTo(String.valueOf(v2));
        if (strComp != 0) {
          return strComp;
        }
      }
      return 0;
    }
  }

  public class MatrixQueryException extends Exception {
  }
}
