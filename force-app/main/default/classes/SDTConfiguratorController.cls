public with sharing class SDTConfiguratorController {

@AuraEnabled(cacheable=true)
  public static List<Shree_Tech__Table__c> getAllTables() {
    try {
      return SDTConfiguratorSelector.getAllTables();
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (SDTConfiguratorService.DynamicTableException dex) {
      throw new AuraHandledException(dex.getMessage());
    } catch (Exception ex) {
      

      throw new AuraHandledException(
        'An unexpected error occurred. Please contact your administrator. Error Reference: ' +
        ex.getMessage()
      );
    }
  }

@AuraEnabled
  public static Map<String, Object> getTableMetadata(Id tableId) {
    try {
      Shree_Tech__Table__c table = SDTConfiguratorSelector.getTableById(tableId);
      List<Shree_Tech__Table_Columns__c> columns = SDTConfiguratorSelector.getColumnsByTableId(
        tableId
      );
      List<Shree_Tech__Table_Action__c> actions = SDTConfiguratorSelector.getActionsByTableId(
        tableId
      );
      return new Map<String, Object>{
        'table' => table,
        'columns' => columns,
        'actions' => actions
      };
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (SDTConfiguratorService.DynamicTableException dex) {
      throw new AuraHandledException(dex.getMessage());
    } catch (Exception ex) {
      

      throw new AuraHandledException(
        'An unexpected error occurred. Please contact your administrator. Error Reference: ' +
        ex.getMessage()
      );
    }
  }

@AuraEnabled(cacheable=true)
  public static List<Map<String, String>> getObjectFields(
    String objectApiName
  ) {
    try {
      List<Map<String, String>> fieldOptions = new List<Map<String, String>>();
      SObjectType sObjType = SDTConfiguratorService.getSObjectType(objectApiName);
      if (sObjType != null) {
        if (!sObjType.getDescribe().isAccessible())
          throw new AuraHandledException('Object is not accessible.');
        Map<String, Schema.SObjectField> fieldMap = SDTConfiguratorService.getFieldMap(
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
    } catch (SDTConfiguratorService.DynamicTableException dex) {
      throw new AuraHandledException(dex.getMessage());
    } catch (Exception ex) {
      

      throw new AuraHandledException(
        'An unexpected error occurred. Please contact your administrator. Error Reference: ' +
        ex.getMessage()
      );
    }
  }

@AuraEnabled
  public static void saveMetadata(
    Shree_Tech__Table__c table,
    List<Shree_Tech__Table_Columns__c> columns,
    List<Shree_Tech__Table_Action__c> actions,
    List<String> deletedIds,
    List<String> deletedActionIds
  ) {
    try {
      SDTConfiguratorService.saveMetadata(
        table,
        columns,
        actions,
        deletedIds,
        deletedActionIds
      );
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (SDTConfiguratorService.DynamicTableException dex) {
      throw new AuraHandledException(dex.getMessage());
    } catch (Exception ex) {
      

      throw new AuraHandledException(
        'An unexpected error occurred. Please contact your administrator. Error Reference: ' +
        ex.getMessage()
      );
    }
  }

@AuraEnabled
  public static void deleteTableConfig(Id tableId) {
    try {
      Shree_Tech__Table__c tbl = [
        SELECT Id
        FROM Shree_Tech__Table__c
        WHERE Id = :tableId
        WITH USER_MODE
        LIMIT 1
      ];
      delete as user tbl;
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (SDTConfiguratorService.DynamicTableException dex) {
      throw new AuraHandledException(dex.getMessage());
    } catch (Exception ex) {
      

      throw new AuraHandledException(
        'An unexpected error occurred. Please contact your administrator. Error Reference: ' +
        ex.getMessage()
      );
    }
  }

@AuraEnabled
  public static void cloneTableConfig(Id tableId) {
    try {
      SDTConfiguratorService.cloneTableConfig(tableId);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (SDTConfiguratorService.DynamicTableException dex) {
      throw new AuraHandledException(dex.getMessage());
    } catch (Exception ex) {
      

      throw new AuraHandledException(
        'An unexpected error occurred. Please contact your administrator. Error Reference: ' +
        ex.getMessage()
      );
    }
  }

@AuraEnabled
  public static void saveFeatureOverride(
    Shree_Tech__Table_Feature_Override__c featureOverride
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
  public static List<Shree_Tech__Table_Feature_Override__c> getFeatureOverrides(
    Id tableId
  ) {
    try {
      return [
        SELECT
          Id,
          Shree_Tech__Context_Type__c,
          Shree_Tech__Context_Value__c,
          Shree_Tech__Override_Enable_Export__c,
          Shree_Tech__Override_Enable_Import__c,
          Shree_Tech__Override_Enable_Filters__c,
          Shree_Tech__Override_New_Record__c,
          Shree_Tech__Override_Hide_Row_Actions__c,
          Shree_Tech__Override_Enable_Matrix_View__c,
          Shree_Tech__Override_Enable_Column_Manager__c,
          Shree_Tech__Override_Enable_Views__c
        FROM Shree_Tech__Table_Feature_Override__c
        WHERE Shree_Tech__Table__c = :tableId
        WITH USER_MODE
      ];
    } catch (Exception e) {
      AuraHandledException ahe = new AuraHandledException(e.getMessage());
      ahe.setMessage(e.getMessage());
      throw ahe;
    }
  }

@AuraEnabled
  public static void deleteFeatureOverride(Id overrideId) {
    try {
      delete as user [
        SELECT Id
        FROM Shree_Tech__Table_Feature_Override__c
        WHERE Id = :overrideId
        WITH USER_MODE
      ];
    } catch (Exception e) {
      throw new AuraHandledException(
        'An internal server error occurred. Please contact support.'
      );
    }
  }

@AuraEnabled
  public static SDTConfiguratorDTO.ImportMetadata getImportMetadata(
    String tableName
  ) {
    try {
      System.debug(
        LoggingLevel.FINE,
        '[Controller] getImportMetadata → tableName'
      );
      return SDTConfiguratorService.getImportMetadata(tableName);
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (SDTConfiguratorService.DynamicTableException dex) {
      throw new AuraHandledException(dex.getMessage());
    } catch (Exception ex) {
      

      throw new AuraHandledException(
        'An unexpected error occurred. Please contact your administrator. Error Reference: ' +
        ex.getMessage()
      );
    }
  }

@AuraEnabled(cacheable=true)
  public static List<Map<String, String>> getPicklistOptions(
    String objectApiName,
    String fieldApiName
  ) {
    try {
      return SDTConfiguratorService.resolvePicklistValues(
        objectApiName,
        fieldApiName
      );
    } catch (Exception ex) {
      throw new AuraHandledException(
        'An internal server error occurred. Please contact support.'
      );
    }
  }

@AuraEnabled
  public static List<SDTConfiguratorDTO.LookupSearchResult> searchLookupRecords(
    String objectApiName,
    String searchTerm,
    String nameField
  ) {
    try {
      System.debug(
        LoggingLevel.FINE,
        '[Controller] searchLookupRecords → object'
      );
      return SDTConfiguratorService.searchLookupRecords(
        objectApiName,
        searchTerm,
        nameField
      );
    } catch (AuraHandledException ahe) {
      throw ahe;
    } catch (SDTConfiguratorService.DynamicTableException dex) {
      throw new AuraHandledException(dex.getMessage());
    } catch (Exception ex) {
      

      throw new AuraHandledException(
        'An unexpected error occurred. Please contact your administrator. Error Reference: ' +
        ex.getMessage()
      );
    }
  }

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

}
