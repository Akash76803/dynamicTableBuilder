import { LightningElement, track, wire } from "lwc";
import { getObjectInfo } from "lightning/uiObjectInfoApi";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { refreshApex } from "@salesforce/apex";
import getAllTables from "@salesforce/apex/SDTConfiguratorController.getAllTables";
import getTableMetadata from "@salesforce/apex/SDTConfiguratorController.getTableMetadata";
import getObjectFields from "@salesforce/apex/SDTConfiguratorController.getObjectFields";
import saveMetadata from "@salesforce/apex/SDTConfiguratorController.saveMetadata";
import deleteTableConfig from "@salesforce/apex/SDTConfiguratorController.deleteTableConfig";
import cloneTableConfig from "@salesforce/apex/SDTConfiguratorController.cloneTableConfig";
import saveFeatureOverride from "@salesforce/apex/SDTConfiguratorController.saveFeatureOverride";
import getFeatureOverrides from "@salesforce/apex/SDTConfiguratorController.getFeatureOverrides";
import deleteFeatureOverride from "@salesforce/apex/SDTConfiguratorController.deleteFeatureOverride";
import getImportMetadata from "@salesforce/apex/SDTConfiguratorController.getImportMetadata";
import getPicklistOptions from "@salesforce/apex/SDTConfiguratorController.getPicklistOptions";
import searchLookupRecords from "@salesforce/apex/SDTConfiguratorController.searchLookupRecords";
import getRecordNames from "@salesforce/apex/SDTConfiguratorController.getRecordNames";

const READ_ONLY_SYSTEM_FIELDS = [
  "id",
  "createddate",
  "lastmodifieddate",
  "systemmodstamp",
  "isdeleted",
  "lastvieweddate",
  "lastreferenceddate",
  "createdbyid",
  "lastmodifiedbyid"
];

const CHIP_BASE = "chip";
const CHIP_ON = "chip chip--on";
const CHIP_BLUE = "chip chip--on-blue";

const addNamespace = (obj) => {
  if (!obj) return obj;
  const newObj = { ...obj };
  Object.keys(obj).forEach((key) => {
    if (key.endsWith("__c") && !key.startsWith("")) {
      newObj[`${key}`] = obj[key];
      delete newObj[key];
    }
  });
  return newObj;
};

const stripNamespace = (obj) => {
  if (!obj) return obj;
  const newObj = { ...obj };
  Object.keys(obj).forEach((key) => {
    if (key.startsWith("")) {
      newObj[key.replace("", "")] = obj[key];
    }
  });
  return newObj;
};

export default class DynamicTableConfigurator extends LightningElement {
  @track tables = [];
  @track activeTable = {
    Name: "",
    Object_API_Name__c: "",
    Object_Name__c: "",
    Hide_Row_Actions__c: false,
    Empty_State_Illustration__c: "",
    Enable_Filters__c: true,
    Enable_Matrix_View__c: true,
    Enable_Column_Manager__c: true,
    Enable_Views__c: true,
    Enable_Import__c: true,
    Enable_Export__c: true,
    Enable_New_Record__c: true
  };
  @track localColumns = [];
  @track deletedIds = [];
  @track actions = [];
  @track deletedActionIds = [];
  @track objectFieldOptions = [];
  _columnSearch = "";

  @track featureOverrides = [];
  @track newOverride = {
    Context_Type__c: "Profile",
    Context_Value__c: "",
    Override_Enable_Export__c: "",
    Override_Enable_Filters__c: "",
    Override_Hide_Row_Actions__c: "",
    Override_Enable_Import__c: "",
    Override_New_Record__c: "",
    Override_Enable_Matrix_View__c: "",
    Override_Enable_Column_Manager__c: "",
    Override_Enable_Views__c: ""
  };

  isLoading = false;
  showEditor = false;
  _isDirty = false;
  wiredTablesResult;

  // ── Options ───────────────────────────────────────────────────────────────

  dataTypeOptions = [
    { label: "Text", value: "Text" },
    { label: "Number", value: "Number" },
    { label: "Currency", value: "Currency" },
    { label: "Percentage", value: "Percentage" },
    { label: "Date", value: "Date" },
    { label: "DateTime", value: "DateTime" },
    { label: "Boolean", value: "Boolean" },
    { label: "Picklist", value: "Picklist" },
    { label: "Lookup", value: "Lookup" },
    { label: "Phone", value: "Phone" },
    { label: "Email", value: "Email" },
    { label: "Url", value: "Url" },
    { label: "RichText", value: "RichText" },
    { label: "LongText", value: "LongText" }
  ];

  filterTypeOptions = [
    { label: "— None —", value: "" },
    { label: "Text", value: "Text" },
    { label: "Number", value: "Number" },
    { label: "Date", value: "Date" },
    { label: "Picklist", value: "Picklist" },
    { label: "Boolean", value: "Boolean" }
  ];

  actionTypeOptions = [
    { label: "Flow", value: "Flow" },
    { label: "Apex", value: "Apex" },
    { label: "Navigation", value: "Navigation" },
    { label: "LWC", value: "LWC" },
    { label: "VF Page", value: "VF Page" }
  ];

  illustrationOptions = [
    { label: "Desert – Empty List (default)", value: "desert:empty_list" },
    { label: "Lake View – Empty List", value: "lakeview:empty_list" },
    { label: "No Data – Beach", value: "no_data:beach" },
    { label: "No Data – Desert", value: "no_data:desert" },
    { label: "No Data – Mountain", value: "no_data:mountain" },
    { label: "Error – No Access", value: "error:no_access" },
    { label: "Error – Maintenance", value: "error:maintenance" },
    { label: "Open Road – No Events", value: "open_road:no_events" }
  ];

  aggregateOptions = [
    { label: "None", value: "None" },
    { label: "Sum", value: "Sum" },
    { label: "Average", value: "Average" },
    { label: "Count", value: "Count" },
    { label: "Max", value: "Max" },
    { label: "Min", value: "Min" }
  ];

  // ── Wire ──────────────────────────────────────────────────────────────────

  @wire(getAllTables)
  wiredTables(result) {
    this.wiredTablesResult = result;
    if (result.data) {
      this.tables = result.data.map(tbl => stripNamespace(tbl));
    } else if (result.error) {
      this.showToast("Error", "Failed to load tables", "error");
    }
  }

  @wire(getObjectInfo, { objectApiName: "$activeTable.Object_API_Name__c" })
  wiredObjectInfo({ error, data }) {
    if (data && data.fields) {
      const fields = data.fields;
      this.objectFieldOptions = Object.keys(fields)
        .sort()
        .map((key) => {
          const f = fields[key];
          return {
            label: `${f.label} (${f.apiName})`,
            value: f.apiName,
            dataType: f.dataType,
            relationshipName: f.relationshipName,
            fieldLabel: f.label,
            referenceToApiName:
              f.referenceToInfos && f.referenceToInfos.length > 0
                ? f.referenceToInfos[0].apiName
                : ""
          };
        });
      // Append an option to allow custom API names (via typing, if we were using datalist, but combobox we can just provide standard fields)
    } else if (error) {
      this.objectFieldOptions = [];
    }
  }

  // ── Computed ──────────────────────────────────────────────────────────────

  get columnCount() {
    return this.localColumns.length;
  }

  get actionCount() {
    return this.actions.length;
  }

  get isPlural() {
    return this.localColumns.length !== 1;
  }

  get filteredColumns() {
    const q = (this._columnSearch || "").toLowerCase();
    const length = this.localColumns.length;
    return this.localColumns
      .filter(
        (col) =>
          !q ||
          (col.Name || "").toLowerCase().includes(q) ||
          (col.Column_API_Name__c || "").toLowerCase().includes(q)
      )
      .map((col, idx) => {
        const isNum = col.Data_Type__c === "Number" || col.Data_Type__c === "Currency" || col.Data_Type__c === "Percentage";
        const isDate = col.Data_Type__c === "Date" || col.Data_Type__c === "DateTime";
        const isPicklist = col.Data_Type__c === "Picklist";
        const isBoolean = col.Data_Type__c === "Boolean";
        const isLookup = col.Data_Type__c === "Lookup";
        const isText = !isNum && !isDate && !isPicklist && !isBoolean && !isLookup;

        let operators = [];
        if (isNum) {
          operators = [
            { label: "Equals", value: "exact" },
            { label: "Less Than", value: "less_than" },
            { label: "Greater Than", value: "greater_than" },
            { label: "Between", value: "range" }
          ];
        } else if (isDate) {
          operators = [
            { label: "Equals", value: "exact" },
            { label: "Before", value: "before" },
            { label: "After", value: "after" },
            { label: "Between", value: "date_range" }
          ];
        } else if (isPicklist) {
          operators = [
            { label: "Equals", value: "exact" },
            { label: "Includes any", value: "multi_select" },
            { label: "Excludes all", value: "multi_select_not" }
          ];
        } else if (isBoolean) {
          operators = [
            { label: "Is True", value: "boolean_true" },
            { label: "Is False", value: "boolean_false" }
          ];
        } else if (isLookup) {
          operators = [
            { label: "Equals", value: "exact" },
            { label: "Not Equals", value: "not_equals" },
            { label: "Contains", value: "contains" },
            { label: "Does not contain", value: "not_contains" },
            { label: "Includes any", value: "multi_select" },
            { label: "Excludes all", value: "multi_select_not" }
          ];
        } else {
          operators = [
            { label: "Contains", value: "text" },
            { label: "Equals", value: "exact" },
            { label: "Not Equals", value: "not_equals" },
            { label: "Does not contain", value: "not_contains" },
            { label: "Starts With", value: "starts_with" }
          ];
        }

        const op = col._filterOperator || "";
        const isFilterOperatorEmpty = !op;
        const mappedOperators = (operators || []).map(o => ({
          ...o,
          isSelected: o.value === op
        }));
        const showBetween = (op === "range" || op === "date_range");
        const showMulti = (op === "multi_select" || op === "multi_select_not");
        const showSingle = op && !showBetween && !showMulti && op !== "boolean_true" && op !== "boolean_false";

        const inputHtmlType = isDate ? (col.Data_Type__c === "DateTime" ? "datetime-local" : "date") : (isNum ? "number" : "text");
        const minLabel = isDate ? "From" : "Min";
        const maxLabel = isDate ? "To" : "Max";

        let picklistOptionsWithSelected = [];
        if (isPicklist && col._picklistOptions) {
          const selectedSet = new Set(col._filterValues || []);
          picklistOptionsWithSelected = col._picklistOptions.map(opt => ({
            ...opt,
            isSelected: selectedSet.has(opt.value)
          }));
        }

        const showLookupDropdown = col.lookupResults && col.lookupResults.length > 0 && !!col.lookupSearchTerm;

        return {
          ...col,
          isFirst: idx === 0,
          isLast: idx === length - 1,
          chipVisible: col.Is_Visible__c ? CHIP_ON : CHIP_BASE,
          chipSortable: col.Is_Sortable__c ? CHIP_BLUE : CHIP_BASE,
          chipEditable: col.Is_Editable__c ? CHIP_BLUE : CHIP_BASE,
          chipGroupable: col.Is_Groupable__c ? CHIP_BLUE : CHIP_BASE,
          chipFilterable: col.Is_Filterable__c ? CHIP_BLUE : CHIP_BASE,
          chipSearchable: col.Is_Searchable__c ? CHIP_BLUE : CHIP_BASE,
          chipAdditional: col.Additional_Column__c ? CHIP_BLUE : CHIP_BASE,
          isNum,
          isDate,
          isPicklist,
          isBoolean,
          isLookup,
          isText,
          operators: mappedOperators,
          isFilterOperatorEmpty,
          showBetween,
          showMulti,
          showSingle,
          inputHtmlType,
          minLabel,
          maxLabel,
          picklistOptions: col._picklistOptions || [],
          picklistOptionsWithSelected,
          showLookupDropdown,
          _selectedPills: col._selectedPills || [],
          _selectedPill: col._selectedPill || null,
          lookupSearchTerm: col.lookupSearchTerm || "",
          lookupResults: col.lookupResults || []
        };
      });
  }

  get tablesWithMeta() {
    return this.tables.map((t) => {
      let colCount = 0;
      const childCols = t.Table_Columns__r || t.Dynamic_Table_Columns__r;
      if (childCols && childCols.length) {
        colCount = childCols.length;
      }
      return {
        ...t,
        colCount,
        formattedDate: t.CreatedDate
          ? new Date(t.CreatedDate).toLocaleDateString()
          : "—"
      };
    });
  }

  get hasTables() {
    return this.tables && this.tables.length > 0;
  }

  // ── Button Actions ────────────────────────────────────────────────────────

  handleNewTable() {
    this.activeTable = {
      Name: "",
      Object_API_Name__c: "",
      Object_Name__c: "",
      Hide_Row_Actions__c: false,
      Empty_State_Illustration__c: "",
      Enable_Filters__c: true,
      Enable_Matrix_View__c: true,
      Enable_Column_Manager__c: true,
      Enable_Views__c: true,
      Enable_Import__c: true,
      Enable_Export__c: true,
      Enable_New_Record__c: true
    };
    this.localColumns = [];
    this.deletedIds = [];
    this.actions = [];
    this.deletedActionIds = [];
    this.featureOverrides = [];
    this.newOverride = {
      Context_Type__c: "Profile",
      Context_Value__c: "",
      Override_Enable_Export__c: "",
      Override_Enable_Filters__c: "",
      Override_Hide_Row_Actions__c: "",
      Override_Enable_Import__c: "",
      Override_New_Record__c: "",
      Override_Enable_Matrix_View__c: "",
      Override_Enable_Column_Manager__c: "",
      Override_Enable_Views__c: ""
    };
    this._isDirty = false;
    this._columnSearch = "";
    this.showEditor = true;
  }

  async handleClone(event) {
    const tableId = event.target.dataset.id;
    this.isLoading = true;
    try {
      await cloneTableConfig({ tableId });
      this.showToast("Success", "Table config cloned successfully", "success");
      await refreshApex(this.wiredTablesResult);
    } catch (error) {
      this.showToast(
        "Error",
        error.body ? error.body.message : error.message,
        "error"
      );
    } finally {
      this.isLoading = false;
    }
  }
  async handleEdit(event) {
    const tableId = event.target.dataset.id;
    this.isLoading = true;
    try {
      const data = await getTableMetadata({ tableId });

      this.activeTable = stripNamespace(data.table);
      const lookupIds = [];
      const columnsProcessed = await Promise.all(
        data.columns.map(async (col) => {
          const stripped = stripNamespace(col);
          const isLookup = stripped.Data_Type__c === "Lookup";
          let _baseField = stripped.Column_API_Name__c || "";
          let _parentField = "";
          let parentFieldOptions = [];

          if (isLookup) {
            let rawLookup = stripped.Lookup_Field_API_Name__c || "";
            if (rawLookup && rawLookup.includes(".")) {
              const baseRel = rawLookup.split(".")[0];
              if (baseRel.endsWith("__r"))
                _baseField = baseRel.replace("__r", "__c");
              else _baseField = baseRel + "Id";
            } else {
              _baseField = rawLookup;
            }

            if (
              stripped.Column_API_Name__c &&
              stripped.Column_API_Name__c.includes(".")
            ) {
              const parts = stripped.Column_API_Name__c.split(".");
              const relName = parts[0];
              if (!_baseField) {
                if (relName.endsWith("__r"))
                  _baseField = relName.replace("__r", "__c");
                else _baseField = relName + "Id";
              }
              _parentField = parts[1];
            }
            if (stripped.Object_Reference__c) {
              try {
                parentFieldOptions = await getObjectFields({
                  objectApiName: stripped.Object_Reference__c
                });
              } catch (e) {
                
              }
            }
          }

          let useCustomPath = false;
          if (stripped.Column_API_Name__c) {
            const dots = stripped.Column_API_Name__c.split(".").length - 1;
            if (dots > 1 || (!isLookup && dots === 1)) {
              useCustomPath = true;
            }
          }

          const parsedDefaultFilter = this.parseDefaultFilterConfig(stripped);
          const {
            _filterOperator,
            _filterValue,
            _filterValueMin,
            _filterValueMax,
            _filterValues
          } = parsedDefaultFilter;

          let _picklistOptions = [];
          if (stripped.Data_Type__c === "Picklist") {
            let objectApiName = this.activeTable.Object_API_Name__c;
            let fieldApiName = stripped.Column_API_Name__c;
            if (fieldApiName) {
              if (fieldApiName.includes(".")) {
                const parts = fieldApiName.split(".");
                fieldApiName = parts[parts.length - 1];
                let currentObj = this.activeTable.Object_API_Name__c;
                for (let i = 0; i < parts.length - 1; i++) {
                  const relName = parts[i];
                  try {
                    const fields = await getObjectFields({ objectApiName: currentObj });
                    const relField = fields.find(f => 
                      f.relationshipName === relName || 
                      (f.relationshipName && f.relationshipName.toLowerCase() === relName.toLowerCase())
                    );
                    if (relField && relField.referenceTo) {
                      currentObj = relField.referenceTo;
                    } else {
                      break;
                    }
                  } catch (err) {
                    
                    break;
                  }
                }
                objectApiName = currentObj;
              }
              try {
                _picklistOptions = await getPicklistOptions({ objectApiName, fieldApiName }) || [];
              } catch (error) {
                
              }
            }
          }

          if (isLookup && _filterOperator) {
            if (_filterOperator === "multi_select" || _filterOperator === "multi_select_not") {
              if (_filterValues && _filterValues.length > 0) {
                _filterValues.forEach(idVal => {
                  if (idVal) lookupIds.push(idVal);
                });
              }
            } else if (_filterValue) {
              lookupIds.push(_filterValue);
            }
          }

          return {
            ...stripped,
            tempId: stripped.Id,
            isLookup: isLookup,
            _baseField: _baseField,
            _parentField: _parentField,
            parentFieldOptions: parentFieldOptions,
            useCustomPath: useCustomPath,
            _level0Field: _baseField || "",
            _level1Field: _parentField || "",
            _level2Field: "",
            _level3Field: "",
            level1Options: parentFieldOptions || [],
            level2Options: [],
            level3Options: [],
            _filterOperator,
            _filterValue,
            _filterValueMin,
            _filterValueMax,
            _filterValues,
            _picklistOptions,
            _selectedPills: [],
            _selectedPill: null,
            lookupSearchTerm: "",
            lookupResults: []
          };
        })
      );

      this.localColumns = columnsProcessed;

      if (lookupIds.length > 0) {
        try {
          const nameMap = await getRecordNames({ recordIds: lookupIds });
          this.localColumns = this.localColumns.map(col => {
            if (col.Data_Type__c === "Lookup" && col._filterOperator) {
              if (col._filterOperator === "multi_select" || col._filterOperator === "multi_select_not") {
                col._selectedPills = (col._filterValues || []).map(idVal => ({
                  value: idVal,
                  label: nameMap[idVal] || idVal
                }));
              } else if (col._filterValue) {
                col._selectedPill = {
                  value: col._filterValue,
                  label: nameMap[col._filterValue] || col._filterValue
                };
              }
            }
            return col;
          });
        } catch (err) {
          
        }
      }

      this.actions = (data.actions || []).map((act, idx) => ({
        ...stripNamespace(act),
        tempId: act.Id,
        isFirst: idx === 0,
        isLast: idx === (data.actions ? data.actions.length - 1 : 0)
      }));

      if (tableId) {
        try {
          this.featureOverrides = await getFeatureOverrides({
            tableId: tableId
          });
        } catch (e) {
          this.featureOverrides = [];
        }
      }

      this.deletedIds = [];
      this.deletedActionIds = [];
      this._isDirty = false;
      this._columnSearch = "";
      this.showEditor = true;
    } catch (error) {
      this.showToast("Error", "Failed to load metadata", "error");
    } finally {
      this.isLoading = false;
    }
  }

  handleBack() {
    if (
      this._isDirty &&
      !confirm("You have unsaved changes. Are you sure you want to go back?")
    ) {
      return;
    }
    this._isDirty = false;
    this.showEditor = false;
  }

  async handleDelete(event) {
    const tableId = event.target.dataset.id;
    if (
      !confirm(
        "Delete this Table Configuration and all its columns? This cannot be undone."
      )
    )
      return;

    this.isLoading = true;
    try {
      await deleteTableConfig({ tableId });
      this.showToast("Success", "Table configuration deleted.", "success");
      await refreshApex(this.wiredTablesResult);
    } catch (error) {
      this.showToast("Error", error.body?.message || "Delete failed", "error");
    } finally {
      this.isLoading = false;
    }
  }

  handleCopyName(event) {
    const name = event.target.dataset.name;
    navigator.clipboard
      .writeText(name)
      .then(() =>
        this.showToast("Copied!", `"${name}" copied to clipboard.`, "success")
      )
      .catch(() => this.showToast("Error", "Copy failed.", "error"));
  }

  async handleDownloadSample() {
    this.isLoading = true;
    try {
      if (!this.activeTable.Name) {
        this.showToast(
          "Warning",
          "Save the table configuration before downloading template.",
          "warning"
        );
        return;
      }

      // 1. Fetch import metadata for the active table
      const meta = await getImportMetadata({
        tableName: this.activeTable.Name
      });
      const allFields = meta.allFields || [];

      // Map of lowercase API names for quick verification of writeability
      const writableFieldsMap = new Map();
      allFields.forEach((f) => {
        writableFieldsMap.set(f.apiName.toLowerCase(), f);
      });

      // Set to keep track of already processed parent lookup relationships to prevent duplicates
      const processedRelationships = new Set();
      const headers = [];

      for (const col of this.localColumns) {
        if (col.Additional_Column__c || !col.Column_API_Name__c) {
          continue; // Skip additional columns and empty columns
        }

        const path = col.Column_API_Name__c;
        const pathLower = path.toLowerCase();

        // Check if it's a system read-only field
        if (READ_ONLY_SYSTEM_FIELDS.includes(pathLower)) {
          continue;
        }

        // Identify if it's a lookup field (either by configured Data Type, Lookup_Field_API_Name__c, or if Column_API_Name__c contains a dot)
        const isLookup =
          col.Data_Type__c === "Lookup" ||
          (col.Lookup_Field_API_Name__c &&
            col.Lookup_Field_API_Name__c !== "") ||
          path.includes(".");

        if (isLookup) {
          // Extract standard lookup API name (e.g. AccountId or Shree_Tech_Contact__c)
          let lookupFieldApi = "";
          const lookupPath = col.Lookup_Field_API_Name__c || "";
          const pathToParse = lookupPath || path;

          if (pathToParse.includes(".")) {
            const rel = pathToParse.split(".")[0];
            lookupFieldApi = rel.endsWith("__r")
              ? rel.replace("__r", "__c")
              : rel + "Id";
          } else {
            lookupFieldApi = pathToParse;
          }

          const lookupLower = lookupFieldApi.toLowerCase();

          // Ensure lookup is writable
          const metaField = writableFieldsMap.get(lookupLower);
          if (!metaField) {
            continue; // If the lookup field itself is not writable, skip
          }

          // Prevent same parent object multiple relationship columns in template
          if (processedRelationships.has(lookupLower)) {
            continue;
          }
          processedRelationships.add(lookupLower);

          // Resolve External ID of parent
          const extIdFields = metaField.externalIdFields || [];
          if (extIdFields.length > 0) {
            // Use the first External ID field. CSV header name will be RelationshipName.ExternalIdField
            const relName =
              metaField.relationshipName ||
              lookupFieldApi.replace("Id", "").replace("__c", "__r");
            headers.push(`${relName}.${extIdFields[0].value}`);
          } else {
            // Fallback to standard Lookup Field API name itself
            headers.push(metaField.apiName);
          }
        } else {
          // Direct field - verify writeability
          const metaField = writableFieldsMap.get(pathLower);
          if (metaField) {
            headers.push(metaField.apiName);
          }
        }
      }

      if (headers.length === 0) {
        this.showToast("Warning", "No importable fields found.", "warning");
        return;
      }

      const csvContent = headers.join(",") + "\n";
      const encodedUri =
        "data:text/csv;charset=utf-8," + encodeURIComponent(csvContent);
      const tableName =
        this.activeTable && this.activeTable.Name
          ? this.activeTable.Name
          : "Template";
      const safeName = tableName.replace(/[^a-zA-Z0-9_-]/g, "_");

      const link = document.createElement("a");
      link.href = encodedUri;
      link.download = `Sample_${safeName}_Import.csv`;
      link.style.visibility = "hidden";
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      this.showToast("Success", "Sample CSV downloaded.", "success");
    } catch (error) {
      
      this.showToast(
        "Error",
        "Failed to generate CSV: " + (error.message || error),
        "error"
      );
    } finally {
      this.isLoading = false;
    }
  }

  async handleSave() {
    if (!this.validateInputs()) return;
    this.isLoading = true;
    try {
      const columnsToSave = this.localColumns.map((col, index) => {
        let Filter_Type__c = "";
        let Default_Filter_Value__c = "";

        if (col.Is_Filterable__c && col._filterOperator) {
          const op = col._filterOperator;
          if (op === "range") {
            Filter_Type__c = "range";
            Default_Filter_Value__c = JSON.stringify({ min: col._filterValueMin, max: col._filterValueMax });
          } else if (op === "date_range") {
            Filter_Type__c = "date_range";
            Default_Filter_Value__c = JSON.stringify({ from: col._filterValueMin, to: col._filterValueMax });
          } else if (op === "multi_select" || op === "multi_select_not") {
            Filter_Type__c = "multi_select";
            const operatorCode = op === "multi_select_not" ? "NOT_IN" : "IN";
            let vals = [];
            if (col.Data_Type__c === "Picklist") {
              vals = col._filterValues || [];
            } else if (col.Data_Type__c === "Lookup") {
              vals = (col._selectedPills || []).map(p => p.value);
            } else {
              vals = (col._filterValue || "").split(",").map(s => s.trim()).filter(Boolean);
            }
            Default_Filter_Value__c = JSON.stringify({ operator: operatorCode, values: vals });
          } else if (op === "boolean_true") {
            Filter_Type__c = "boolean";
            Default_Filter_Value__c = "true";
          } else if (op === "boolean_false") {
            Filter_Type__c = "boolean";
            Default_Filter_Value__c = "false";
          } else if (op === "not_equals") {
            Filter_Type__c = "exact";
            const val = col.Data_Type__c === "Lookup" ? (col._selectedPill?.value || "") : col._filterValue;
            Default_Filter_Value__c = JSON.stringify({ operator: "NOT_EQUALS", value: val });
          } else if (op === "contains") {
            Filter_Type__c = "exact";
            const val = col.Data_Type__c === "Lookup" ? (col._selectedPill?.value || "") : col._filterValue;
            Default_Filter_Value__c = JSON.stringify({ operator: "CONTAINS", value: val });
          } else if (op === "not_contains") {
            Filter_Type__c = "exact";
            const val = col.Data_Type__c === "Lookup" ? (col._selectedPill?.value || "") : col._filterValue;
            Default_Filter_Value__c = JSON.stringify({ operator: "NOT_CONTAINS", value: val });
          } else if (op === "less_than") {
            Filter_Type__c = "exact";
            const val = col.Data_Type__c === "Lookup" ? (col._selectedPill?.value || "") : col._filterValue;
            Default_Filter_Value__c = JSON.stringify({ operator: "LESS_THAN", value: val });
          } else if (op === "greater_than") {
            Filter_Type__c = "exact";
            const val = col.Data_Type__c === "Lookup" ? (col._selectedPill?.value || "") : col._filterValue;
            Default_Filter_Value__c = JSON.stringify({ operator: "GREATER_THAN", value: val });
          } else if (op === "before") {
            Filter_Type__c = "exact";
            const val = col.Data_Type__c === "Lookup" ? (col._selectedPill?.value || "") : col._filterValue;
            Default_Filter_Value__c = JSON.stringify({ operator: "BEFORE", value: val });
          } else if (op === "after") {
            Filter_Type__c = "exact";
            const val = col.Data_Type__c === "Lookup" ? (col._selectedPill?.value || "") : col._filterValue;
            Default_Filter_Value__c = JSON.stringify({ operator: "AFTER", value: val });
          } else {
            Filter_Type__c = op;
            Default_Filter_Value__c = col.Data_Type__c === "Lookup" ? (col._selectedPill?.value || "") : (col._filterValue || "");
          }
        }

        const {
          tempId,
          isLookup,
          isFirst,
          isLast,
          chipVisible,
          chipSortable,
          chipEditable,
          chipGroupable,
          chipFilterable,
          chipSearchable,
          chipAdditional,
          _baseField,
          _parentField,
          parentFieldOptions,
          _filterOperator,
          _filterValue,
          _filterValueMin,
          _filterValueMax,
          _filterValues,
          _picklistOptions,
          _selectedPill,
          _selectedPills,
          lookupSearchTerm,
          lookupResults,
          ...rest
        } = col;
        return addNamespace({ 
          ...rest, 
          Index__c: index,
          Filter_Type__c,
          Default_Filter_Value__c,
          sobjectType: 'Table_Columns__c'
        });
      });

      const actionsToSave = this.actions.map((act, index) => {
        const { tempId, isFirst, isLast, ...rest } = act;
        return addNamespace({ 
          ...rest, 
          Display_Order__c: index + 1,
          sobjectType: 'Table_Action__c'
        });
      });

      await saveMetadata({
        table: addNamespace({
          ...this.activeTable,
          sobjectType: 'Table__c'
        }),
        columns: columnsToSave,
        actions: actionsToSave,
        deletedIds: this.deletedIds,
        deletedActionIds: this.deletedActionIds
      });
      this._isDirty = false;
      this.showToast("Success", "Configuration saved successfully!", "success");
      await refreshApex(this.wiredTablesResult);
      this.showEditor = false;
    } catch (error) {
      this.showToast("Error", error.body?.message || "Save failed", "error");
    } finally {
      this.isLoading = false;
    }
  }

  // ── Field Change Handlers ─────────────────────────────────────────────────

  handleTableFieldChange(event) {
    const field = event.target.dataset.field;
    const val =
      event.target.type === "checkbox" || event.target.type === "toggle"
        ? event.target.checked
        : event.target.value;
    this.activeTable = { ...this.activeTable, [field]: val };
    this._isDirty = true;
  }

  handleToggleCustomPath(event) {
    const index = parseInt(event.target.dataset.index, 10);
    const cols = [...this.localColumns];
    cols[index].useCustomPath = !cols[index].useCustomPath;

    // If switching back to dropdown, try to reset Column_API_Name__c to match the dropdown state
    if (!cols[index].useCustomPath) {
      if (cols[index].isLookup && cols[index]._parentField) {
        cols[index].Column_API_Name__c = cols[index]._parentField;
      } else if (cols[index]._baseField) {
        cols[index].Column_API_Name__c = cols[index]._baseField;
      }
    }

    this.localColumns = cols;
    this._isDirty = true;
  }

  async handleLevelChange(event) {
    const index = parseInt(event.target.dataset.index, 10);
    const level = parseInt(event.target.dataset.level, 10);
    const val = event.detail ? event.detail.value : event.target.value;

    const cols = [...this.localColumns];
    const colObj = this.filteredColumns[index];
    const localIndex = cols.findIndex((c) => c.tempId === colObj.tempId);
    if (localIndex === -1) return;
    const col = cols[localIndex];

    col[`_level${level}Field`] = val;

    // Clear subsequent levels
    for (let i = level + 1; i <= 3; i++) {
      col[`_level${i}Field`] = "";
      col[`level${i}Options`] = [];
    }

    let options =
      level === 0 ? this.objectFieldOptions : col[`level${level}Options`];
    const selectedOpt = options.find((o) => o.value === val);

    if (selectedOpt) {
      col[`_level${level}Rel`] = selectedOpt.relationshipName || "";
      col[`_level${level}Ref`] =
        selectedOpt.referenceToApiName || selectedOpt.referenceTo || "";
      col[`_level${level}Lookup`] =
        selectedOpt.dataType &&
        (selectedOpt.dataType.toUpperCase() === "REFERENCE" ||
          selectedOpt.dataType.toUpperCase() === "ID");

      if (
        col[`_level${level}Lookup`] &&
        col[`_level${level}Ref`] &&
        level < 3
      ) {
        try {
          const nextOpts = await getObjectFields({
            objectApiName: col[`_level${level}Ref`]
          });
          col[`level${level + 1}Options`] = nextOpts.map((f) => ({
            ...f,
            referenceToApiName: f.referenceTo || f.referenceToApiName
          }));
        } catch (e) {
          
        }
      }

      // Build API path
      let apiPath = "";
      let lookupPath = "";
      let targetObj = "";

      for (let i = 0; i <= level; i++) {
        let f = col[`_level${i}Field`];
        let rel = col[`_level${i}Rel`];
        let ref = col[`_level${i}Ref`];
        let isL = col[`_level${i}Lookup`];

        if (f && typeof rel === "undefined") {
          let opts =
            i === 0 ? this.objectFieldOptions : col[`level${i}Options`];
          if (opts) {
            let opt = opts.find((o) => o.value === f);
            if (opt) {
              rel = opt.relationshipName || "";
              ref = opt.referenceToApiName || opt.referenceTo || "";
              isL =
                opt.dataType &&
                (opt.dataType.toUpperCase() === "REFERENCE" ||
                  opt.dataType.toUpperCase() === "ID");
              col[`_level${i}Rel`] = rel;
              col[`_level${i}Ref`] = ref;
              col[`_level${i}Lookup`] = isL;
            }
          }
        }

        // Fallback to empty string if still undefined
        rel = rel || "";
        ref = ref || "";

        if (i < level) {
          apiPath += (apiPath ? "." : "") + (rel || f);
          lookupPath += (lookupPath ? "." : "") + (rel || f);
        } else {
          apiPath += (apiPath ? "." : "") + f;
          if (ref) targetObj = ref;
          lookupPath += (lookupPath ? "." : "") + f;
        }
      }

      col.Column_API_Name__c = apiPath;
      if (targetObj) col.Object_Reference__c = targetObj;

      // Auto populate lookup ID field path if Data Type is Lookup
      if (col[`_level${level}Lookup`]) {
        col.Lookup_Field_API_Name__c = lookupPath;
      } else if (level > 0) {
        col.Lookup_Field_API_Name__c =
          lookupPath.substring(0, lookupPath.lastIndexOf(".")) + ".Id";
      }

      // Clear filter config on path change
      col._filterOperator = "";
      col._filterValue = "";
      col._filterValueMin = "";
      col._filterValueMax = "";
      col._filterValues = [];

      if (col.Data_Type__c === "Picklist") {
        this.fetchPicklistOptions(col).then(() => {
          this.localColumns = [...cols];
        });
      }
    }

    this.localColumns = cols;
    this._isDirty = true;
  }

  handleColumnFieldChange(event) {
    const index = parseInt(event.target.dataset.index, 10);
    const field = event.target.dataset.field;
    const val =
      event.target.type === "checkbox" || event.target.type === "toggle"
        ? event.target.checked
        : event.detail && typeof event.detail.value !== "undefined"
          ? event.detail.value
          : event.target.value;

    const cols = [...this.localColumns];
    const colObj = this.filteredColumns[index];
    const localIndex = cols.findIndex((c) => c.tempId === colObj.tempId);
    if (localIndex === -1) return;

    cols[localIndex] = { ...cols[localIndex], [field]: val };
    const col = cols[localIndex];

    if (field === "_filterOperator") {
      col._filterValue = "";
      col._filterValueMin = "";
      col._filterValueMax = "";
      col._filterValues = [];
    }

    if (field === "Data_Type__c" || field === "_baseField" || field === "_parentField" || field === "Column_API_Name__c") {
      col._filterOperator = "";
      col._filterValue = "";
      col._filterValueMin = "";
      col._filterValueMax = "";
      col._filterValues = [];
      if (col.Data_Type__c === "Picklist") {
        this.fetchPicklistOptions(col).then(() => {
          this.localColumns = [...cols];
        });
      }
    }

    if (field === "_baseField") {
      const selectedOpt = this.objectFieldOptions.find(
        (opt) => opt.value === val
      );
      if (selectedOpt) {
        if (!cols[localIndex].Name) {
          cols[localIndex].Name = selectedOpt.fieldLabel;
        }

        let dt = "Text";
        const sDataType = selectedOpt.dataType;
        if (sDataType === "Boolean") dt = "Boolean";
        else if (sDataType === "Currency") dt = "Currency";
        else if (sDataType === "Date") dt = "Date";
        else if (sDataType === "DateTime") dt = "DateTime";
        else if (sDataType === "Double" || sDataType === "Int") dt = "Number";
        else if (sDataType === "Email") dt = "Email";
        else if (sDataType === "Phone") dt = "Phone";
        else if (sDataType === "Url") dt = "Url";
        else if (sDataType === "Picklist" || sDataType === "MultiPicklist")
          dt = "Picklist";
        else if (sDataType === "Reference") dt = "Lookup";

        cols[localIndex].Data_Type__c = dt;
        cols[localIndex].isLookup = dt === "Lookup";

        if (cols[localIndex].isLookup && selectedOpt.relationshipName) {
          cols[localIndex].Lookup_Field_API_Name__c = val;
          cols[localIndex].Object_Reference__c = selectedOpt.referenceToApiName;

          if (selectedOpt.referenceToApiName) {
            getObjectFields({ objectApiName: selectedOpt.referenceToApiName })
              .then((options) => {
                const newCols = [...this.localColumns];
                newCols[localIndex].parentFieldOptions = options;
                const hasName = options.find((o) => o.value === "Name");
                newCols[localIndex]._parentField = hasName
                  ? "Name"
                  : options.length > 0
                    ? options[0].value
                    : "";
                newCols[localIndex].Column_API_Name__c = newCols[localIndex]._parentField;
                this.localColumns = newCols;
              })
              .catch((err) => {});
          }
        } else {
          cols[localIndex].Column_API_Name__c = val;
        }

        if (dt === "Picklist") {
          this.fetchPicklistOptions(cols[localIndex]).then(() => {
            this.localColumns = [...cols];
          });
        }
      }
    }

    if (field === "_parentField") {
      const baseOpt = this.objectFieldOptions.find(
        (opt) => opt.value === cols[localIndex]._baseField
      );
      if (baseOpt && baseOpt.relationshipName) {
        cols[localIndex].Column_API_Name__c = val;
      }
    }

    if (field === "Data_Type__c") {
      cols[localIndex].isLookup = val === "Lookup";
    }
    this.localColumns = cols;
    this._isDirty = true;
  }

  // Chip click toggles the boolean directly (no toggle input needed)
  handleChipToggle(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10);
    const field = event.currentTarget.dataset.field;
    const cols = [...this.localColumns];
    const colObj = this.filteredColumns[index];
    const localIndex = cols.findIndex((c) => c.tempId === colObj.tempId);
    if (localIndex === -1) return;

    cols[localIndex] = { ...cols[localIndex], [field]: !cols[localIndex][field] };
    
    if (field === "Is_Filterable__c" && cols[localIndex].Is_Filterable__c && cols[localIndex].Data_Type__c === "Picklist" && (!cols[localIndex]._picklistOptions || cols[localIndex]._picklistOptions.length === 0)) {
      this.fetchPicklistOptions(cols[localIndex]).then(() => {
        this.localColumns = [...cols];
      });
    } else {
      this.localColumns = cols;
    }
    this._isDirty = true;
  }

  handlePicklistFilterCheck(event) {
    const index = parseInt(event.target.dataset.index, 10);
    const val = event.target.dataset.value;
    const checked = event.target.checked;
    
    const cols = [...this.localColumns];
    const colObj = this.filteredColumns[index];
    const localIndex = cols.findIndex((c) => c.tempId === colObj.tempId);
    if (localIndex === -1) return;
    const col = cols[localIndex];

    if (!col._filterValues) {
      col._filterValues = [];
    }
    
    if (checked) {
      if (!col._filterValues.includes(val)) {
        col._filterValues.push(val);
      }
    } else {
      col._filterValues = col._filterValues.filter(v => v !== val);
    }
    
    this.localColumns = cols;
    this._isDirty = true;
  }

  debounceSearch;

  handleLookupSearchChange(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10);
    const term = event.detail.value;

    const cols = [...this.localColumns];
    const colObj = this.filteredColumns[index];
    const localIndex = cols.findIndex((c) => c.tempId === colObj.tempId);
    if (localIndex === -1) return;
    const col = cols[localIndex];

    col.lookupSearchTerm = term;

    if (!term || term.length < 2) {
      col.lookupResults = [];
      this.localColumns = cols;
      return;
    }

    this.localColumns = cols;

    const objectApiName = col.Object_Reference__c || "Account";
    const nameField = "Name";

    clearTimeout(this.debounceSearch);
    this.debounceSearch = setTimeout(async () => {
      try {
        const results = await searchLookupRecords({
          objectApiName,
          searchTerm: term,
          nameField
        });
        const currentCols = [...this.localColumns];
        const matchCol = currentCols.find(c => c.tempId === col.tempId);
        if (matchCol) {
          matchCol.lookupResults = results || [];
          this.localColumns = currentCols;
        }
      } catch (error) {
        
      }
    }, 300);
  }

  handleSelectLookupResult(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10);
    const selectedValue = event.currentTarget.dataset.value;
    const selectedLabel = event.currentTarget.dataset.label;

    const cols = [...this.localColumns];
    const colObj = this.filteredColumns[index];
    const localIndex = cols.findIndex((c) => c.tempId === colObj.tempId);
    if (localIndex === -1) return;
    const col = cols[localIndex];

    const op = col._filterOperator;
    const isMulti = op === "multi_select" || op === "multi_select_not";

    if (isMulti) {
      if (!col._selectedPills) {
        col._selectedPills = [];
      }
      if (!col._selectedPills.some((p) => p.value === selectedValue)) {
        col._selectedPills.push({ value: selectedValue, label: selectedLabel });
      }
      col._filterValues = col._selectedPills.map(p => p.value);
    } else {
      col._selectedPill = { value: selectedValue, label: selectedLabel };
      col._filterValue = selectedValue;
    }

    col.lookupSearchTerm = "";
    col.lookupResults = [];
    this.localColumns = cols;
    this._isDirty = true;
  }

  handleRemoveLookupPill(event) {
    const index = parseInt(event.currentTarget.dataset.index, 10);
    const pillValue = event.currentTarget.dataset.value;

    const cols = [...this.localColumns];
    const colObj = this.filteredColumns[index];
    const localIndex = cols.findIndex((c) => c.tempId === colObj.tempId);
    if (localIndex === -1) return;
    const col = cols[localIndex];

    const op = col._filterOperator;
    const isMulti = op === "multi_select" || op === "multi_select_not";

    if (isMulti) {
      col._selectedPills = (col._selectedPills || []).filter(
        (p) => p.value !== pillValue
      );
      col._filterValues = col._selectedPills.map(p => p.value);
    } else {
      col._selectedPill = null;
      col._filterValue = "";
    }

    this.localColumns = cols;
    this._isDirty = true;
  }

  parseDefaultFilterConfig(col) {
    const result = {
      _filterOperator: "",
      _filterValue: "",
      _filterValueMin: "",
      _filterValueMax: "",
      _filterValues: []
    };

    if (!col?.Is_Filterable__c) {
      return result;
    }

    const rawValue = col.Default_Filter_Value__c || "";
    let filterType = (col.Filter_Type__c || "").toLowerCase();
    const parsed = this.safeParseDefaultFilter(rawValue);

    if (this.isLegacyFilterType(filterType)) {
      filterType = this.inferFilterTypeFromDefaultValue(col, parsed, rawValue, filterType);
    } else if (!filterType && rawValue) {
      filterType = this.inferFilterTypeFromDefaultValue(col, parsed, rawValue, filterType);
    }

    if (!filterType) {
      return result;
    }

    if (filterType === "range" || filterType === "date_range") {
      result._filterOperator = filterType;
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        if (filterType === "range") {
          result._filterValueMin = parsed.min !== undefined ? parsed.min : "";
          result._filterValueMax = parsed.max !== undefined ? parsed.max : "";
        } else {
          result._filterValueMin = parsed.from !== undefined ? parsed.from : "";
          result._filterValueMax = parsed.to !== undefined ? parsed.to : "";
        }
      }
      return result;
    }

    if (filterType === "multi_select") {
      result._filterOperator = "multi_select";
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        result._filterOperator = parsed.operator === "NOT_IN" ? "multi_select_not" : "multi_select";
        result._filterValues = Array.isArray(parsed.values) ? parsed.values : [];
      } else if (Array.isArray(parsed)) {
        result._filterValues = parsed;
      } else if (rawValue) {
        result._filterValues = [rawValue];
      }
      if (col.Data_Type__c !== "Picklist" && col.Data_Type__c !== "Lookup") {
        result._filterValue = result._filterValues.join(", ");
      }
      return result;
    }

    if (filterType === "boolean") {
      result._filterOperator = rawValue === "false" ? "boolean_false" : "boolean_true";
      return result;
    }

    if (filterType === "exact") {
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        result._filterOperator = this.mapStoredOperatorToUi(parsed.operator || "EQUALS");
        result._filterValue = parsed.value !== undefined ? parsed.value : "";
      } else {
        result._filterOperator = "exact";
        result._filterValue = rawValue;
      }
      return result;
    }

    result._filterOperator = this.mapStoredOperatorToUi(filterType);
    result._filterValue = rawValue;
    return result;
  }

  safeParseDefaultFilter(rawValue) {
    if (!rawValue) {
      return null;
    }
    try {
      return JSON.parse(rawValue);
    } catch (e) {
      return null;
    }
  }

  inferFilterTypeFromDefaultValue(col, parsed, rawValue, originalFilterType) {
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      if (parsed.min !== undefined || parsed.max !== undefined) {
        return "range";
      }
      if (parsed.from !== undefined || parsed.to !== undefined) {
        return "date_range";
      }
      if (parsed.values !== undefined) {
        return "multi_select";
      }
      if (parsed.operator !== undefined) {
        return "exact";
      }
    }
    if (Array.isArray(parsed)) {
      return "multi_select";
    }
    if (col.Data_Type__c === "Boolean") {
      return "boolean";
    }
    return rawValue ? "exact" : (originalFilterType || "");
  }

  isLegacyFilterType(filterType) {
    return ["text", "number", "date", "picklist", "lookup"].includes(filterType);
  }

  mapStoredOperatorToUi(operator) {
    const op = (operator || "").toString().toUpperCase();
    const map = {
      EQUALS: "exact",
      EXACT: "exact",
      NOT_EQUALS: "not_equals",
      CONTAINS: "contains",
      NOT_CONTAINS: "not_contains",
      LESS_THAN: "less_than",
      GREATER_THAN: "greater_than",
      BEFORE: "before",
      AFTER: "after",
      IN: "multi_select",
      NOT_IN: "multi_select_not"
    };
    return map[op] || operator || "";
  }

  async fetchPicklistOptions(col) {
    if (col.Data_Type__c !== "Picklist" || !col.Column_API_Name__c) {
      col._picklistOptions = [];
      return;
    }
    
    let objectApiName = this.activeTable.Object_API_Name__c;
    let fieldApiName = col.Column_API_Name__c;

    if (fieldApiName.includes(".")) {
      const parts = fieldApiName.split(".");
      fieldApiName = parts[parts.length - 1];
      
      let currentObj = this.activeTable.Object_API_Name__c;
      for (let i = 0; i < parts.length - 1; i++) {
        const relName = parts[i];
        try {
          const fields = await getObjectFields({ objectApiName: currentObj });
          const relField = fields.find(f => 
            f.relationshipName === relName || 
            (f.relationshipName && f.relationshipName.toLowerCase() === relName.toLowerCase())
          );
          if (relField && relField.referenceTo) {
            currentObj = relField.referenceTo;
          } else {
            break;
          }
        } catch (err) {
          
          break;
        }
      }
      objectApiName = currentObj;
    }

    try {
      const options = await getPicklistOptions({ objectApiName, fieldApiName });
      col._picklistOptions = options || [];
    } catch (error) {
      
      col._picklistOptions = [];
    }
  }

  handleColumnSearch(event) {
    this._columnSearch = event.target.value || "";
  }

  // ── Column Management ─────────────────────────────────────────────────────

  handleAddColumn() {
    this.localColumns = [
      ...this.localColumns,
      {
        tempId: Date.now().toString(),
        Name: "",
        Column_API_Name__c: "",
        Data_Type__c: "Text",
        Is_Visible__c: true,
        Is_Editable__c: false,
        Is_Sortable__c: true,
        Is_Groupable__c: false,
        Is_Searchable__c: false,
        Is_Filterable__c: false,
        Additional_Column__c: false,
        Aggregate__c: "None",
        Lookup_Field_API_Name__c: "",
        Object_Reference__c: "",
        Filter_Type__c: "",
        Default_Filter_Value__c: "",
        useCustomPath: false,
        _level0Field: "",
        _level1Field: "",
        _level2Field: "",
        _level3Field: "",
        level1Options: [],
        level2Options: [],
        level3Options: [],
        _selectedPills: [],
        _selectedPill: null,
        lookupSearchTerm: "",
        lookupResults: []
      }
    ];
    this._isDirty = true;
  }

  handleRemoveColumn(event) {
    const index = parseInt(event.target.dataset.index, 10);
    const colId = this.localColumns[index].Id;
    if (colId) this.deletedIds.push(colId);
    const cols = [...this.localColumns];
    cols.splice(index, 1);
    this.localColumns = cols;
    this._isDirty = true;
  }

  moveUp(event) {
    const index = parseInt(event.target.dataset.index, 10);
    if (index > 0) this.swapColumns(index, index - 1);
  }

  moveDown(event) {
    const index = parseInt(event.target.dataset.index, 10);
    if (index < this.localColumns.length - 1)
      this.swapColumns(index, index + 1);
  }

  swapColumns(idxA, idxB) {
    const cols = [...this.localColumns];
    [cols[idxA], cols[idxB]] = [cols[idxB], cols[idxA]];
    this.localColumns = cols;
    this._isDirty = true;
  }

  // ── Action Management ─────────────────────────────────────────────────────

  handleAddAction() {
    this.actions = [
      ...this.actions,
      {
        tempId: Date.now().toString(),
        Label__c: "",
        Icon__c: "",
        Action_Type__c: "Flow",
        Target__c: "",
        Requires_Selection__c: true
      }
    ];
    this.recalculateActionFlags();
    this._isDirty = true;
  }

  handleRemoveAction(event) {
    const index = parseInt(event.target.dataset.index, 10);
    const actId = this.actions[index].Id;
    if (actId) this.deletedActionIds.push(actId);
    const acts = [...this.actions];
    acts.splice(index, 1);
    this.actions = acts;
    this.recalculateActionFlags();
    this._isDirty = true;
  }

  handleActionFieldChange(event) {
    const index = parseInt(event.target.dataset.index, 10);
    const field = event.target.dataset.field;
    const val =
      event.target.type === "checkbox" || event.target.type === "toggle"
        ? event.target.checked
        : event.target.value;

    const acts = [...this.actions];
    acts[index] = { ...acts[index], [field]: val };
    this.actions = acts;
    this._isDirty = true;
  }

  moveActionUp(event) {
    const index = parseInt(event.target.dataset.index, 10);
    if (index > 0) this.swapActions(index, index - 1);
  }

  moveActionDown(event) {
    const index = parseInt(event.target.dataset.index, 10);
    if (index < this.actions.length - 1) this.swapActions(index, index + 1);
  }

  swapActions(idxA, idxB) {
    const acts = [...this.actions];
    [acts[idxA], acts[idxB]] = [acts[idxB], acts[idxA]];
    this.actions = acts;
    this.recalculateActionFlags();
    this._isDirty = true;
  }

  recalculateActionFlags() {
    const length = this.actions.length;
    this.actions = this.actions.map((act, idx) => ({
      ...act,
      isFirst: idx === 0,
      isLast: idx === length - 1
    }));
  }

  handleOverrideChange(event) {
    const field = event.target.dataset.field;
    this.newOverride = { ...this.newOverride, [field]: event.target.value };
  }

  async handleAddOverride() {
    if (!this.newOverride.Context_Value__c) {
      this.showToast("Error", "Context Value (ID) is required", "error");
      return;
    }
    this.isLoading = true;
    try {
      const tfo = { 
        ...this.newOverride, 
        Table__c: this.activeTable.Id,
        sobjectType: 'Table_Feature_Override__c'
      };
      await saveFeatureOverride({ featureOverride: addNamespace(tfo) });
      this.showToast("Success", "Override saved successfully.", "success");

      // reset form
      this.newOverride = {
        Context_Type__c: "Profile",
        Context_Value__c: "",
        Override_Enable_Export__c: "",
        Override_Enable_Filters__c: "",
        Override_Hide_Row_Actions__c: "",
        Override_Enable_Import__c: "",
        Override_New_Record__c: "",
        Override_Enable_Matrix_View__c: "",
        Override_Enable_Column_Manager__c: "",
        Override_Enable_Views__c: ""
      };

      // refresh list
      if (this.activeTable.Id) {
        this.featureOverrides = await getFeatureOverrides({
          tableId: this.activeTable.Id
        });
      }
    } catch (e) {
      this.showToast("Error", e.body ? e.body.message : e.message, "error");
    } finally {
      this.isLoading = false;
    }
  }

  async handleDeleteOverride(event) {
    const ovId = event.target.dataset.id;
    this.isLoading = true;
    try {
      await deleteFeatureOverride({ overrideId: ovId });
      this.showToast("Success", "Override deleted.", "success");
      if (this.activeTable.Id) {
        this.featureOverrides = await getFeatureOverrides({
          tableId: this.activeTable.Id
        });
      }
    } catch (e) {
      this.showToast("Error", e.body ? e.body.message : e.message, "error");
    } finally {
      this.isLoading = false;
    }
  }

  // ── Utilities ─────────────────────────────────────────────────────────────

  validateInputs() {
    const allValid = [
      ...this.template.querySelectorAll("lightning-input"),
      ...this.template.querySelectorAll("lightning-combobox")
    ].reduce((valid, el) => {
      el.reportValidity();
      return valid && el.checkValidity();
    }, true);
    if (!allValid)
      this.showToast(
        "Validation Error",
        "Please fix errors in the form.",
        "warning"
      );
    return allValid;
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}