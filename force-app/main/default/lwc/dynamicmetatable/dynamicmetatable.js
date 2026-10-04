import { LightningElement, api, track, wire } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { FlowAttributeChangeEvent } from "lightning/flowSupport";
import getTableData from "@salesforce/apex/DynamicTableController.getTableData";
import getFilteredTableData from "@salesforce/apex/DynamicTableController.getFilteredTableData";
import saveTableData from "@salesforce/apex/DynamicTableController.saveTableData";
import executeTableAction from "@salesforce/apex/DynamicTableController.executeTableAction";
import exportTableViaEmail from "@salesforce/apex/DynamicTableController.exportTableViaEmail";
import getAsyncRecordCount from "@salesforce/apex/DynamicTableController.getAsyncRecordCount";
import exportAndSaveFile from "@salesforce/apex/DynamicTableController.exportAndSaveFile";
import exportMatrixJobCsv from "@salesforce/apex/DynamicTableController.exportMatrixJobCsv";
import requestMatrixData from "@salesforce/apex/DynamicTableController.requestMatrixData";
import getMatrixJobStatus from "@salesforce/apex/DynamicTableController.getMatrixJobStatus";
import getMatrixJobResult from "@salesforce/apex/DynamicTableController.getMatrixJobResult";
import getUserViews from "@salesforce/apex/DynamicTableController.getUserViews";
import { refreshApex } from "@salesforce/apex";
import { deleteRecord } from "lightning/uiRecordApi";
import { applyFilters } from "c/tableFilterEngine";
import MatrixVirtualScroll from "c/matrixVirtualScroll";

export default class DynamicMetaTable extends NavigationMixin(
  LightningElement
) {
  static MATRIX_MIN_LOADING_MS = 650;
  static MATRIX_BROWSER_EXPORT_MAX_BYTES = 4000000;

  @api tableName;
  @api recordId;
  _showCheckboxColumn = true;
  @api
  get showCheckboxColumn() {
    return this._showCheckboxColumn;
  }
  set showCheckboxColumn(value) {
    this._showCheckboxColumn = typeof value === 'string' ? value === 'true' : !!value;
  }
  @api isWidgetMode = false; // Set to true when used in a dashboard
  @api theme = ""; // 'healthcare', 'retail'
  @api useGqlMetadata = false; // Set to true to fetch config via GraphQL instead of Apex
  @api isFlowMode = false;
  @api hideFilterChips = false;
  @api hideGrandTotal = false;
  @api logoIcon = "standard:opportunity";
  @api logoUrl = "";

  @api
  get selectedRowIds() {
    return Array.from(this._selectedIds);
  }
  set selectedRowIds(value) {
    if (Array.isArray(value)) {
      this._selectedIds = new Set(value);
      this._buildRows();
    }
  }

  _manualRows;
  @api
  get manualRows() {
    return this._manualRows;
  }
  set manualRows(value) {
    this._manualRows = value;
    if (this.isWidgetMode) {
      this.isLoading = false;
      this._processData({ rows: value, columns: this._manualColumns });
    }
  }

  _manualColumns;
  @api
  get manualColumns() {
    return this._manualColumns;
  }
  set manualColumns(value) {
    this._manualColumns = value;
    if (this.isWidgetMode) {
      this.isLoading = false;
      this._processData({ rows: this._manualRows, columns: value });
    }
  }
  @api displayMode = "TABLE"; // 'TABLE', 'MATRIX', 'KPI', 'CHART'
  _externalMatrixConfig;
  @api
  get externalMatrixConfig() {
    return this._externalMatrixConfig;
  }
  set externalMatrixConfig(value) {
    this._externalMatrixConfig = value;
    if (value?.isMatrixMode) {
      this._localIsMatrixMode = true;
      this.markMatrixDraftDirty();
    }
  }
  @api filtersFeature = "Default";
  @api matrixViewFeature = "Default";
  @api columnManagerFeature = "Default";
  @api viewsFeature = "Default";
  @api importFeature = "Default";
  @api exportFeature = "Default";
  @api newRecordFeature = "Default";
  @api rowActionsFeature = "Default";

  @track columns = [];

  _wiredResult; // â† store the full wire result
  _baseColumns = [];
  _rawRows = [];
  _editMap = {};
  _lookupDisplayMap = {};
  _sortKey;
  _searchKey;
  _sortDir = "asc";
  _isSaving = false;
  _previousPageSize = 10; // Store for restoring after Matrix mode
  @track _localIsMatrixMode = false;
  @track _localRowGroupFields = []; // Array of keys (col0, col1, etc)
  @track _localColumnGroupFields = []; // Array of keys
  @track _localAggregateField = ""; // Key (backward compatibility fallback)
  @track _localSummaryFields = []; // Array of active summary fields
  @track _localAggregateType = "SUM"; // 'SUM' | 'AVERAGE' | 'MINIMUM' | 'MAXIMUM'
  @track matrixResult = null;
  @track matrixRows = []; // 2D structure for HTML template
  @track matrixColHeaders = []; // nested col header rows
  @track matrixLoading = false;
  @track matrixLoadingLabel = "Generating...";
  @track matrixRequestStatus = "";
  @track matrixJobId = "";
  @track matrixProgress = 0;
  @track matrixProcessingMessage = "";
  @track matrixError = null;
  @track matrixDraftDirty = false;
  @track _dateGranularityMap = {};
  @track _matrixLimitExceeded = false;
  @track _matrixLimitCount = "";
  _matrixPausedByUser = false;
  _matrixPollTimer = null;
  _activeMatrixConfigJson = "";
  _matrixPreviewRowLimit = 200;

  // Virtual Scroll State Variables
  @track vsRows = [];
  @track vsSpacerTopPx = 0;
  @track vsSpacerBotPx = 0;
  @track vsTotalHeight = 0;
  @track vsTotalCount = 0;

  _vsEngine = null;
  _scrollContainer = null;
  _scrollRAF = null;
  _rowHeightMeasured = false;

  get firstMatrixColHeaderRow() {
    return this.matrixColHeaders && this.matrixColHeaders.length > 0
      ? this.matrixColHeaders[0]
      : [];
  }

  // Pagination
  @track pageSize = 10;
  currentPage = 1;
  totalRecords = 0;
  totalPages = 0;
  allRows = [];
  displayRows = [];

  // Export state
  @track isExporting = false;

  // Selection state (persists across pages)
  _selectedIds = new Set();

  // Filter state
  @track _showFilterPanel = false;
  @track _showViewManager = false;
  @track _filterPayload = null; // { logic: 'AND'|'OR', filters: [] }
  _defaultFilterPayload = null;
  @track _picklistOptionsMap = {}; // { fieldName: [{label,value}] }
  _filteredCount = null;
  @track _showColumnManager = false;
  @track _showImporter = false;
  @track _displayTableName = "";
  @track _hideRowActions = false;
  @track _illustrationName = "desert:empty_list";
  @track _enableFilters = true;
  @track _enableMatrixView = true;
  @track _enableColumnManager = true;
  @track _enableViews = true;
  @track _enableImport = true;
  @track _enableExport = true;
  @track _enableNewRecord = true;
  @track isRefreshing = false;
  @track isLoading = false;
  @track _density = "comfy"; // 'comfy' | 'compact'
  @track _customActions = [];
  @track _showActionModal = false;
  @track _modalTitle = "";
  @track _modalFlowName = "";
  @track _modalFlowInputVariables = [];
  @track _modalMessage = "";
  @track _isModalLoading = false;

  // Virtual Browse State
  @track _dataLoadMode = "Standard";
  @track _enableInfiniteScroll = false;
  @track loadedVirtualCount = 0;

  get _isVirtualMode() {
    if (this._localIsMatrixMode) return false;
    return (
      this._dataLoadMode === "Virtual" ||
      (this._dataLoadMode === "Auto" && this._enableInfiniteScroll)
    );
  }

  // Export State
  @track exportInProgress = false;
  @track exportError = null;
  @track showExportDialog = false;
  @track exportView = "FORMATTED";
  @track exportFormat = "xls";
  @track exportEncoding = "UTF-8";

  get formattedExportViewClass() {
    return this.exportView === "FORMATTED"
      ? "export-view-card selected"
      : "export-view-card";
  }

  get detailsExportViewClass() {
    return this.exportView === "DETAILS"
      ? "export-view-card selected"
      : "export-view-card";
  }

  get isFormattedExportView() {
    return this.exportView === "FORMATTED";
  }

  get formattedExportCardTitle() {
    return this._isMatrixMode ? "Matrix Summary" : "Formatted Report";
  }

  get formattedExportCardCopy() {
    return this._isMatrixMode
      ? "Download the generated matrix summary as CSV. It uses the current completed matrix snapshot."
      : "Export the report, including the report header, groupings, and filter settings. Large datasets are automatically exported as structured CSV instead of Excel.";
  }

  get detailsExportCardCopy() {
    return this._isMatrixMode
      ? "Export the underlying detail rows with the current filters for downstream analysis."
      : "Export only the detail rows. Use this to do further calculations or for uploading to other systems.";
  }

  get exportPrimaryLabel() {
    if (this.exportInProgress) {
      return this._isMatrixMode && this.exportView === "FORMATTED"
        ? "Preparing Matrix..."
        : "Exporting...";
    }
    return this._isMatrixMode && this.exportView === "FORMATTED"
      ? "Download Matrix"
      : "Export";
  }

  get isHeaderExportDisabled() {
    return this.exportInProgress || (this._isMatrixMode && this._matrixLimitExceeded);
  }

  get exportButtonTitle() {
    if (this._isMatrixMode && this._matrixLimitExceeded) {
      return "Direct export is disabled for large datasets. Use the 'Email Full Matrix' button in the warning banner.";
    }
    return this._isMatrixMode
      ? "Export the current matrix summary or detail rows"
      : "Export table data to CSV";
  }

  get exportBusyLabel() {
    return this._isMatrixMode ? "Preparing..." : "Exporting...";
  }

  get exportToolbarLabel() {
    return this._isMatrixMode ? "Download Matrix" : "Export";
  }

  get currentAppliedViewId() {
    return this._currentAppliedView?.id || null;
  }

  get currentAppliedViewName() {
    return this._currentAppliedView?.name || "";
  }

  // 📌 LIFECYCLE 📌
  connectedCallback() {
    const saved = localStorage.getItem("dt_density");
    if (saved === "compact" || saved === "comfy") {
      this._density = saved;
    }
    if (
      this.displayMode === "MATRIX" ||
      this.externalMatrixConfig?.isMatrixMode
    ) {
      this._localIsMatrixMode = true;
    }
  }

  disconnectedCallback() {
    this.releaseMatrixScrollContainer();
    this.stopMatrixJobPolling();
  }

  renderedCallback() {
    if (!this._isMatrixMode) return;

    const container = this.template.querySelector(".matrix-scroll-container");
    if (!container) return;
    if (this._scrollContainer === container) return;

    this.releaseMatrixScrollContainer();

    this._scrollContainer = container;
    this._measureAndApplyDimensions(container);
  }

  releaseMatrixScrollContainer() {
    if (this._scrollRAF) {
      cancelAnimationFrame(this._scrollRAF);
      this._scrollRAF = null;
    }
    this._scrollContainer = null;
    this._boundScrollHandler = null;
  }

  _measureAndApplyDimensions(container) {
    const firstRow = container.querySelector("tbody tr.matrix-data-row");
    if (firstRow && !this._rowHeightMeasured) {
      const measuredHeight = firstRow.getBoundingClientRect().height;
      if (measuredHeight > 0) {
        MatrixVirtualScroll.setRowHeight(Math.round(measuredHeight));
        this._rowHeightMeasured = true;
      }
    }

    const containerHeight = container.getBoundingClientRect().height;
    if (containerHeight > 0) {
      MatrixVirtualScroll.setViewportHeight(containerHeight);
    }

    if (this._vsEngine) {
      this._vsEngine.onScroll(this._scrollContainer?.scrollTop ?? 0);
      this._applyWindowSlice();
    }
  }

  initVirtualScroll(allRows) {
    if (!this._vsEngine) {
      this._vsEngine = new MatrixVirtualScroll();
    }

    this._vsEngine.init(allRows);
    this._rowHeightMeasured = false;

    if (this._scrollContainer) {
      this._scrollContainer.scrollTop = 0;
    }

    this._applyWindowSlice();
  }

  _onScroll(event) {
    const scrollTop = event.target.scrollTop;

    if (this._scrollRAF) {
      cancelAnimationFrame(this._scrollRAF);
    }

    this._scrollRAF = requestAnimationFrame(() => {
      if (!this._vsEngine) return;

      const { changed } = this._vsEngine.onScroll(scrollTop);

      if (changed) {
        this._applyWindowSlice();
      }

      this._scrollRAF = null;
    });
  }

  _applyWindowSlice() {
    if (!this._vsEngine) return;

    const slice = this._vsEngine.getWindowSlice();

    this.vsRows = slice.rows;
    this.vsSpacerTopPx = slice.spacerTopPx;
    this.vsSpacerBotPx = slice.spacerBotPx;
    this.vsTotalHeight = slice.totalHeight;
    this.vsTotalCount = slice.totalRowCount;
  }

  handleGroupToggle(event) {
    const rowKey = event.currentTarget.dataset.rowKey;
    if (!rowKey || !this._vsEngine) return;

    this._vsEngine.toggleGroup(rowKey);
    this._applyWindowSlice();
  }

  isRowCollapsed(rowKey) {
    return this._vsEngine?.isCollapsed(rowKey) ?? false;
  }

  // ───── COMPUTED PARENT ID ─────
  // On Record Pages: recordId is populated by the framework → used as parentId filter
  // On App Pages: recordId is undefined → we pass null so the wire still fires
  get parentIdParam() {
    return this.recordId || null;
  }

  // ───── UI HELPERS ─────
  get tableWrapperClass() {
    let cls = `table-wrapper ${this._density}`;
    if (this.theme) cls += ` theme-${this.theme}`;
    return cls;
  }

  get densityLabel() {
    return this._density === "comfy" ? "Compact" : "Comfy";
  }

  get densityIcon() {
    return this._density === "comfy" ? "utility:contract" : "utility:expand";
  }

  get densityTooltip() {
    return this._density === "comfy"
      ? "Switch to Compact view"
      : "Switch to Comfy view";
  }

  get skeletonRows() {
    return [1, 2, 3, 4, 5, 6];
  }

  get isKPIMode() {
    return this.displayMode === "KPI";
  }

  get kpiValue() {
    if (!this._rawRows || this._rawRows.length === 0) return 0;
    const activeFields =
      this._localSummaryFields.length > 0
        ? this._localSummaryFields
        : this.columns.find((c) => c.isNumber || c.isCurrency)
          ? [this.columns.find((c) => c.isNumber || c.isCurrency).key]
          : [];
    const field = activeFields[0];
    if (!field) return this._rawRows.length; // Default to count

    const vals = this._rawRows.map((row) => {
      const cell = row.cells.find((c) => c.key === field);
      return cell ? cell.value : null;
    });

    const agg = this._calculateAggregate(vals, this._aggregateType, field);
    return this._formatValue(agg, field);
  }

  get kpiLabel() {
    const isNum = (c) =>
      c.isNumeric ||
      [
        "NUMBER",
        "CURRENCY",
        "PERCENT",
        "PERCENTAGE",
        "DOUBLE",
        "INTEGER",
        "LONG",
        "DECIMAL"
      ].includes(String(c.dataType).toUpperCase());
    const activeFields =
      this._localSummaryFields.length > 0
        ? this._localSummaryFields
        : this.columns.find(isNum)
          ? [this.columns.find(isNum).key]
          : [];
    const field = activeFields[0];
    const col = this.columns.find((c) => c.key === field);
    return col ? `Total ${col.label}` : "Total Records";
  }

  get _aggregateType() {
    if (this.externalMatrixConfig?.aggregateType) {
      return this.externalMatrixConfig.aggregateType;
    }
    return this._localAggregateType || "SUM";
  }

  get aggregateTypeOptions() {
    const activeType = this._aggregateType.toUpperCase();
    const types = [
      { label: "Sum", value: "SUM" },
      { label: "Average", value: "AVERAGE" },
      { label: "Minimum", value: "MINIMUM" },
      { label: "Maximum", value: "MAXIMUM" },
      { label: "Count", value: "COUNT" }
    ];
    return types.map((t) => ({
      ...t,
      className:
        t.value === activeType
          ? "matrix-pill matrix-pill--active"
          : "matrix-pill"
    }));
  }

  handleAggregateTypeToggle(event) {
    const type = event.currentTarget.dataset.type;
    this._localAggregateType = type;
    this._applySort();
  }

  _calculateAggregate(vals, type, valKey) {
    if (!vals || vals.length === 0) return 0;

    if (valKey === "_recordCount") {
      return vals.reduce((a, b) => a + (typeof b === "number" ? b : 1), 0);
    }

    if (valKey) {
      const actualValKey = valKey.includes("|")
        ? valKey.split("|").pop()
        : valKey;
      const colField = this.columns.find((c) => c.key === actualValKey);
      const isLookup =
        colField &&
        (colField.isLookup ||
          String(colField.dataType).toUpperCase() === "REFERENCE");
      if (isLookup) {
        const validStrs = vals.filter(
          (v) => v !== null && v !== undefined && v !== ""
        );
        return new Set(validStrs).size;
      }
    }

    const validVals = vals
      .map((v) => {
        if (typeof v === "number") return v;
        const parsed = parseFloat(String(v || "").replace(/[$,\s]/g, ""));
        return isNaN(parsed) ? null : parsed;
      })
      .filter((v) => v !== null);
    if (validVals.length === 0) return 0;
    switch (String(type).toUpperCase()) {
      case "SUM":
        return validVals.reduce((a, b) => a + b, 0);
      case "AVG":
      case "AVERAGE":
        return validVals.reduce((a, b) => a + b, 0) / validVals.length;
      case "MAX":
      case "MAXIMUM":
        return Math.max(...validVals);
      case "MIN":
      case "MINIMUM":
        return Math.min(...validVals);
      case "COUNT":
        return vals.length;
      case "COUNT_DISTINCT":
        return new Set(vals).size;
      default:
        return validVals.reduce((a, b) => a + b, 0);
    }
  }

  get _isMatrixMode() {
    return this._localIsMatrixMode;
  }

  get _rowGroupFields() {
    if (this.externalMatrixConfig?.rowGroups)
      return this.externalMatrixConfig.rowGroups;
    return this._localRowGroupFields || [];
  }

  get _columnGroupFields() {
    if (this.externalMatrixConfig?.columnGroups)
      return this.externalMatrixConfig.columnGroups;
    return this._localColumnGroupFields || [];
  }

  get _aggregateField() {
    if (this.externalMatrixConfig?.aggregateField)
      return this.externalMatrixConfig.aggregateField;
    return this._localSummaryFields.join(",");
  }

  handleDensityToggle() {
    this._density = this._density === "comfy" ? "compact" : "comfy";
    localStorage.setItem("dt_density", this._density);
  }

  // ───── WIRE ─────
  @wire(getTableData, { tableName: "$tableName", parentId: "$parentIdParam" })
  wiredData(result) {
    if (this.useGqlMetadata) return; // Skip if using GraphQL for metadata
    if (this.isWidgetMode && this.manualRows) return; // Skip if in widget mode with manual data
    this._wiredResult = result;
    const { data, error } = result;
    if (data) {
      this.isLoading = false;
      this._defaultFilterPayload = data.defaultFilterPayload || null;
      this._checkAndApplyDefaultView();
      this._baseColumns = (data.columns || []).map((col) => ({ ...col }));
      const processedCols = this._applyColumnPrefs(data.columns || []);
      this.columns = processedCols.filter((c) => c.isVisible !== false || true);
      this._processData({ ...data, columns: processedCols });
    } else if (error) {
      this.isLoading = false;
      console.error("[DynamicMetaTable] Wire Error:", error);
      const message = error.body?.message || "Unknown error loading table";
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Error Loading Table",
          message: message,
          variant: "error",
          mode: "sticky"
        })
      );
    } else {
      // No data and no error yet — wire is pending
      this.isLoading = true;
    }
  }

  /**
   * Handles metadata loaded via GraphQL instead of Apex.
   */
  handleGqlConfigLoad(event) {
    const config = event.detail;
    console.log("[DynamicMetaTable] Config loaded via GraphQL:", config);

    this.isLoading = false;
    this._baseColumns = (config.columns || []).map((col) => ({ ...col }));
    const processedCols = this._applyColumnPrefs(config.columns || []);
    this.columns = processedCols;

    // Use standard data processor but with GraphQL provided metadata
    this._processData({
      ...config,
      columns: processedCols,
      rows: this.manualRows || [] // Rows still come from Apex/Widget data for now
    });
  }

  handleGqlError(event) {
    this.isLoading = false;
    this.error = event.detail;
    this.dispatchEvent(
      new ShowToastEvent({
        title: "Configuration Error",
        message: "Could not load metadata via GraphQL",
        variant: "error"
      })
    );
  }

  // ───── PROCESS ─────
  _resolveFeatureFlag(pageValue, tableValue, defaultValue = true) {
    if (pageValue === "Enabled") return true;
    if (pageValue === "Disabled") return false;
    return tableValue ?? defaultValue;
  }

  _processData(data) {
    if (!this._lookupDisplayMap) {
      this._lookupDisplayMap = {};
    }
    if (data.rows) {
      data.rows.forEach((row) => {
        row.cells.forEach((cell) => {
          if (cell.isLookup && cell.lookupId && cell.value) {
            this._lookupDisplayMap[cell.lookupId] = cell.value;
          }
        });
      });
    }

    let baseCols = data.columns || [];
    if (this._currentAppliedView && this._currentAppliedView.columnState) {
      baseCols = this._applyColumnState(
        baseCols,
        this._currentAppliedView.columnState
      );
    }
    this.columns =
      this.isWidgetMode && this.manualColumns ? this.manualColumns : baseCols;
    this.objectApiName = data.objectApiName;
    this.parentFilterField = data.parentFilterField || "";
    this._displayTableName = data.tableName || "";
    this._hideRowActions =
      this.isFlowMode
        ? true
        : (this.rowActionsFeature === "Hidden"
          ? true
          : this.rowActionsFeature === "Visible"
            ? false
            : data.hideRowActions || false);
    this._illustrationName = data.illustrationName || "desert:empty_list";
    this._enableFilters = this._resolveFeatureFlag(
      this.filtersFeature,
      data.enableFilters
    );
    this._enableMatrixView = this._resolveFeatureFlag(
      this.matrixViewFeature,
      data.enableMatrixView
    );
    this._enableColumnManager = this._resolveFeatureFlag(
      this.columnManagerFeature,
      data.enableColumnManager
    );
    this._enableViews = this._resolveFeatureFlag(
      this.viewsFeature,
      data.enableViews
    );
    this._enableImport = this._resolveFeatureFlag(
      this.importFeature,
      data.enableImport
    );
    this._enableExport = this._resolveFeatureFlag(
      this.exportFeature,
      data.enableExport
    );
    this._enableNewRecord = this._resolveFeatureFlag(
      this.newRecordFeature,
      data.enableNewRecord
    );
    this._dataLoadMode = data.dataLoadMode || "Standard";
    this._enableInfiniteScroll = data.enableInfiniteScroll || false;
    this._matrixPreviewRowLimit =
      data.matrixPreviewRowLimit && data.matrixPreviewRowLimit > 0
        ? data.matrixPreviewRowLimit
        : 200;
    this._customActions = data.actions || [];

    // Auto-build picklist options map from column metadata
    this._picklistOptionsMap = this.columns.reduce((map, col) => {
      if (col.isPicklist && Array.isArray(col.picklistOptions)) {
        [col.fieldName, col.soqlFieldPath, col.key, col.lookupField]
          .filter(Boolean)
          .forEach((key) => {
            map[key] = col.picklistOptions;
          });
      }
      return map;
    }, {});

    this._rawRows = (data.rows || []).map((row) => {
      const cells = row.cells.map((cell) => {
        if (cell.isLookup) {
          return { ...cell, value: cell.lookupId, label: cell.value };
        }
        return cell;
      });
      return { ...row, cells };
    });

    if (this.externalMatrixConfig?.aggregateField) {
      this._localSummaryFields = this.externalMatrixConfig.aggregateField
        .split(",")
        .map((s) => s.trim());
    } else if (
      this._localSummaryFields.length === 0 &&
      this.availableSummaryOptions.length > 0
    ) {
      this._localSummaryFields = [this.availableSummaryOptions[0].value];
    }

    if (
      this._currentAppliedView &&
      this._currentAppliedView.matrixConfig &&
      !this._matrixPausedByUser
    ) {
      const mc = this._currentAppliedView.matrixConfig;
      this._localIsMatrixMode = !!mc.isMatrixMode;
      this._localRowGroupFields = this.normalizeMatrixFieldKeys(
        mc.rowGroups || []
      );
      this._localColumnGroupFields = this.normalizeMatrixFieldKeys(
        mc.colGroups || mc.columnGroups || []
      );
      this._localSummaryFields = this.normalizeMatrixFieldKeys(
        mc.summaryFields || [],
        true
      );
      this._localAggregateType = mc.aggregateType || "SUM";
      this._dateGranularityMap = mc.dateGranularityMap || {};
    }

    this.currentPage = 1;
    this._applySort();
  }

  // â”€â”€â”€â”€â”€ SORT â”€â”€â”€â”€â”€
  handleSort(event) {
    const key = event.currentTarget.dataset.key;
    if (!key) return;

    if (this._sortKey === key) {
      this._sortDir = this._sortDir === "asc" ? "desc" : "asc";
    } else {
      this._sortKey = key;
      this._sortDir = "asc";
    }

    // Standard column metadata update
    this.columns = this.columns.map((col) => ({
      ...col,
      isSorted: col.key === this._sortKey,
      isSortedAsc: col.key === this._sortKey && this._sortDir === "asc"
    }));

    this._refreshColumnMeta();
    this._applySort();
  }

  _refreshColumnMeta() {
    this.columns = this.columns.map((col) => ({
      ...col,
      isSorted: col.key === this._sortKey,
      isSortedAsc: col.key === this._sortKey && this._sortDir === "asc",
      headerClass:
        col.key === this._sortKey ? "sortable is-sorted" : "sortable",
      ariaSort:
        col.key !== this._sortKey
          ? "none"
          : this._sortDir === "asc"
            ? "ascending"
            : "descending"
    }));
  }

  _applySort() {
    if (this._isVirtualMode) {
      const executeRefresh = () => {
        const viewport = this.template.querySelector("c-virtual-table-viewport");
        if (viewport) {
          const col = this.columns.find((c) => c.key === this._sortKey);
          const sortField = col ? col.soqlFieldPath : null;
          viewport.refresh(
            this._filterPayload,
            sortField,
            this._sortDir,
            this._searchKey
          );
        }
      };

      const viewport = this.template.querySelector("c-virtual-table-viewport");
      if (viewport) {
        executeRefresh();
      } else {
        setTimeout(() => {
          executeRefresh();
        }, 50);
      }
      this.updateVirtualRecordCount();
      return;
    }

    let data = [...this._rawRows];

    // 1. SEARCH
    if (this._searchKey) {
      const searchableCols = this.columns
        .filter((col) => col.isSearchable !== false)
        .map((col) => col.key);

      data = data.filter((row) =>
        row.cells.some((cell) => {
          if (!searchableCols.includes(cell.key)) return false;
          const val = cell.isLookup
            ? (cell.label || "").toLowerCase()
            : (cell.value || "").toString().toLowerCase();
          return val.includes(this._searchKey);
        })
      );
    }

    // 2. FILTER
    if (
      this._filterPayload &&
      this._filterPayload.filters &&
      this._filterPayload.filters.length
    ) {
      // Build a lookup: fieldName (e.g. "Name") -> column key (e.g. "col0")
      const fieldNameToKey = {};
      this.columns.forEach((col) => {
        if (col.fieldName && !fieldNameToKey[col.fieldName])
          fieldNameToKey[col.fieldName] = col.key;
      });

      const flatRecords = data.map((row) => {
        const flat = { _row: row };
        row.cells.forEach((cell) => {
          // Index by cell.key (col0, col1...)
          flat[cell.key] = cell.value;
        });
        return flat;
      });

      // Re-map filter fieldName to the corresponding cell key so applyFilters can resolve values
      const remappedFilters = this._filterPayload.filters.map((f) => ({
        ...f,
        soqlFieldPath: f.columnKey || fieldNameToKey[f.fieldName] || f.fieldName
      }));

      const filteredFlat = applyFilters(flatRecords, {
        logic: this._filterPayload.logic,
        filters: remappedFilters
      });

      data = filteredFlat.map((f) => f._row);
    }

    this._filteredCount = this.hasActiveFilters ? data.length : null;

    // 3. SORT
    if (this._sortKey) {
      data.sort((a, b) => {
        const valA = this._getCellValue(a, this._sortKey);
        const valB = this._getCellValue(b, this._sortKey);
        if (!valA && !valB) return 0;
        if (!valA) return this._sortDir === "asc" ? -1 : 1;
        if (!valB) return this._sortDir === "asc" ? 1 : -1;
        return this._sortDir === "asc"
          ? valA.localeCompare(valB, undefined, {
              numeric: true,
              sensitivity: "base"
            })
          : valB.localeCompare(valA, undefined, {
              numeric: true,
              sensitivity: "base"
            });
      });
    }

    // 4. MATRIX TRANSFORMATION (if active)
    if (
      this._isMatrixMode &&
      this._aggregateField &&
      (this._rowGroupFields.length > 0 || this._columnGroupFields.length > 0)
    ) {
      const matrix = this._transformToMatrix(data);
      this._matrixData = matrix;
      this._setPaginationData(matrix.rows, false);
    } else {
      this._matrixData = null;
      this._setPaginationData(data, false);
    }
  }

  // â”€â”€â”€â”€â”€ FILTER HANDLERS â”€â”€â”€â”€â”€
  handleFilterToggle() {
    this._showFilterPanel = !this._showFilterPanel;
  }

  handleFilterChange(evt) {
    this._filterPayload = evt.detail;
    if (evt.detail && evt.detail.lookupLabelsMap) {
      this._lookupDisplayMap = {
        ...this._lookupDisplayMap,
        ...evt.detail.lookupLabelsMap
      };
    }
    this.currentPage = 1;
    this._applySort();
    if (this._isMatrixMode) {
      this.markMatrixDraftDirty();
    } else if (!this._isVirtualMode) {
      this._loadFilteredFromServer(this._filterPayload);
    }
  }

  handleFilterCancel() {
    this._showFilterPanel = false;
  }

  handleFilterClose() {
    this._showFilterPanel = false;
  }

  handleClearFilters() {
    this._filterPayload = null;
    this._filteredCount = null;
    this.currentPage = 1;
    if (this._isMatrixMode) {
      this.markMatrixDraftDirty();
    } else if (!this._isVirtualMode) {
      refreshApex(this._wiredResult);
    }
    this._applySort();

    if (this._showFilterPanel) {
      this._showFilterPanel = false;
      setTimeout(() => {
        this._showFilterPanel = true;
      }, 0);
    }
  }

  handleRemoveChip(evt) {
    const idx = parseInt(evt.currentTarget.dataset.id.replace("chip_", ""), 10);
    if (!this._filterPayload?.filters) return;

    const updatedFilters = this._filterPayload.filters.filter((f, i) =>
      f.fieldName && f.operator ? i !== idx : true
    );

    this._filterPayload = { ...this._filterPayload, filters: updatedFilters };
    this._filteredCount = null;
    this.currentPage = 1;
    this._applySort();
    if (this._isMatrixMode) {
      this.markMatrixDraftDirty();
    } else if (!this._isVirtualMode) {
      this._loadFilteredFromServer(this._filterPayload);
    }
  }

  handleLookupQuery(evt) {
    const { rowId, query } = evt.detail;
    const filterChild = this.template.querySelector("c-table-filter");
    if (!filterChild) return;
    filterChild.setLookupResults(rowId, []);
  }

  // handleRefresh defined below (authoritative async version)

  _loadPicklistOptions() {
    // Replace with real data from Apex
  }

  // ── SAVED VIEWS WORKFLOW ──
  _defaultViewApplied = false;

  _checkAndApplyDefaultView() {
    if (this._defaultViewApplied || !this.tableName) return;
    this._defaultViewApplied = true;

    getUserViews({ tableName: this.tableName })
      .then((views) => {
        const defaultView = views.find((v) => v.isDefault);
        if (defaultView) {
          const viewData = {
            id: defaultView.id,
            name: defaultView.name,
            filterPayload: defaultView.filterPayloadJson
              ? JSON.parse(defaultView.filterPayloadJson)
              : null,
            columnState: defaultView.columnStateJson
              ? JSON.parse(defaultView.columnStateJson)
              : null,
            matrixConfig: defaultView.matrixConfigJson
              ? JSON.parse(defaultView.matrixConfigJson)
              : null,
            sortKey: defaultView.sortKey,
            sortDir: defaultView.sortDirection
          };
          this._currentAppliedView = viewData;
          this._applySavedView(viewData);
        } else {
          // No default saved view, so apply/show original table's default filters
          if (this._defaultFilterPayload) {
            this._filterPayload = JSON.parse(
              JSON.stringify(this._defaultFilterPayload)
            );
          }
        }
      })
      .catch((err) => {
        console.error("Error loading default view: ", err);
        if (this._defaultFilterPayload) {
          this._filterPayload = JSON.parse(
            JSON.stringify(this._defaultFilterPayload)
          );
        }
      });
  }

  _applySavedView(viewData) {
    if (!viewData) return;
    this._matrixPausedByUser = false;

    // Apply sort
    this._sortKey = viewData.sortKey || null;
    this._sortDir = viewData.sortDir || "asc";

    // Apply columns visibility & order
    if (viewData.columnState) {
      this.columns = this._applyColumnState(this.columns, viewData.columnState);
    }

    // Apply matrix config
    if (viewData.matrixConfig) {
      const mc = viewData.matrixConfig;
      this._localIsMatrixMode = !!mc.isMatrixMode;
      this._localRowGroupFields = this.normalizeMatrixFieldKeys(
        mc.rowGroups || []
      );
      this._localColumnGroupFields = this.normalizeMatrixFieldKeys(
        mc.colGroups || mc.columnGroups || []
      );
      this._localSummaryFields = this.normalizeMatrixFieldKeys(
        mc.summaryFields || [],
        true
      );
      this._localAggregateType = mc.aggregateType || "SUM";
      this._dateGranularityMap = mc.dateGranularityMap || {};
    } else {
      this._localIsMatrixMode = false;
    }

    // Apply filter payload
    this._filterPayload = viewData.filterPayload;
    this.currentPage = 1;
    this._applySort();

    if (this._isMatrixMode) {
      this.resetMatrixRenderState();
      this.markMatrixDraftDirty();
    } else if (this._isVirtualMode) {
      const executeRefresh = () => {
        const viewport = this.template.querySelector("c-virtual-table-viewport");
        if (viewport) {
          const col = this.columns.find((c) => c.key === this._sortKey);
          const sortField = col ? col.soqlFieldPath : null;
          viewport.refresh(
            this._filterPayload,
            sortField,
            this._sortDir,
            this._searchKey
          );
        }
      };

      const viewport = this.template.querySelector("c-virtual-table-viewport");
      if (viewport) {
        executeRefresh();
      } else {
        setTimeout(() => {
          executeRefresh();
        }, 50);
      }
      this.updateVirtualRecordCount();
    } else {
      this._loadFilteredFromServer(this._filterPayload);
    }
  }

  _applyColumnState(dataColumns, columnState) {
    if (!columnState || !columnState.order || !columnState.vis)
      return dataColumns;
    let result = [];
    columnState.order.forEach((key) => {
      const col = dataColumns.find((c) => c.key === key);
      if (col) result.push(col);
    });
    dataColumns.forEach((col) => {
      if (!result.find((c) => c.key === col.key)) result.push(col);
    });
    return result.map((col) => {
      const v = columnState.vis.find((x) => x.key === col.key);
      return { ...col, isVisible: v ? v.isVisible : col.isVisible !== false };
    });
  }

  normalizeMatrixFieldKeys(keys, allowRecordCount = false) {
    if (!Array.isArray(keys)) return [];
    const normalized = [];

    keys.forEach((key) => {
      if (!key) return;
      if (allowRecordCount && key === "_recordCount") {
        normalized.push(key);
        return;
      }

      const keyText = String(key).trim();
      const matchedColumn = this.columns.find((col) => {
        return [
          col.key,
          col.fieldName,
          col.soqlFieldPath,
          col.lookupField,
          col.label
        ]
          .filter(Boolean)
          .some((candidate) => String(candidate).trim() === keyText);
      });

      normalized.push(matchedColumn ? matchedColumn.key : keyText);
    });

    return [...new Set(normalized)];
  }

  handleOpenViewManager() {
    this._showViewManager = true;
  }

  handleCloseViewManager() {
    this._showViewManager = false;
  }

  handleApplyView(event) {
    const viewData = event.detail;
    this._currentAppliedView = viewData;
    this._applySavedView(viewData);
    this._showViewManager = false;
  }

  handleResetView() {
    this._currentAppliedView = null;
    this._matrixPausedByUser = false;
    this._filterPayload = this._defaultFilterPayload
      ? JSON.parse(JSON.stringify(this._defaultFilterPayload))
      : null;
    this._sortKey = null;
    this._sortDir = "asc";
    this._localIsMatrixMode = false;
    this._localRowGroupFields = [];
    this._localColumnGroupFields = [];
    this._localSummaryFields = [];
    this._localAggregateField = "";
    this._localAggregateType = "SUM";
    this._dateGranularityMap = {};
    this.matrixResult = null;
    this.matrixRows = [];
    this.matrixColHeaders = [];
    this.matrixError = null;
    this._matrixLimitExceeded = false;
    this._matrixLimitCount = "";
    this._matrixData = null; // Clear matrix data explicitly
    this.currentPage = 1;

    if (this._baseColumns && this._baseColumns.length) {
      this.columns = this._baseColumns.map((col) => ({
        ...col,
        isSorted: false,
        isSortedAsc: false
      }));
    }

    if (this._isVirtualMode) {
      const executeRefresh = () => {
        const viewport = this.template.querySelector("c-virtual-table-viewport");
        if (viewport) {
          viewport.refresh(this._filterPayload, null, "asc", this._searchKey);
        }
      };

      const viewport = this.template.querySelector("c-virtual-table-viewport");
      if (viewport) {
        executeRefresh();
      } else {
        setTimeout(() => {
          executeRefresh();
        }, 50);
      }
      this.updateVirtualRecordCount();
    } else {
      this.isLoading = true;
      refreshApex(this._wiredResult).finally(() => {
        this.isLoading = false;
      });
    }

    this.dispatchEvent(
      new ShowToastEvent({
        title: "Original table restored",
        message:
          "Saved view filters, sorting, columns, and matrix settings were cleared.",
        variant: "success"
      })
    );
  }

  handleViewSaved(event) {
    const savedView = event.detail;
    if (savedView?.id && this._currentAppliedView?.id === savedView.id) {
      this._currentAppliedView = {
        ...this._currentAppliedView,
        id: savedView.id,
        name: savedView.name
      };
    }

    const manager = this.template.querySelector("c-table-view-manager");
    if (manager) {
      manager.refreshViews();
    }
  }

  // ───── COLUMN MANAGER HANDLERS ─────
  handleOpenColumnManager() {
    this._showColumnManager = true;
  }

  handleCloseColumnManager() {
    this._showColumnManager = false;
  }

  // ── DATA IMPORT HANDLERS ────────────────────────────────────────────────

  handleOpenImport() {
    this._showImporter = true;
  }

  handleCloseImport() {
    this._showImporter = false;
  }

  handleImportSuccess() {
    if (this._isVirtualMode) {
      const viewport = this.template.querySelector("c-virtual-table-viewport");
      if (viewport) {
        const col = this.columns.find((c) => c.key === this._sortKey);
        const sortField = col ? col.soqlFieldPath : null;
        viewport.refresh(
          this._filterPayload,
          sortField,
          this._sortDir,
          this._searchKey
        );
      }
      this.updateVirtualRecordCount();
    } else {
      return refreshApex(this._wiredResult);
    }
  }

  handleColumnsApply(event) {
    const { columns } = event.detail;
    this.columns = [...columns];
    this._showColumnManager = false;

    // Persist to localStorage
    this._saveColumnPrefs();

    // Refresh view
    this._applySort();
  }

  _saveColumnPrefs() {
    try {
      const prefs = this.columns.map((c) => ({
        key: c.key,
        isVisible: c.isVisible
      }));
      localStorage.setItem(
        `dt_prefs_${this.tableName}`,
        JSON.stringify({
          order: this.columns.map((c) => c.key),
          vis: prefs
        })
      );
    } catch (e) {
      console.error("Prefs Save Error", e);
    }
  }

  _applyColumnPrefs(dataColumns) {
    try {
      const saved = localStorage.getItem(`dt_prefs_${this.tableName}`);
      if (!saved) return dataColumns;

      const { order, vis } = JSON.parse(saved);

      // 1. Reorder based on saved order
      let result = [];
      order.forEach((key) => {
        const col = dataColumns.find((c) => c.key === key);
        if (col) result.push(col);
      });

      // 2. Add any NEW columns that weren't in saved order
      dataColumns.forEach((col) => {
        if (!result.find((c) => c.key === col.key)) result.push(col);
      });

      // 3. Apply visibility
      result = result.map((col) => {
        const v = vis.find((x) => x.key === col.key);
        return { ...col, isVisible: v ? v.isVisible : col.isVisible !== false };
      });

      return result;
    } catch (e) {
      console.error("Prefs Apply Error", e);
      return dataColumns;
    }
  }

  _loadFilteredFromServer(filterPayload) {
    if (!filterPayload) {
      refreshApex(this._wiredResult);
      return;
    }

    const apexPayload = {
      logic: filterPayload.logic || "AND",
      filters: (filterPayload.filters || [])
        .filter((f) => f.fieldName && f.operator)
        .map((f) => ({
          fieldName: f.fieldName,
          soqlFieldPath: f.soqlFieldPath || f.fieldName,
          dataType: f.dataType || "Text",
          operator: f.operator,
          values: (f.values || []).map((v) => (v != null ? String(v) : ""))
        }))
    };

    const filtersJson = JSON.stringify(apexPayload);

    getFilteredTableData({
      tableName: this.tableName,
      parentId: this.recordId || null,
      filtersJson: filtersJson
    })
      .then((data) => {
        this._rawRows = (data.rows || []).map((row) => {
          const visibleKeys = this.columns.map((c) => c.key);
          const cells = row.cells
            .filter((cell) => visibleKeys.includes(cell.key))
            .map((cell) => {
              if (cell.isLookup) {
                return { ...cell, value: cell.lookupId, label: cell.value };
              }
              return cell;
            });
          return { ...row, cells };
        });

        // Server has already filtered the rows. Keep _filterPayload intact
        // so _applySort() applies client-side sort & pagination correctly.
        // Do NOT null-out the filter — that was causing all rows to show.
        this._filteredCount = this._rawRows.length;
        this._applySort();
      })
      .catch((error) => {
        console.error("[DynamicMetaTable] getFilteredTableData error:", error);
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Filter Warning",
            message:
              "Server-side filtering failed. Showing client-side results.",
            variant: "warning",
            mode: "dismissable"
          })
        );
      });
  }

  // â”€â”€â”€â”€â”€ PAGE SIZE HANDLER â”€â”€â”€â”€â”€
  handlePageSizeChange(event) {
    const newSize = parseInt(event.target.value, 10);
    if (newSize !== this.pageSize) {
      this.pageSize = newSize;
      this.currentPage = 1; // Reset to page 1 when changing size
      this._buildRows();

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Page Size Updated",
          message: `Now showing ${newSize} records per page`,
          variant: "info",
          mode: "pester"
        })
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  EXPORT — Native CSV (zero external dependencies)
  // ──────────────────────────────────────────────────────────────────────────

  async handleExport() {
    if (this.exportInProgress) return;
    this.exportError = null;

    if (this._isMatrixMode) {
      if (!this.matrixResult) {
        const message = "Generate the matrix first, then export it.";
        this.exportError = message;
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Matrix not ready",
            message,
            variant: "warning"
          })
        );
        return;
      }

      this.exportView = "FORMATTED";
      this.exportInProgress = true;
      try {
        await this._downloadCurrentMatrixExport();
      } catch (error) {
        const msg = this._formatExportErrorMessage(
          error?.body?.message ?? error?.message ?? "Unknown error"
        );
        this.exportError = msg;
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Export failed",
            message: msg,
            variant: "error",
            mode: "sticky"
          })
        );
      } finally {
        this.exportInProgress = false;
      }
      return;
    }

    this.showExportDialog = true;
  }

  handleExportViewSelect(event) {
    this.exportView = event.currentTarget.dataset.view;
  }

  handleExportFormatChange(event) {
    this.exportFormat = event.target.value;
  }

  handleExportEncodingChange(event) {
    this.exportEncoding = event.target.value;
  }

  handleCloseExportDialog() {
    this.showExportDialog = false;
  }

  _buildExportFilterConfigs() {
    return (this._filterPayload?.filters || [])
      .filter((f) => f.fieldName && f.operator)
      .map((f) => {
        const rawValues = Array.isArray(f.values)
          ? f.values
          : Array.isArray(f.value)
            ? f.value
            : f.value != null
              ? [f.value]
              : [];
        return {
          filterIndex: f.filterIndex,
          fieldApiName: f.soqlFieldPath || f.fieldName,
          operator: f.operator,
          fieldType: f.dataType,
          value: rawValues.length === 1 ? String(rawValues[0]) : null,
          values: rawValues.map((value) => String(value))
        };
      });
  }

  async _startExportViaEmail(matrixParamsJson) {
    return exportTableViaEmail({
      tableName: this.tableName,
      parentId: this.parentIdParam,
      filtersJson: this._filterPayload
        ? JSON.stringify(this._filterPayload)
        : "",
      matrixParamsJson: matrixParamsJson,
      searchTerm: this._searchKey ?? "",
      columnKeysJson: JSON.stringify(this.columns.map((col) => col.key))
    });
  }

  _downloadBase64File(fileName, contentType, base64Data) {
    if (!base64Data) {
      throw new Error("No export data was returned.");
    }

    const binary = atob(base64Data);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) {
      bytes[i] = binary.charCodeAt(i);
    }

    const blob = new Blob([bytes], {
      type: this._getSafeDownloadMimeType(contentType)
    });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = fileName || "Matrix_Export.csv";
    anchor.type = this._getSafeDownloadMimeType(contentType);
    document.body.appendChild(anchor);
    anchor.click();
    document.body.removeChild(anchor);
    setTimeout(() => URL.revokeObjectURL(url), 0);
  }

  _downloadTextFile(fileName, contentType, textData) {
    const blob = new Blob([textData], {
      type: this._getSafeDownloadMimeType(contentType)
    });
    if (blob.size > DynamicMetaTable.MATRIX_BROWSER_EXPORT_MAX_BYTES) {
      throw new Error(
        "Matrix export is too large for browser download. Reduce row/column groups or filters."
      );
    }

    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = fileName || "Matrix_Export.csv";
    anchor.type = this._getSafeDownloadMimeType(contentType);
    document.body.appendChild(anchor);
    anchor.click();
    document.body.removeChild(anchor);
    setTimeout(() => URL.revokeObjectURL(url), 0);
  }

  _getSafeDownloadMimeType(contentType) {
    const type = String(contentType || "").toLowerCase();
    if (
      type.includes("csv") ||
      type.includes("excel") ||
      type.includes("spreadsheet")
    ) {
      return "application/octet-stream";
    }
    return "application/octet-stream";
  }

  _escapeCsvCell(value) {
    if (value === null || value === undefined) return "";
    const text = String(value);
    return /[",\r\n]/.test(text) ? `"${text.replace(/"/g, '""')}"` : text;
  }

  _joinMatrixKeyParts(parts) {
    return Array.isArray(parts)
      ? parts.map((part) => this.normalizeMatrixKey(part)).join("|")
      : "";
  }

  _buildCurrentMatrixCsv() {
    const result = this.matrixResult;
    if (!result) {
      throw new Error(
        "Generate the matrix first, then export the formatted matrix summary."
      );
    }

    const rowLabels = result.rowFieldLabels || [];
    const colKeys =
      result.colKeys && result.colKeys.length > 0 ? result.colKeys : [[]];
    const summaryAliases = result.summaryAliases || [];
    const summaryLabels =
      result.summaryLabels && result.summaryLabels.length > 0
        ? result.summaryLabels
        : summaryAliases;

    const headers = [...rowLabels];
    colKeys.forEach((colParts) => {
      const colLabel = Array.isArray(colParts)
        ? colParts.filter(Boolean).join(" / ")
        : "";
      summaryLabels.forEach((summaryLabel) => {
        headers.push(colLabel ? `${colLabel} - ${summaryLabel}` : summaryLabel);
      });
    });

    const cellMap = {};
    (result.cells || []).forEach((cell) => {
      if (!cell) return;
      const rowKey = this.normalizeMatrixKey(cell.rowKey);
      const colKey = this.normalizeMatrixKey(cell.colKey);
      if (!cellMap[rowKey]) cellMap[rowKey] = {};
      if (!cellMap[rowKey][colKey]) cellMap[rowKey][colKey] = {};
      cellMap[rowKey][colKey][cell.alias] = cell.value;
    });

    const lines = [headers.map((cell) => this._escapeCsvCell(cell)).join(",")];
    (result.rowKeys || []).forEach((rowParts) => {
      const rowKey = this._joinMatrixKeyParts(rowParts);
      const line = Array.isArray(rowParts) ? [...rowParts] : [];
      while (line.length < rowLabels.length) line.push("");

      colKeys.forEach((colParts) => {
        const colKey = this._joinMatrixKeyParts(colParts);
        summaryAliases.forEach((alias) => {
          const value = cellMap[rowKey]?.[colKey]?.[alias];
          line.push(value === null || value === undefined ? "" : value);
        });
      });

      lines.push(line.map((cell) => this._escapeCsvCell(cell)).join(","));
    });

    return lines.join("\n");
  }

  _downloadCurrentMatrixResultExport() {
    const csv = this._buildCurrentMatrixCsv();
    const timestamp = new Date()
      .toISOString()
      .replace(/[-:]/g, "")
      .replace(/\.\d{3}Z$/, "Z");
    this._downloadTextFile(
      `Matrix_Export_${timestamp}.csv`,
      "text/csv;charset=utf-8",
      csv
    );

    this.dispatchEvent(
      new ShowToastEvent({
        title: "Export complete",
        message: `${(
          this.matrixResult?.totalMatrixRowCount || 0
        ).toLocaleString()} grouped matrix rows exported`,
        variant: "success"
      })
    );
  }

  async _downloadCurrentMatrixExport() {
    if (!this.matrixJobId) {
      this._downloadCurrentMatrixResultExport();
      return;
    }

    try {
      const result = await exportMatrixJobCsv({
        jobId: this.matrixJobId
      });
      if (!result?.success) {
        throw new Error(result?.errorMessage || "Matrix export failed.");
      }

      this._downloadBase64File(
        result.fileName,
        result.contentType,
        result.base64Data
      );

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Export complete",
          message: `${(result.totalRows || 0).toLocaleString()} grouped matrix rows exported`,
          variant: "success"
        })
      );
    } catch (error) {
      const message = error?.body?.message ?? error?.message ?? "";
      if (
        this.matrixResult &&
        !message.includes("too large for browser download")
      ) {
        this._downloadCurrentMatrixResultExport();
        return;
      }
      throw error;
    }
  }

  _formatExportErrorMessage(message) {
    if (!message) {
      return "Unknown error";
    }
    if (message.includes("ERR_BACKGROUND_EXPORT_REQUIRED:")) {
      return message.split("ERR_BACKGROUND_EXPORT_REQUIRED:").pop().trim();
    }
    if (message.includes("too large for browser download")) {
      return "This matrix export is too large for browser download. Reduce row/column groups or filters, generate the matrix again, then export.";
    }
    return message;
  }

  _isBackgroundExportRequired(message) {
    return (
      !!message &&
      (message.includes("ERR_BACKGROUND_EXPORT_REQUIRED") ||
        message.includes("will be processed in the background"))
    );
  }

  async handleConfirmExport() {
    this.showExportDialog = false;
    this.exportInProgress = true;
    this.exportError = null;
    let matrixParamsJson = "";

    try {
      const isFormatted = this.exportView === "FORMATTED";
      const useMatrixExport = this._isMatrixMode && isFormatted;

      if (useMatrixExport) {
        await this._downloadCurrentMatrixExport();
        return;
      }

      const filterConfigs = this._buildExportFilterConfigs();

      const exportRequest = {
        tableName: this.tableName,
        matrixParamsJson: matrixParamsJson,
        objectApiName: this.objectApiName,
        parentId: this.recordId ?? null,
        columns: this.columns
          .filter((col) => col.soqlFieldPath)
          .map((col) => ({
            fieldApiName: col.soqlFieldPath,
            label: col.label,
            fieldType: col.dataType?.toUpperCase() ?? "STRING"
          })),
        filters: filterConfigs,
        logic: this._filterPayload?.logic || "AND",
        customLogic: this._filterPayload?.customLogic || "",
        sortField:
          this._sortKey &&
          !this._sortKey.includes("col") &&
          !this._sortKey.includes("grand_total") &&
          !this._sortKey.includes("|")
            ? this._sortKey
            : null,
        sortDirection: this._sortDir ?? "ASC",
        searchTerm: this._searchKey ?? ""
      };

      const saveResult = await exportAndSaveFile({
        exportRequestJson: JSON.stringify(exportRequest)
      });

      if (!saveResult.success) {
        throw new Error(saveResult.errorMessage ?? "File save failed");
      }

      const downloadUrl = `/sfc/servlet.shepherd/version/download/${saveResult.contentVersionId}`;

      const anchor = document.createElement("a");
      anchor.href = downloadUrl;
      anchor.download = saveResult.fileName;
      anchor.type =
        saveResult.outputFormat === "XLSX"
          ? "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
          : "text/csv";
      anchor.target = "_blank";
      document.body.appendChild(anchor);
      anchor.click();
      document.body.removeChild(anchor);

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Export complete",
          message: `${saveResult.totalRows.toLocaleString()} rows exported → ${saveResult.fileName}`,
          variant: "success"
        })
      );
    } catch (error) {
      const rawMessage = error?.body?.message ?? error?.message ?? "Unknown error";
      const msg = this._formatExportErrorMessage(rawMessage);
      if (this._isBackgroundExportRequired(rawMessage)) {
        try {
          const jobId = await this._startExportViaEmail(matrixParamsJson);
          this.exportError = null;
          this.dispatchEvent(
            new ShowToastEvent({
              title: "Export started",
              message: `The export is processing in the background. Job ${jobId} will email a download link when complete.`,
              variant: "info"
            })
          );
          return;
        } catch (asyncError) {
          const asyncMsg =
            asyncError?.body?.message ?? asyncError?.message ?? msg;
          this.exportError = asyncMsg;
          this.dispatchEvent(
            new ShowToastEvent({
              title: "Export failed",
              message: asyncMsg,
              variant: "error",
              mode: "sticky"
            })
          );
          return;
        }
      }

      this.exportError = msg;

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Export failed",
          message: msg,
          variant: "error",
          mode: "sticky"
        })
      );
    } finally {
      this.exportInProgress = false;
    }
  }

  async handleExportMatrixOnDemand() {
    this.exportInProgress = true;
    this.exportError = null;

    try {
      const aggField =
        this._localSummaryFields.length > 0 &&
        this._localSummaryFields[0] !== "_recordCount"
          ? this._localSummaryFields[0]
          : "_recordCount";
      const matrixParamsJson = JSON.stringify({
        rowFields: this._rowGroupFields,
        columnFields: this._columnGroupFields,
        aggregateField: aggField,
        granularityMap: this._dateGranularityMap
      });

      await exportTableViaEmail({
        tableName: this.tableName,
        parentId: this.parentIdParam,
        filtersJson: this._filterPayload
          ? JSON.stringify(this._filterPayload)
          : "",
        matrixParamsJson: matrixParamsJson,
        searchTerm: this._searchKey ?? "",
        columnKeysJson: JSON.stringify(this.columns.map((col) => col.key))
      });

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Export started",
          message:
            "The matrix export is processing in the background. An email with download links will be sent upon completion.",
          variant: "info"
        })
      );
    } catch (error) {
      const msg = error?.body?.message ?? error?.message ?? "Unknown error";
      this.exportError = msg;

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Export failed",
          message: msg,
          variant: "error",
          mode: "sticky"
        })
      );
    } finally {
      this.exportInProgress = false;
    }
  }

  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
  //  CHECKBOX SELECTION (persists across pages)
  // â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•

  /**
   * Header checkbox â€” select/deselect ALL rows on current page.
   */
  handleSelectAll(event) {
    const checked = event.target.checked;
    const pageRowIds = this.displayRows
      .filter((row) => !row.hideCheckbox)
      .map((row) => row.recordId);

    if (checked) {
      pageRowIds.forEach((id) => this._selectedIds.add(id));
    } else {
      pageRowIds.forEach((id) => this._selectedIds.delete(id));
    }

    // Force reactivity
    this._selectedIds = new Set(this._selectedIds);
    this._buildRows();
  }

  /**
   * Individual row checkbox â€” toggle a single row.
   */
  handleRowSelect(event) {
    const recordId = event.currentTarget.dataset.id;
    const checked = event.target.checked;

    if (checked) {
      this._selectedIds.add(recordId);
    } else {
      this._selectedIds.delete(recordId);
    }

    // Force reactivity
    this._selectedIds = new Set(this._selectedIds);
    this._buildRows();
  }

  /**
   * Clear all selections across all pages.
   */
  handleClearSelection() {
    this._selectedIds = new Set();
    this._buildRows();
  }

  /**
   * True when ALL rows on the current page are selected.
   */
  get isAllSelectedOnPage() {
    if (!this.displayRows || this.displayRows.length === 0) return false;
    return this.displayRows.every((row) => this._selectedIds.has(row.recordId));
  }

  /**
   * True when SOME (but not all) rows on the current page are selected.
   * Used for indeterminate checkbox state.
   */
  get isSomeSelectedOnPage() {
    if (!this.displayRows || this.displayRows.length === 0) return false;
    const count = this.displayRows.filter((row) =>
      this._selectedIds.has(row.recordId)
    ).length;
    return count > 0 && count < this.displayRows.length;
  }

  get selectedCount() {
    return this._selectedIds.size;
  }

  get hasSelections() {
    return this._selectedIds.size > 0;
  }

  get selectedCountLabel() {
    const count = this._selectedIds.size;
    return `${count} row${count !== 1 ? "s" : ""} selected`;
  }

  get filterBadgeTitle() {
    return `${this.activeFilterCount} active filter(s)`;
  }

  _getCellValue(row, key) {
    const cell = row.cells.find((c) => c.key === key);
    if (!cell) return "";
    return cell.isLookup
      ? (cell.label || "").toLowerCase()
      : (cell.value || "").toString().toLowerCase();
  }

  // â”€â”€â”€â”€â”€ PAGINATION â”€â”€â”€â”€â”€
  _setPaginationData(data, resetPage = false) {
    this.allRows = data;
    this.totalRecords = data.length;
    this.totalPages = Math.ceil(this.totalRecords / this.pageSize);

    if (resetPage) {
      this.currentPage = 1;
    }

    if (this.currentPage > this.totalPages && this.totalPages > 0) {
      this.currentPage = this.totalPages;
    }

    this._buildRows();
  }

  _buildRows() {
    const start = (this.currentPage - 1) * this.pageSize;
    const end = start + this.pageSize;
    const pageRows = this.allRows.slice(start, end);

    this.displayRows = pageRows.map((row) => {
      const edits = this._editMap[row.recordId] || {};
      const isSelected = this._selectedIds.has(row.recordId);

      // Pre-index cells by key for O(1) lookup instead of O(n) find()
      const cellMap = new Map();
      for (const c of row.cells) {
        cellMap.set(c.key, c);
      }

      // Reorder and filter cells based on visibleColumns order
      const cells = this.visibleColumns.map((col) => {
        const cell = cellMap.get(col.key) || { key: col.key, value: "" };
        const editVal = edits[cell.key];
        let value = cell.value;
        let lookupId = cell.lookupId;
        let label = cell.label;

        if (editVal !== undefined) {
          if (typeof editVal === "object" && editVal !== null) {
            if (cell.isLookup) {
              value = editVal.label;
              lookupId = editVal.value;
              label = editVal.label;
            } else {
              value = editVal.value;
              label = editVal.label;
            }
          } else {
            value = editVal;
          }
        }

        const isEdited = editVal !== undefined;

        // Compute per-cell type class for width hints
        let cellTypeClass = "cell-td";
        if (cell.isLongText || cell.isRichText) {
          cellTypeClass += " cell-td--longtext";
        }
        if (isEdited) {
          cellTypeClass += " edited";
        }

        return {
          ...cell,
          value,
          lookupId,
          label,
          isEdited,
          cellClass: `${cell.cellClass || ""} ${cellTypeClass}`.trim()
        };
      });

      const hasEditsOnRow =
        Object.keys(this._editMap[row.recordId] || {}).length > 0;

      let rowClass = "";
      if (hasEditsOnRow) rowClass += "row-edited ";
      if (isSelected) rowClass += "row-selected ";

      return {
        ...row,
        cells,
        isSelected,
        rowClass: rowClass.trim()
      };
    });

    if (!this._isMatrixMode && this.displayRows.length > 0 && !this.hideGrandTotal) {
      const numericCols = this.visibleColumns.filter(
        (c) =>
          c.isNumber ||
          c.isCurrency ||
          [
            "NUMBER",
            "CURRENCY",
            "PERCENT",
            "PERCENTAGE",
            "DOUBLE",
            "INTEGER",
            "LONG",
            "DECIMAL"
          ].includes(String(c.dataType).toUpperCase())
      );

      // Only add grand total row if there are numeric columns to summarize
      if (numericCols.length > 0) {
        const footerCells = this.visibleColumns.map((col, idx) => {
          if (idx === 0) {
            return {
              key: col.key,
              value: "Grand Total",
              isRowHeader: true,
              isFooter: true,
              cellClass:
                "matrix-cell matrix-total-footer font-bold text-slate-900 cell-td"
            };
          }

          const isNumeric =
            col.isNumber ||
            col.isCurrency ||
            [
              "NUMBER",
              "CURRENCY",
              "PERCENT",
              "PERCENTAGE",
              "DOUBLE",
              "INTEGER",
              "LONG",
              "DECIMAL"
            ].includes(String(col.dataType).toUpperCase());
          if (isNumeric) {
            // Aggregate over the entire allRows dataset
            const vals = this.allRows.map((row) => {
              const cell = row.cells.find((c) => c.key === col.key);
              return cell ? cell.value : 0;
            });
            const aggVal = this._calculateAggregate(
              vals,
              this._aggregateType,
              col.key
            );
            return {
              key: col.key,
              value: this._formatValue(aggVal, col.key),
              isNumber: true,
              isMatrixTotal: true,
              isFooter: true,
              cellClass:
                "matrix-cell matrix-total-footer font-bold text-slate-800 text-right cell-td"
            };
          }

          return {
            key: col.key,
            value: "",
            isFooter: true,
            cellClass: "matrix-cell matrix-total-footer cell-td"
          };
        });

        this.displayRows.push({
          recordId: "grand_total_footer",
          cells: footerCells,
          rowClass:
            "matrix-row matrix-footer-row font-bold bg-slate-50 border-t border-b border-slate-200",
          hideCheckbox: true,
          isFooter: true
        });
      }
    }
  }

  get recordCountLabel() {
    if (this._isVirtualMode) {
      if (this.totalRecords === 0) return "No records";
      return `Showing ${this.loadedVirtualCount} of ${this.totalRecords} records`;
    }
    if (this.totalRecords === 0) return "No records";
    const start = (this.currentPage - 1) * this.pageSize + 1;
    const end = Math.min(this.currentPage * this.pageSize, this.totalRecords);
    return `Showing ${start}-${end} of ${this.totalRecords} records`;
  }

  updatePagination() {
    this._buildRows();
  }

  handlePageChange(event) {
    this.currentPage =
      typeof event.detail === "number" ? event.detail : event.detail?.page || 1;
    this._buildRows();
  }

  handlePageSizeChange(event) {
    this.pageSize = parseInt(event.target.value, 10);
    this.currentPage = 1;
    this._buildRows();
  }

  // â”€â”€â”€â”€â”€ SAVE â”€â”€â”€â”€â”€
  get hasEdits() {
    return Object.keys(this._editMap).length > 0;
  }

  handleSave() {
    if (this._isSaving) return;

    const records = Object.entries(this._editMap).map(([recordId, fields]) => {
      const flatFields = {};
      Object.entries(fields).forEach(([key, val]) => {
        flatFields[key] =
          typeof val === "object" && val !== null ? val.value : val;
      });

      return { recordId, fields: flatFields };
    });

    this._isSaving = true;

    saveTableData({
      tableName: this.tableName,
      recordsJson: JSON.stringify(records)
    })
      .then(() => {
        this._editMap = {};
        this._isSaving = false;

        this.dispatchEvent(
          new ShowToastEvent({
            title: "Success",
            message: "Records saved successfully.",
            variant: "success"
          })
        );

        if (this._isVirtualMode) {
          const viewport = this.template.querySelector(
            "c-virtual-table-viewport"
          );
          if (viewport) {
            const col = this.columns.find((c) => c.key === this._sortKey);
            const sortField = col ? col.soqlFieldPath : null;
            viewport.refresh(
              this._filterPayload,
              sortField,
              this._sortDir,
              this._searchKey
            );
          }
          this.updateVirtualRecordCount();
        }

        return refreshApex(this._wiredResult);
      })
      .catch((error) => {
        this._isSaving = false;
        const msg = error?.body?.message || "Unknown error";
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Save Failed",
            message: msg,
            variant: "error"
          })
        );
      });
  }

  // â”€â”€â”€â”€â”€ CELL / LOOKUP EVENTS â”€â”€â”€â”€â”€
  // handleRefresh defined below (authoritative async version)

  handleCellChange(event) {
    const { recordId, key, value } = event.detail;
    const map = { ...this._editMap };
    if (!map[recordId]) map[recordId] = {};
    map[recordId] = { ...map[recordId], [key]: value };
    this._editMap = map;
    this._buildRows();
  }

  // ── CUSTOM ACTIONS ──
  get selectionActions() {
    if (this.isFlowMode) {
      return [];
    }
    return this._customActions.filter(
      (a) => a.requiresSelection && this.hasSelections
    );
  }

  get globalActions() {
    if (this.isFlowMode) {
      return [];
    }
    return this._customActions.filter((a) => !a.requiresSelection);
  }

  handleActionClick(event) {
    const actionId = event.currentTarget.dataset.id;
    const action = this._customActions.find((a) => a.id === actionId);
    if (!action) return;

    const recordIds = Array.from(this._selectedIds);

    if (action.type === "Flow") {
      this._runFlowAction(action, recordIds);
    } else if (action.type === "Apex") {
      this._runApexAction(action, recordIds);
    } else if (action.type === "Navigation") {
      this._runNavigationAction(action, recordIds);
    } else if (action.type === "VF Page") {
      this._runVFPageAction(action, recordIds);
    } else if (action.type === "LWC") {
      this._runLwcAction(action, recordIds);
    }
  }

  _runFlowAction(action, recordIds) {
    this._modalTitle = action.label;
    this._modalFlowName = action.target;
    this._modalFlowInputVariables = [
      { name: "recordIds", type: "String", value: recordIds }
    ];
    this._modalMessage = "";
    this._showActionModal = true;
  }

  async _runApexAction(action, recordIds) {
    this._isModalLoading = true;
    this._showActionModal = true;
    this._modalTitle = `Executing ${action.label}...`;
    this._modalFlowName = "";

    try {
      const result = await executeTableAction({
        actionId: action.id,
        recordIds
      });
      this._modalMessage = result.message || "Action completed successfully.";
      this._modalTitle = action.label;
      if (result.success) {
        this.handleClearSelection();

        if (this._isVirtualMode) {
          const viewport = this.template.querySelector(
            "c-virtual-table-viewport"
          );
          if (viewport) {
            const col = this.columns.find((c) => c.key === this._sortKey);
            const sortField = col ? col.soqlFieldPath : null;
            viewport.refresh(
              this._filterPayload,
              sortField,
              this._sortDir,
              this._searchKey
            );
          }
          this.updateVirtualRecordCount();
        }

        return refreshApex(this._wiredResult);
      }
    } catch (error) {
      console.error("[Action] Apex Error:", error);
      this._modalMessage = "Error: " + (error.body?.message || error.message);
    } finally {
      this._isModalLoading = false;
    }
  }

  _runNavigationAction(action, recordIds) {
    let url = action.target;
    if (recordIds.length > 0) {
      url += (url.includes("?") ? "&" : "?") + "ids=" + recordIds.join(",");
    }
    this[NavigationMixin.Navigate]({
      type: "standard__webPage",
      attributes: { url }
    });
  }

  _runVFPageAction(action, recordIds) {
    let url = `/apex/${action.target}`;
    if (recordIds.length > 0) {
      url += (url.includes("?") ? "&" : "?") + "ids=" + recordIds.join(",");
    }
    window.open(url, "_blank");
  }

  _runLwcAction(action, recordIds) {
    let compName = action.target || "";
    if (compName.includes(":")) {
      compName = compName.replace(":", "__");
    } else if (!compName.includes("__")) {
      compName = "c__" + compName;
    }
    this[NavigationMixin.Navigate]({
      type: "standard__component",
      attributes: {
        componentName: compName
      },
      state: {
        c__recordIds: recordIds.join(",")
      }
    });
  }

  handleCloseModal() {
    this._showActionModal = false;
    this._modalMessage = "";
    this._modalFlowName = "";
  }

  handleFlowStatusChange(event) {
    if (
      event.detail.status === "FINISHED" ||
      event.detail.status === "FINISHED_SCREEN"
    ) {
      this.handleCloseModal();
      this.handleClearSelection();
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Success",
          message: "Flow finished successfully.",
          variant: "success"
        })
      );
      return refreshApex(this._wiredResult);
    }
  }

  handleSearch(event) {
    const term =
      typeof event.detail === "string"
        ? event.detail
        : event.detail?.searchTerm || "";
    this._searchKey = term.toLowerCase();
    this.currentPage = 1;
    this._applySort();
  }

  handleVirtualRowCountChange(event) {
    this.loadedVirtualCount = event.detail.count;
  }

  async updateVirtualRecordCount() {
    if (!this._isVirtualMode) return;
    try {
      const count = await getAsyncRecordCount({
        tableName: this.tableName,
        parentId: this.parentIdParam,
        filtersJson: this._filterPayload
          ? JSON.stringify(this._filterPayload)
          : "",
        searchTerm: this._searchKey || ""
      });
      this.totalRecords = count;
    } catch (err) {
      console.error("Error fetching virtual record count", err);
    }
  }

  _applySearchAndSort(data) {
    if (this._searchKey) {
      const searchableCols = this.columns
        .filter((col) => col.isSearchable !== false)
        .map((col) => col.key);
      data = data.filter((row) =>
        row.cells.some((cell) => {
          if (!searchableCols.includes(cell.key)) return false;
          const val = cell.isLookup
            ? (cell.label || "").toLowerCase()
            : (cell.value || "").toString().toLowerCase();
          return val.includes(this._searchKey);
        })
      );
    }
    if (this._sortKey) {
      data.sort((a, b) => {
        const valA = this._getCellValue(a, this._sortKey);
        const valB = this._getCellValue(b, this._sortKey);
        if (!valA && !valB) return 0;
        if (!valA) return this._sortDir === "asc" ? -1 : 1;
        if (!valB) return this._sortDir === "asc" ? 1 : -1;
        return this._sortDir === "asc"
          ? valA.localeCompare(valB, undefined, {
              numeric: true,
              sensitivity: "base"
            })
          : valB.localeCompare(valA, undefined, {
              numeric: true,
              sensitivity: "base"
            });
      });
    }
    return data;
  }

  handleLookupSelect(event) {
    const { recordId, key, value, label } = event.detail;
    const map = { ...this._editMap };
    if (!map[recordId]) map[recordId] = {};
    map[recordId] = { ...map[recordId], [key]: { value, label } };
    this._editMap = map;
    this._buildRows();
  }

  handleLookupClear(event) {
    const { recordId, key } = event.detail;
    const map = { ...this._editMap };
    if (!map[recordId]) map[recordId] = {};
    map[recordId] = { ...map[recordId], [key]: { value: null, label: null } };
    this._editMap = map;
    this._buildRows();
  }

  handleView(event) {
    const recordId = event.currentTarget.dataset.id;
    window.open(`/lightning/r/${recordId}/view`, "_blank");
  }

  // handleDelete defined below (authoritative async version)

  // â”€â”€â”€â”€â”€ GETTERS â”€â”€â”€â”€â”€
  get visibleColumns() {
    if (this._isMatrixMode && this._matrixData) {
      return this._matrixData.columns;
    }
    const activeFilterFields = new Set(
      (this._filterPayload?.filters || [])
        .filter((f) => f.fieldName && f.operator)
        .map((f) => f.fieldName)
    );
    return (this.columns || [])
      .filter((c) => c.isVisible !== false)
      .map((c) => ({
        ...c,
        isFiltered: activeFilterFields.has(c.fieldName)
      }));
  }

  get showFilterPanel() {
    return this._showFilterPanel;
  }

  get hasActiveFilters() {
    return !!this._filterPayload?.filters?.some(
      (f) => f.fieldName && f.operator
    );
  }

  get showFilterChipsBar() {
    return this.hasActiveFilters && !this.isWidgetMode && !this.hideFilterChips;
  }

  get activeFilterCount() {
    if (!this._filterPayload?.filters) return 0;
    return this._filterPayload.filters.filter((f) => f.fieldName && f.operator)
      .length;
  }

  // rowFieldsCount, pivotColsCount and _columnGroupLabel are defined below (authoritative versions)

  get matrixBtnClass() {
    return this._isMatrixMode ? "btn-export matrix-btn--active" : "btn-export";
  }

  get matrixBtnLabel() {
    return "Matrix";
  }

  get freezeColStyle() {
    if (this.matrixResult?.rowFieldLabels) {
      const width = this.matrixResult.rowFieldLabels.length * 150;
      return `width: ${width}px; min-width: ${width}px; max-width: ${width}px; padding: 0; border: none;`;
    }
    return "";
  }

  get availableRowGroupOptions() {
    return this.columns
      .filter(
        (c) => c.isVisible !== false && !this._rowGroupFields.includes(c.key)
      )
      .map((c) => ({ label: c.label, value: c.key }));
  }

  get selectedRowGroupOptions() {
    return this._rowGroupFields.map((key) => {
      const c = this.columns.find((col) => col.key === key);
      return {
        label: c ? c.label : key,
        value: key,
        isDate: c && (c.isDate || c.isDateTime),
        granularity: this._dateGranularityMap[key] || ""
      };
    });
  }

  get availableColGroupOptions() {
    return this.columns
      .filter(
        (c) =>
          (c.isPicklist ||
            c.isLookup ||
            c.isBoolean ||
            c.isDate ||
            c.isDateTime) &&
          !this._columnGroupFields.includes(c.key)
      )
      .map((c) => ({ label: c.label, value: c.key }));
  }

  get selectedColGroupOptions() {
    return this._columnGroupFields.map((key) => {
      const c = this.columns.find((col) => col.key === key);
      return {
        label: c ? c.label : key,
        value: key,
        isDate: c && (c.isDate || c.isDateTime),
        granularity: this._dateGranularityMap[key] || ""
      };
    });
  }

  get granularityOptions() {
    return [
      { label: "Full Date", value: "" },
      { label: "Month", value: "CALENDAR_MONTH" },
      { label: "Quarter", value: "CALENDAR_QUARTER" },
      { label: "Year", value: "CALENDAR_YEAR" }
    ];
  }

  get availableSummaryOptions() {
    const valKeys = this._localSummaryFields;
    const options = [];

    if (!valKeys.includes("_recordCount")) {
      options.push({ label: "Record Count", value: "_recordCount" });
    }

    this.columns.forEach((c) => {
      const isNumeric =
        c.isNumber ||
        c.isCurrency ||
        [
          "NUMBER",
          "CURRENCY",
          "PERCENT",
          "PERCENTAGE",
          "DOUBLE",
          "INTEGER",
          "LONG",
          "DECIMAL"
        ].includes(String(c.dataType).toUpperCase());
      const isLookup =
        c.isLookup || String(c.dataType).toUpperCase() === "REFERENCE";

      if (isNumeric || isLookup) {
        if (!valKeys.includes(c.key)) {
          options.push({
            label: isLookup ? `${c.label} (Count)` : c.label,
            value: c.key
          });
        }
      }
    });
    return options;
  }

  get selectedSummaryOptions() {
    return this._localSummaryFields.map((key) => {
      if (key === "_recordCount") {
        return { label: "Record Count", value: key };
      }
      const c = this.columns.find((col) => col.key === key);
      const isLookup =
        c && (c.isLookup || String(c.dataType).toUpperCase() === "REFERENCE");
      return {
        label: c ? (isLookup ? `${c.label} (Count)` : c.label) : key,
        value: key
      };
    });
  }

  get selectedAggregateLabel() {
    const ag = this.aggregateTypeOptions.find(
      (o) => o.value === this._localAggregateType
    );
    return ag ? ag.label : "Sum";
  }

  get hasStackedHeaders() {
    return !!(this._matrixData && this._matrixData.stackedHeaders);
  }

  get matrixStackedHeaders() {
    return this._matrixData ? this._matrixData.stackedHeaders : [];
  }

  get matrixHeaderRow2() {
    return this._matrixData ? this._matrixData.headerRow2 : [];
  }

  handleMatrixToggle() {
    const enteringMatrixMode = !this._localIsMatrixMode;
    this._localIsMatrixMode = enteringMatrixMode;
    if (!this._isMatrixMode) {
      this.exitMatrixMode();
      return;
    } else {
      this._matrixPausedByUser = false;
      // Save current size and expand for Matrix
      this._previousPageSize = this.pageSize;
      this.pageSize = 2000;
      this.currentPage = 1;

      const savedMatrixConfig = this._currentAppliedView?.matrixConfig;
      if (savedMatrixConfig) {
        this._localRowGroupFields = this.normalizeMatrixFieldKeys(
          savedMatrixConfig.rowGroups || []
        );
        this._localColumnGroupFields = this.normalizeMatrixFieldKeys(
          savedMatrixConfig.colGroups || savedMatrixConfig.columnGroups || []
        );
        this._localSummaryFields = this.normalizeMatrixFieldKeys(
          savedMatrixConfig.summaryFields || [],
          true
        );
        this._localAggregateType = savedMatrixConfig.aggregateType || "SUM";
        this._dateGranularityMap = savedMatrixConfig.dateGranularityMap || {};
      }

      // Set defaults if in Matrix Mode
      if (
        this._localSummaryFields.length === 0 &&
        this.availableSummaryOptions.length > 0
      ) {
        this._localSummaryFields = [this.availableSummaryOptions[0].value];
      }

      // Set default column group if no grouping at all
      if (
        this._columnGroupFields.length === 0 &&
        this._rowGroupFields.length === 0 &&
        this.availableColGroupOptions.length > 0
      ) {
        this._localColumnGroupFields = [this.availableColGroupOptions[0].value];
      }

      // Also try to set a row group default if none
      if (
        this._rowGroupFields.length === 0 &&
        this.availableRowGroupOptions.length > 0
      ) {
        this._localRowGroupFields = [this.availableRowGroupOptions[0].value];
      }
    }

    if (this._localIsMatrixMode) {
      this.markMatrixDraftDirty();
    } else {
      this._applySort();
    }
  }

  exitMatrixMode() {
    this._matrixPausedByUser = true;
    this.pageSize = this._previousPageSize || 10;
    this.currentPage = 1;
    this.matrixDraftDirty = false;
    this.matrixLoading = false;
    this.matrixRequestStatus = "";
    this.matrixJobId = "";
    this.matrixProgress = 0;
    this.matrixProcessingMessage = "";
    this.matrixError = null;
    this._matrixLimitExceeded = false;
    this._matrixLimitCount = "";
    this._activeMatrixConfigJson = "";
    this._matrixData = null;
    this.stopMatrixJobPolling();
    this.resetMatrixRenderState();
    this._applySort();
  }

  handleAddRowGroup(event) {
    const field = event.detail.value;
    if (this._rowGroupFields.length < 5) {
      this._localRowGroupFields = [...this._rowGroupFields, field];
      if (this._localIsMatrixMode) this.markMatrixDraftDirty();
      else this._applySort();
    }
  }

  handleRemoveRowGroup(event) {
    const field =
      event.target.dataset.field || event.currentTarget.dataset.field;
    this._localRowGroupFields = this._rowGroupFields.filter((f) => f !== field);
    if (this._localIsMatrixMode) this.markMatrixDraftDirty();
    else this._applySort();
  }

  handleAddColGroup(event) {
    const field = event.detail.value;
    if (this._columnGroupFields.length < 2) {
      this._localColumnGroupFields = [...this._columnGroupFields, field];
      if (this._localIsMatrixMode) this.markMatrixDraftDirty();
      else this._applySort();
    } else {
      this.showToast(
        "Limit Reached",
        "You can select up to 2 column grouping fields.",
        "warning"
      );
    }
  }

  handleRemoveColGroup(event) {
    const field =
      event.target.dataset.field || event.currentTarget.dataset.field;
    this._localColumnGroupFields = this._columnGroupFields.filter(
      (f) => f !== field
    );
    if (this._localIsMatrixMode) this.markMatrixDraftDirty();
    else this._applySort();
  }

  handleAddSummary(event) {
    const field = event.detail.value;
    this._localSummaryFields = [...this._localSummaryFields, field];
    if (this._localIsMatrixMode) this.markMatrixDraftDirty();
    else this._applySort();
  }

  handleRemoveSummary(event) {
    const field =
      event.target.dataset.field || event.currentTarget.dataset.field;
    if (this._localSummaryFields.length > 1) {
      this._localSummaryFields = this._localSummaryFields.filter(
        (f) => f !== field
      );
      if (this._localIsMatrixMode) this.markMatrixDraftDirty();
      else this._applySort();
    } else {
      this.showToast(
        "Select At Least One",
        "At least one summary field must remain selected.",
        "warning"
      );
    }
  }

  handleAggregateChange(event) {
    this._localAggregateType = event.detail.value;
    if (this._localIsMatrixMode) this.markMatrixDraftDirty();
    else this._applySort();
  }

  get hasMatrixResult() {
    return !!this.matrixResult;
  }

  get isMatrixJobActive() {
    return (
      this.matrixRequestStatus === "QUEUED" ||
      this.matrixRequestStatus === "PROCESSING"
    );
  }

  get canGenerateMatrix() {
    return (
      this._localIsMatrixMode &&
      !this.matrixLoading &&
      !this.isMatrixJobActive &&
      this._localSummaryFields.length > 0 &&
      (this._rowGroupFields.length > 0 || this._columnGroupFields.length > 0)
    );
  }

  get isGenerateMatrixDisabled() {
    return !this.canGenerateMatrix;
  }

  get matrixGenerateLabel() {
    if (this.matrixLoading) return this.matrixLoadingLabel;
    if (this.isMatrixJobActive) return "Processing...";
    if (this.matrixResult && this.matrixDraftDirty) return "Regenerate Matrix";
    if (this.matrixResult) return "Refresh Matrix";
    return "Generate Matrix";
  }

  get showMatrixSetupState() {
    return (
      this._localIsMatrixMode &&
      !this.matrixLoading &&
      !this.matrixError &&
      !this._matrixLimitExceeded &&
      !this.isMatrixJobActive &&
      !this.matrixResult
    );
  }

  get rowFieldsCount() {
    return this._rowGroupFields.length;
  }

  get valKeysCount() {
    return this._localSummaryFields.length > 0
      ? this._localSummaryFields.length
      : 1;
  }

  get pivotColsCount() {
    if (!this._matrixData || !this._matrixData.columns) return 0;
    return this._matrixData.columns.filter((c) => c.isPivot).length;
  }

  get _columnGroupLabel() {
    if (this._columnGroupFields.length === 0) return "No Column Grouping";
    return this._columnGroupFields
      .map((key) => {
        const col = this.columns.find((c) => c.key === key);
        return col ? col.label : key;
      })
      .join(" > ");
  }

  _formatValue(val, key) {
    if (key === "_recordCount") {
      return (val || 0).toLocaleString("en-US", { maximumFractionDigits: 0 });
    }

    const num =
      typeof val === "number"
        ? val
        : parseFloat(String(val).replace(/[$,]/g, ""));
    const cleanNum = isNaN(num) ? 0 : num;

    if (String(this._aggregateType).toUpperCase() === "COUNT") {
      return cleanNum.toLocaleString("en-US", { maximumFractionDigits: 0 });
    }

    const col = this.columns.find((c) => c.key === key);
    if (!col) return cleanNum.toLocaleString("en-US");

    const isLookup =
      col.isLookup || String(col.dataType).toUpperCase() === "REFERENCE";
    if (isLookup) {
      return cleanNum.toLocaleString("en-US", { maximumFractionDigits: 0 });
    }

    const isCurrency =
      col.isCurrency || String(col.dataType).toUpperCase() === "CURRENCY";
    if (isCurrency) {
      return new Intl.NumberFormat("en-US", {
        style: "currency",
        currency: "USD",
        maximumFractionDigits: 0
      }).format(cleanNum);
    }
    return cleanNum.toLocaleString("en-US", { maximumFractionDigits: 2 });
  }

  _transformToMatrix(data) {
    if (!this._isMatrixMode || !this._aggregateField) return data;

    // Support either row grouping or column grouping or both
    if (
      this._rowGroupFields.length === 0 &&
      this._columnGroupFields.length === 0
    )
      return data;

    const colKeys = this._columnGroupFields;
    const valKeys =
      this._localSummaryFields.length > 0
        ? this._localSummaryFields
        : this.columns.find((c) => c.isNumber || c.isCurrency)
          ? [this.columns.find((c) => c.isNumber || c.isCurrency).key]
          : [];
    const rowKeys = this._rowGroupFields;

    if (valKeys.length === 0) return data;

    // 1. Identify Column Combinations (Cartesian Product)
    // For 2 levels: Unique(Col1|Col2)
    const baseCombinations =
      colKeys.length > 0
        ? [
            ...new Set(
              data.map((row) => {
                return colKeys
                  .map((ck) => this._getPartitionedValue(row, ck))
                  .join("|");
              })
            )
          ]
        : [];

    if (baseCombinations.length > 0) {
      baseCombinations.sort((comboA, comboB) => {
        const partsA = comboA.split("|");
        const partsB = comboB.split("|");
        for (let i = 0; i < colKeys.length; i++) {
          const ck = colKeys[i];
          const colField = this.columns.find((c) => c.key === ck);
          const dt = String(colField?.dataType || "").toUpperCase();
          const isDate =
            colField?.isDate ||
            colField?.isDateTime ||
            ["DATE", "DATETIME"].includes(dt);
          const valA = partsA[i];
          const valB = partsB[i];

          if (valA === valB) continue;
          if (valA === "(blank)") return 1;
          if (valB === "(blank)") return -1;

          if (isDate) {
            const dateA = this._parseMatrixDateString(valA, ck);
            const dateB = this._parseMatrixDateString(valB, ck);
            if (dateA && dateB) {
              return dateA.getTime() - dateB.getTime();
            }
          }
          return valA.localeCompare(valB, undefined, { numeric: true });
        }
        return 0;
      });
    }

    // 2. Build Column Hierarchy (Stacked Headers)
    let stackedHeaders = null;
    if (colKeys.length > 0) {
      if (colKeys.length > 1) {
        const level1Map = {};
        baseCombinations.forEach((combo) => {
          const parts = combo.split("|");
          const parentVal = parts[0];
          if (!level1Map[parentVal]) level1Map[parentVal] = 0;
          level1Map[parentVal]++;
        });

        stackedHeaders = Object.keys(level1Map)
          .sort()
          .map((val) => ({
            label: val,
            colspan: level1Map[val] * valKeys.length
          }));
      } else {
        // If only 1 column group, stacked headers are simply the unique group values
        stackedHeaders = baseCombinations.map((val) => ({
          label: val,
          colspan: valKeys.length
        }));
      }
    }

    // Second-level column headers
    const _getLabel = (valKey) => {
      if (valKey === "_recordCount") return "Record Count";
      const colField = this.columns.find((c) => c.key === valKey);
      if (!colField) return valKey;
      const isLookup =
        colField.isLookup ||
        String(colField.dataType).toUpperCase() === "REFERENCE";
      return isLookup ? `${colField.label} (Count)` : colField.label;
    };

    let headerRow2 = [];
    if (colKeys.length > 0) {
      baseCombinations.forEach((combo) => {
        valKeys.forEach((valKey) => {
          headerRow2.push({
            key: `pivot_${combo}|${valKey}`,
            label: _getLabel(valKey)
          });
        });
      });

      // Append Grand Total sub-columns
      valKeys.forEach((valKey) => {
        headerRow2.push({
          key: `grand_total|${valKey}`,
          label: _getLabel(valKey)
        });
      });
    }

    const matrixResult = {
      columns: [
        ...rowKeys.map((rk) => {
          const col = this.columns.find((c) => c.key === rk);
          return {
            key: rk,
            label: col ? col.label : rk,
            isRowGroup: true,
            headerClass: "matrix-header--row-group"
          };
        }),
        ...(colKeys.length > 0
          ? headerRow2
              .filter((h) => !h.key.startsWith("grand_total"))
              .map((h) => ({
                key: h.key,
                label: h.label,
                isPivot: true,
                cellClass: "matrix-cell matrix-cell--value"
              }))
          : valKeys.map((valKey) => {
              return {
                key: `total_${valKey}`,
                label: _getLabel(valKey),
                isPivot: false,
                isTotal: true,
                cellClass: "matrix-cell matrix-cell--total"
              };
            })),
        ...(colKeys.length > 0
          ? valKeys.map((valKey) => {
              return {
                key: `grand_total|${valKey}`,
                label: _getLabel(valKey),
                isTotal: true,
                cellClass: "matrix-cell matrix-cell--total"
              };
            })
          : [])
      ],
      stackedHeaders: stackedHeaders,
      headerRow2: headerRow2,
      rows: []
    };

    const groupedMap = new Map();

    data.forEach((row) => {
      const rowKeyParts = rowKeys.map((rk) =>
        this._getPartitionedValue(row, rk)
      );
      const rowGroupKey = rowKeyParts.join("|");
      const colCombo = colKeys
        .map((ck) => this._getPartitionedValue(row, ck))
        .join("|");

      if (!groupedMap.has(rowGroupKey)) {
        groupedMap.set(rowGroupKey, {
          keyParts: rowKeyParts,
          pivotVals: {},
          rowTotals: {}
        });
      }

      const entry = groupedMap.get(rowGroupKey);
      valKeys.forEach((valKey) => {
        const cellKey = colCombo ? `${colCombo}|${valKey}` : valKey;
        let cleanAggVal = 0;

        if (valKey === "_recordCount") {
          cleanAggVal = 1;
        } else {
          const aggCell = row.cells.find((c) => c.key === valKey);
          const colField = this.columns.find((c) => c.key === valKey);
          const isLookup =
            colField &&
            (colField.isLookup ||
              String(colField.dataType).toUpperCase() === "REFERENCE");

          if (isLookup) {
            cleanAggVal = aggCell ? aggCell.value : null;
          } else {
            const aggVal = aggCell
              ? parseFloat(String(aggCell.value || 0).replace(/[$,]/g, ""))
              : 0;
            cleanAggVal = isNaN(aggVal) ? 0 : aggVal;
          }
        }

        if (!entry.pivotVals[cellKey]) {
          entry.pivotVals[cellKey] = [];
        }
        entry.pivotVals[cellKey].push(cleanAggVal);

        if (!entry.rowTotals[valKey]) {
          entry.rowTotals[valKey] = [];
        }
        entry.rowTotals[valKey].push(cleanAggVal);
      });
    });

    // 3. Flatten Map to Rows
    let lastRowKeyParts = [];
    const flatRows = [];

    // SORTING LOGIC FOR MATRIX ROWS
    const sortedKeys = [...groupedMap.keys()].sort((a, b) => {
      if (!this._sortKey) return a.localeCompare(b);

      const entryA = groupedMap.get(a);
      const entryB = groupedMap.get(b);
      const dir = this._sortDir === "asc" ? 1 : -1;

      let valA, valB;

      if (this._sortKey.startsWith("grand_total")) {
        const parts = this._sortKey.split("|");
        const valKey = parts.length > 1 ? parts[1] : valKeys[0];
        valA = this._calculateAggregate(
          entryA.rowTotals[valKey] || [],
          this._aggregateType,
          valKey
        );
        valB = this._calculateAggregate(
          entryB.rowTotals[valKey] || [],
          this._aggregateType,
          valKey
        );
      } else if (this._sortKey.startsWith("pivot_")) {
        const combo = this._sortKey.replace("pivot_", "");
        const valKey = combo.includes("|") ? combo.split("|").pop() : combo;
        valA = this._calculateAggregate(
          entryA.pivotVals[combo] || [],
          this._aggregateType,
          valKey
        );
        valB = this._calculateAggregate(
          entryB.pivotVals[combo] || [],
          this._aggregateType,
          valKey
        );
      } else {
        // Sorting by one of the Row Group fields
        const rkIdx = rowKeys.indexOf(this._sortKey);
        if (rkIdx !== -1) {
          valA = entryA.keyParts[rkIdx];
          valB = entryB.keyParts[rkIdx];
        } else {
          return a.localeCompare(b) * dir;
        }
      }

      if (typeof valA === "number" && typeof valB === "number") {
        return (valA - valB) * dir;
      }
      return (
        String(valA).localeCompare(String(valB), undefined, {
          numeric: true,
          sensitivity: "base"
        }) * dir
      );
    });

    sortedKeys.forEach((rowGroupKey) => {
      const entry = groupedMap.get(rowGroupKey);
      const cells = [];

      // Row group cells
      entry.keyParts.forEach((val, idx) => {
        const isRepeat =
          lastRowKeyParts.slice(0, idx + 1).join("|") ===
          entry.keyParts.slice(0, idx + 1).join("|");
        cells.push({
          key: rowKeys[idx],
          value: isRepeat ? "" : val,
          isRowHeader: true,
          isPlaceholder: isRepeat,
          cellClass: isRepeat
            ? "matrix-cell matrix-cell--hierarchical"
            : "matrix-cell matrix-cell--hierarchical-main"
        });
      });

      // Pivot / value cells
      if (colKeys.length > 0) {
        baseCombinations.forEach((combo) => {
          valKeys.forEach((valKey) => {
            const cellKey = `${combo}|${valKey}`;
            const vals = entry.pivotVals[cellKey] || [];
            const val = this._calculateAggregate(
              vals,
              this._aggregateType,
              valKey
            );
            cells.push({
              key: `pivot_${cellKey}`,
              value: vals.length > 0 ? this._formatValue(val, valKey) : "-",
              isNumber: true,
              isMatrixValue: true,
              cellClass: "matrix-cell matrix-cell--value"
            });
          });
        });

        // Row Grand totals
        valKeys.forEach((valKey) => {
          const vals = entry.rowTotals[valKey] || [];
          const val = this._calculateAggregate(vals, this._aggregateType);
          cells.push({
            key: `grand_total|${valKey}`,
            value: vals.length > 0 ? this._formatValue(val, valKey) : "-",
            isNumber: true,
            isMatrixTotal: true,
            cellClass: "matrix-cell matrix-cell--total"
          });
        });
      } else {
        // No column grouping - standard totals columns
        valKeys.forEach((valKey) => {
          const vals = entry.rowTotals[valKey] || [];
          const val = this._calculateAggregate(
            vals,
            this._aggregateType,
            valKey
          );
          cells.push({
            key: `total_${valKey}`,
            value: vals.length > 0 ? this._formatValue(val, valKey) : "-",
            isNumber: true,
            isMatrixTotal: true,
            cellClass: "matrix-cell matrix-cell--total"
          });
        });
      }

      flatRows.push({
        recordId: `matrix_${rowGroupKey}`,
        cells: cells,
        rowClass: "matrix-row"
      });

      lastRowKeyParts = [...entry.keyParts];
    });

    // 4. Add Grand Total Footer Row
    if (flatRows.length > 0) {
      const footerCells = [];
      rowKeys.forEach((rk, idx) => {
        footerCells.push({
          key: rk,
          value: idx === 0 ? "Grand Total" : "",
          isRowHeader: true,
          cellClass: "matrix-cell matrix-total-footer"
        });
      });

      if (colKeys.length > 0) {
        // Pivot Columns Grand Totals
        baseCombinations.forEach((combo) => {
          valKeys.forEach((valKey) => {
            const cellKey = `${combo}|${valKey}`;
            const matchingVals = data
              .filter((row) => {
                const rowColCombo = colKeys
                  .map((ck) => this._getPartitionedValue(row, ck))
                  .join("|");
                return rowColCombo === combo;
              })
              .map((row) => {
                const cell = row.cells.find((c) => c.key === valKey);
                return cell ? cell.value : valKey === "_recordCount" ? 1 : 0;
              });
            const colTotal = this._calculateAggregate(
              matchingVals,
              this._aggregateType,
              valKey
            );
            footerCells.push({
              key: `pivot_${cellKey}`,
              value:
                matchingVals.length > 0
                  ? this._formatValue(colTotal, valKey)
                  : "-",
              isNumber: true,
              cellClass: "matrix-cell matrix-total-footer"
            });
          });
        });

        // Grand Totals Grand Totals
        valKeys.forEach((valKey) => {
          const matchingVals = data.map((row) => {
            const cell = row.cells.find((c) => c.key === valKey);
            return cell ? cell.value : valKey === "_recordCount" ? 1 : 0;
          });
          const colTotal = this._calculateAggregate(
            matchingVals,
            this._aggregateType,
            valKey
          );
          footerCells.push({
            key: `grand_total|${valKey}`,
            value:
              matchingVals.length > 0
                ? this._formatValue(colTotal, valKey)
                : "-",
            isNumber: true,
            cellClass: "matrix-cell matrix-total-footer matrix-total-overall"
          });
        });
      } else {
        // Standard row-only totals columns Grand Totals
        valKeys.forEach((valKey) => {
          const matchingVals = data.map((row) => {
            const cell = row.cells.find((c) => c.key === valKey);
            return cell ? cell.value : valKey === "_recordCount" ? 1 : 0;
          });
          const colTotal = this._calculateAggregate(
            matchingVals,
            this._aggregateType,
            valKey
          );
          footerCells.push({
            key: `total_${valKey}`,
            value:
              matchingVals.length > 0
                ? this._formatValue(colTotal, valKey)
                : "-",
            isNumber: true,
            cellClass: "matrix-cell matrix-total-footer matrix-total-overall"
          });
        });
      }

      flatRows.push({
        recordId: "matrix_footer",
        cells: footerCells,
        rowClass: "matrix-row matrix-footer-row",
        hideCheckbox: true
      });
    }

    return {
      rows: flatRows,
      columns: matrixResult.columns,
      stackedHeaders: matrixResult.stackedHeaders,
      headerRow2: headerRow2.map((h) => ({
        ...h,
        isSorted: h.key === this._sortKey,
        isSortedAsc: h.key === this._sortKey && this._sortDir === "asc"
      }))
    };
  }

  get isTotalSorted() {
    return this._sortKey === "grand_total";
  }

  get isTotalSortedAsc() {
    return this._sortKey === "grand_total" && this._sortDir === "asc";
  }

  /**
   * Extracts and partitions a cell value based on granularity.
   */
  _getPartitionedValue(row, key) {
    const cell = row.cells.find((c) => c.key === key);
    if (!cell) return "(blank)";

    const rawValue = cell.value;
    const displayLabel = cell.label || cell.value;
    if (!rawValue || rawValue === "") return "(blank)";

    const granularity = this._dateGranularityMap[key] || "";

    if (granularity !== "" && (cell.isDate || cell.isDateTime)) {
      const dateObj = new Date(rawValue);
      if (isNaN(dateObj.getTime())) return displayLabel;

      if (granularity === "CALENDAR_YEAR")
        return dateObj.getFullYear().toString();
      if (granularity === "CALENDAR_MONTH") {
        const monthNames = [
          "Jan",
          "Feb",
          "Mar",
          "Apr",
          "May",
          "Jun",
          "Jul",
          "Aug",
          "Sep",
          "Oct",
          "Nov",
          "Dec"
        ];
        return `${monthNames[dateObj.getMonth()]} ${dateObj.getFullYear()}`;
      }
      if (granularity === "CALENDAR_QUARTER") {
        const q = Math.floor(dateObj.getMonth() / 3) + 1;
        return `Q${q} ${dateObj.getFullYear()}`;
      }
    }

    return displayLabel || "(blank)";
  }

  handleGranularityChange(event) {
    const fieldKey = event.target.dataset.field;
    this._dateGranularityMap[fieldKey] = event.target.value;
    this._dateGranularityMap = { ...this._dateGranularityMap };
    if (this._isMatrixMode) {
      this.markMatrixDraftDirty();
    } else {
      this._applySort();
    }
  }

  get filterToggleClass() {
    if (this._showFilterPanel)
      return "filter-toggle-btn filter-toggle-btn--open";
    if (this.hasActiveFilters)
      return "filter-toggle-btn filter-toggle-btn--active";
    return "filter-toggle-btn";
  }

  get filterToggleTitle() {
    if (this._showFilterPanel) return "Close filter panel";
    if (this.hasActiveFilters)
      return `${this.activeFilterCount} filter(s) active — click to edit`;
    return "Open filter panel";
  }

  get filterSidebarClass() {
    return this._showFilterPanel
      ? "filter-sidebar-panel open"
      : "filter-sidebar-panel";
  }

  get filterBackdropClass() {
    return this._showFilterPanel
      ? "filter-sidebar-backdrop active"
      : "filter-sidebar-backdrop";
  }

  get filterPanelAriaHidden() {
    return !this._showFilterPanel;
  }

  get viewSidebarClass() {
    return this._showViewManager
      ? "filter-sidebar-panel open"
      : "filter-sidebar-panel";
  }

  get viewBackdropClass() {
    return this._showViewManager
      ? "filter-sidebar-backdrop active"
      : "filter-sidebar-backdrop";
  }

  get viewPanelAriaHidden() {
    return !this._showViewManager;
  }

  get currentMatrixConfig() {
    return {
      isMatrixMode: this._isMatrixMode,
      rowGroups: this._rowGroupFields,
      colGroups: this._columnGroupFields,
      summaryFields: this._localSummaryFields || [],
      aggregateType: this._aggregateType,
      dateGranularityMap: this._dateGranularityMap || {}
    };
  }

  get filterLogicLabel() {
    return this._filterPayload?.logic === "OR" ? "OR" : "AND";
  }

  get activeFilterChips() {
    if (!this._filterPayload?.filters) return [];

    const activeFilters = this._filterPayload.filters.filter(
      (f) => f.fieldName && f.operator
    );

    return activeFilters.map((f, i) => {
      const col = (this.columns || []).find((c) => c.fieldName === f.fieldName);
      const fieldLabel = col?.label || f.fieldName;

      const opLabels = {
        CONTAINS: "contains",
        EQUALS: "=",
        NOT_EQUALS: "≠",
        STARTS_WITH: "starts with",
        ENDS_WITH: "ends with",
        GREATER_THAN: ">",
        LESS_THAN: "<",
        GTE: "≥",
        LTE: "≤",
        BETWEEN: "between",
        BEFORE: "before",
        AFTER: "after",
        RANGE: "range",
        IN: "in",
        NOT_IN: "not in",
        IS_BLANK: "is blank",
        IS_NOT_BLANK: "is not blank",
        IS_TRUE: "is true",
        IS_FALSE: "is false"
      };
      const opUpper = (f.operator || "").toUpperCase();
      const opLabel = opLabels[opUpper] || f.operator;

      let displayValue = "";
      const noValOps = new Set([
        "IS_BLANK",
        "IS_NOT_BLANK",
        "IS_TRUE",
        "IS_FALSE"
      ]);
      const betweenOps = new Set(["BETWEEN", "RANGE"]);

      if (noValOps.has(opUpper)) {
        displayValue = "";
      } else if (betweenOps.has(opUpper)) {
        const valMin = f.values && f.values.length > 0 ? f.values[0] : "?";
        const valMax = f.values && f.values.length > 1 ? f.values[1] : "?";
        displayValue = `${valMin ?? "?"} – ${valMax ?? "?"}`;
      } else if (Array.isArray(f.values)) {
        if (col && (col.isLookup || col.dataType === "Lookup")) {
          displayValue = f.values
            .map((valId) => this._lookupDisplayMap[valId] || valId)
            .join(", ");
        } else {
          displayValue = f.values.join(", ");
        }
      } else {
        displayValue = "";
      }

      return {
        id: `chip_${i}`,
        filterIndex: i,
        field: fieldLabel,
        operator: opLabel,
        displayValue: String(displayValue)
      };
    });
  }

  async handleRefresh() {
    this.isLoading = true;
    try {
      if (this._isVirtualMode) {
        const viewport = this.template.querySelector(
          "c-virtual-table-viewport"
        );
        if (viewport) {
          const col = this.columns.find((c) => c.key === this._sortKey);
          const sortField = col ? col.soqlFieldPath : null;
          viewport.refresh(
            this._filterPayload,
            sortField,
            this._sortDir,
            this._searchKey
          );
        }
        this.updateVirtualRecordCount();
      } else {
        await refreshApex(this._wiredResult);
      }
    } finally {
      this.isLoading = false;
    }
  }

  handleRowAction(event) {
    const { action, recordId } = event.detail;
    if (action === "view") {
      this[NavigationMixin.Navigate]({
        type: "standard__recordPage",
        attributes: {
          recordId: recordId,
          actionName: "view"
        }
      });
    } else if (action === "delete") {
      this.performDelete(recordId);
    }
  }

  handleViewRecord(event) {
    const recordId = event.target.dataset.id;
    this[NavigationMixin.Navigate]({
      type: "standard__recordPage",
      attributes: {
        recordId: recordId,
        actionName: "view"
      }
    });
  }

  handleNewRecord() {
    let defaultValues = {};
    if (this.parentIdParam && this.parentFilterField) {
      defaultValues[this.parentFilterField] = this.parentIdParam;
    }
    this[NavigationMixin.Navigate]({
      type: "standard__objectPage",
      attributes: {
        objectApiName: this.objectApiName || "Account",
        actionName: "new"
      },
      state: {
        defaultFieldValues: JSON.stringify(defaultValues)
      }
    });
  }

  async handleDelete(event) {
    const recordId = event.target.dataset.id;
    await this.performDelete(recordId);
  }

  async performDelete(recordId) {
    if (!confirm("Are you sure you want to delete this record?")) return;

    this.isLoading = true;
    try {
      await deleteRecord(recordId);
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Success",
          message: "Record deleted",
          variant: "success"
        })
      );

      if (this._isVirtualMode) {
        const viewport = this.template.querySelector(
          "c-virtual-table-viewport"
        );
        if (viewport) {
          const col = this.columns.find((c) => c.key === this._sortKey);
          const sortField = col ? col.soqlFieldPath : null;
          viewport.refresh(
            this._filterPayload,
            sortField,
            this._sortDir,
            this._searchKey
          );
        }
        this.updateVirtualRecordCount();
      } else {
        await refreshApex(this._wiredResult);
      }
    } catch (error) {
      console.error("[DynamicMetaTable] Delete Error:", error);
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Error Deleting Record",
          message: error.body?.message || "Unknown error",
          variant: "error"
        })
      );
    } finally {
      this.isLoading = false;
    }
  }

  get showRowActions() {
    return !this._isMatrixMode && !this._hideRowActions;
  }

  get isEmptyState() {
    if (this._isVirtualMode) {
      return false;
    }
    return (
      !this.isLoading && (!this.displayRows || this.displayRows.length === 0)
    );
  }

  // ============================================================
  // MATRIX MODE HANDLER
  // ============================================================
  resetMatrixRenderState() {
    this.releaseMatrixScrollContainer();
    this.matrixResult = null;
    this.matrixRows = [];
    this.matrixColHeaders = [];
    this.vsRows = [];
    this.vsSpacerTopPx = 0;
    this.vsSpacerBotPx = 0;
    this.vsTotalHeight = 0;
    this.vsTotalCount = 0;
    if (this._vsEngine?.clear) {
      this._vsEngine.clear();
    }
  }

  markMatrixDraftDirty() {
    if (
      this.matrixJobId &&
      this.isMatrixJobActive &&
      this.isActiveMatrixConfigCurrent()
    ) {
      return;
    }

    this.matrixDraftDirty = true;
    this.matrixError = null;
    this._matrixLimitExceeded = false;
    this._matrixLimitCount = "";
    this.matrixRequestStatus = "";
    this.matrixJobId = "";
    this.matrixProgress = 0;
    this.matrixProcessingMessage = "";
    this._activeMatrixConfigJson = "";
    this.stopMatrixJobPolling();
    this.resetMatrixRenderState();
  }

  isActiveMatrixConfigCurrent() {
    if (!this._activeMatrixConfigJson) return false;
    try {
      return JSON.stringify(this.buildMatrixConfig()) === this._activeMatrixConfigJson;
    } catch (error) {
      return false;
    }
  }

  buildMatrixConfig() {
    return {
      objectApiName: this.objectApiName,
      parentId: this.recordId ?? null,

      rowGroupFields: this._localRowGroupFields.map((key) => {
        const col = this.columns.find((c) => c.key === key);
        return {
          fieldApiName: col ? col.soqlFieldPath || col.fieldName : key,
          granularity: this._dateGranularityMap[key] || null,
          label: col ? col.label : key
        };
      }),

      colGroupFields: this._localColumnGroupFields.map((key) => {
        const col = this.columns.find((c) => c.key === key);
        return {
          fieldApiName: col ? col.soqlFieldPath || col.fieldName : key,
          granularity: this._dateGranularityMap[key] || null,
          label: col ? col.label : key
        };
      }),

      summaryFields: this._localSummaryFields.map((key) => {
        let aggFunc = "SUM";
        if (key === "_recordCount") aggFunc = "COUNT";
        else if (String(this._localAggregateType).toUpperCase() === "COUNT")
          aggFunc = "COUNT";
        else aggFunc = String(this._localAggregateType).toUpperCase();

        const col = this.columns.find((c) => c.key === key);
        if (col && key !== "_recordCount") {
          const dt = String(col.dataType || "").toUpperCase();
          const isNumeric =
            col.isNumber ||
            col.isCurrency ||
            [
              "NUMBER",
              "CURRENCY",
              "PERCENT",
              "PERCENTAGE",
              "DOUBLE",
              "INTEGER",
              "LONG",
              "DECIMAL"
            ].includes(dt);
          const isDate =
            col.isDate || col.isDateTime || ["DATE", "DATETIME"].includes(dt);
          if (!isNumeric) {
            if (
              isDate &&
              (aggFunc === "MIN" ||
                aggFunc === "MAX" ||
                aggFunc === "MINIMUM" ||
                aggFunc === "MAXIMUM")
            ) {
              // MIN/MAX allowed for Dates
            } else {
              aggFunc = "COUNT";
            }
          }
        }

        const fieldName =
          key === "_recordCount"
            ? "Id"
            : col
              ? col.soqlFieldPath || col.fieldName
              : key;

        return {
          fieldApiName: fieldName,
          aggregateFunction: aggFunc,
          label: col ? col.label : key === "_recordCount" ? "Record Count" : key
        };
      }),

      filters: this._buildExportFilterConfigs(),
      logic: this._filterPayload?.logic || "AND",
      customLogic: this._filterPayload?.customLogic || "",
      previewRowLimit: this._matrixPreviewRowLimit,
      includeSubtotals: true
    };
  }

  async applyMatrixResult(result) {
    result.rowFieldLabels = result.rowFieldLabels || [];
    result.colFieldLabels = result.colFieldLabels || [];

    this.matrixColHeaders = this.buildColHeaders(
      result.colKeys,
      result.colFieldLabels,
      result.summaryLabels
    );

    this.matrixRows = await this.buildMatrixRows(result);
    this.initVirtualScroll(this.matrixRows);
    this.matrixResult = result;
    this.matrixDraftDirty = false;
  }

  async applyMatrixResponse(response) {
    const status = response?.status || "READY";
    this.matrixRequestStatus = status;
    this.matrixJobId = response?.jobId || "";
    this.matrixProgress = response?.progress || 0;
    this.matrixProcessingMessage = response?.message || "";

    if (response?.message && response.message.startsWith("MATRIX_DETAIL_FALLBACK:")) {
      const parts = response.message.split(":");
      this._matrixLimitExceeded = true;
      this._matrixLimitCount = parts[1] || "50000";
    }

    if (status === "READY" && response?.matrixResult) {
      await this.applyMatrixResult(response.matrixResult);
      return;
    }

    if (status === "FAILED") {
      throw new Error(response?.message || "Matrix request failed");
    }

    if (status === "QUEUED" || status === "PROCESSING") {
      this.matrixLoadingLabel =
        status === "QUEUED" ? "Queued..." : "Processing...";
      this.startMatrixJobPolling();
      return;
    }

    throw new Error(response?.message || "Matrix response was incomplete");
  }

  handleMatrixRequestError(error) {
    this.stopMatrixJobPolling();
    const msg = error?.body?.message ?? error?.message ?? "Matrix load failed";
    if (msg && msg.startsWith("MATRIX_DETAIL_FALLBACK:")) {
      const parts = msg.split(":");
      this._matrixLimitExceeded = true;
      this._matrixLimitCount = parts[1] || "50000";
      this.matrixError = null;
    } else {
      this._matrixLimitExceeded = false;
      this.matrixError = msg;
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Matrix Error",
          message: msg,
          variant: "error"
        })
      );
    }
  }

  handleGenerateMatrix() {
    if (this.isGenerateMatrixDisabled) return;
    if (this.matrixResult && this.matrixDraftDirty) {
      this.matrixLoadingLabel = "Regenerating...";
    } else if (this.matrixResult) {
      this.matrixLoadingLabel = "Refreshing...";
    } else {
      this.matrixLoadingLabel = "Generating...";
    }
    this.handleMatrixModeActivated();
  }

  waitForMatrixLoadingDelay(startedAt) {
    const remaining =
      DynamicMetaTable.MATRIX_MIN_LOADING_MS - (Date.now() - startedAt);
    if (remaining <= 0) {
      return Promise.resolve();
    }

    return new Promise((resolve) => {
      // Keep the Matrix skeleton visible long enough for users to notice state change.
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      setTimeout(resolve, remaining);
    });
  }

  async handleMatrixModeActivated() {
    const loadingStartedAt = Date.now();
    this.matrixLoading = true;
    this.matrixError = null;
    this._matrixLimitExceeded = false;
    this._matrixLimitCount = "";
    this.matrixRequestStatus = "REQUESTING";
    this.matrixJobId = "";
    this.matrixProgress = 0;
    this.matrixProcessingMessage = "";
    this.stopMatrixJobPolling();
    this.resetMatrixRenderState();

    try {
      const matrixConfig = this.buildMatrixConfig();
      this._activeMatrixConfigJson = JSON.stringify(matrixConfig);
      const response = {
        ...(await requestMatrixData({
          tableId: this.tableId,
          parentId: this.recordId ?? null,
          matrixConfigJson: this._activeMatrixConfigJson
        }))
      };

      await this.applyMatrixResponse(response);
    } catch (error) {
      this.handleMatrixRequestError(error);
    } finally {
      await this.waitForMatrixLoadingDelay(loadingStartedAt);
      this.matrixLoading = false;
    }
  }

  startMatrixJobPolling() {
    if (!this.matrixJobId) return;
    this.stopMatrixJobPolling();

    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this._matrixPollTimer = setInterval(() => {
      this.pollMatrixJob();
    }, 2500);
  }

  stopMatrixJobPolling() {
    if (this._matrixPollTimer) {
      clearInterval(this._matrixPollTimer);
      this._matrixPollTimer = null;
    }
  }

  async pollMatrixJob() {
    if (!this.matrixJobId) {
      this.stopMatrixJobPolling();
      return;
    }

    try {
      const status = await getMatrixJobStatus({ jobId: this.matrixJobId });
      this.matrixRequestStatus = status?.status || this.matrixRequestStatus;
      this.matrixProgress = status?.progress || 0;
      this.matrixProcessingMessage =
        status?.message || this.matrixProcessingMessage;

      if (this.matrixRequestStatus === "COMPLETED") {
        this.stopMatrixJobPolling();
        const result = await getMatrixJobResult({ jobId: this.matrixJobId });
        if (!this.isActiveMatrixConfigCurrent()) {
          this.matrixDraftDirty = true;
          this.matrixLoading = false;
          this.matrixProcessingMessage =
            "Matrix generation completed, but the matrix setup changed. Generate again.";
          return;
        }
        await this.applyMatrixResult({ ...result });
        this.matrixLoading = false;
        this.matrixProcessingMessage = "Matrix generation completed.";
        return;
      }

      if (
        this.matrixRequestStatus === "FAILED" ||
        this.matrixRequestStatus === "EXPIRED" ||
        this.matrixRequestStatus === "NOT_FOUND"
      ) {
        this.stopMatrixJobPolling();
        this.matrixLoading = false;
        this.matrixError =
          this.matrixProcessingMessage || "Matrix generation failed.";
      }
    } catch (error) {
      this.stopMatrixJobPolling();
      this.matrixLoading = false;
      this.handleMatrixRequestError(error);
    }
  }

  async handleEmailMatrixReport() {
    this.matrixLoading = true;
    try {
      const aggField =
        this._localSummaryFields.length > 0 &&
        this._localSummaryFields[0] !== "_recordCount"
          ? this._localSummaryFields[0]
          : "_recordCount";
      const matrixParamsJson = JSON.stringify({
        rowFields: this._rowGroupFields,
        columnFields: this._columnGroupFields,
        aggregateField: aggField,
        aggregateFields: this._localSummaryFields,
        granularityMap: this._dateGranularityMap
      });

      await exportTableViaEmail({
        tableName: this.tableName,
        parentId: this.parentIdParam,
        filtersJson: this._filterPayload
          ? JSON.stringify(this._filterPayload)
          : "",
        matrixParamsJson: matrixParamsJson,
        searchTerm: this._searchKey ?? "",
        columnKeysJson: JSON.stringify(this.columns.map((col) => col.key))
      });

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Export started",
          message:
            "The matrix export is processing in the background. An email with download links will be sent upon completion.",
          variant: "success"
        })
      );
    } catch (error) {
      const msg = error?.body?.message ?? error?.message ?? "Unknown error";
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Export failed",
          message: msg,
          variant: "error",
          mode: "sticky"
        })
      );
    } finally {
      this.matrixLoading = false;
    }
  }

  formatMatrixLabel(label, fieldKey) {
    if (!label || label === "(blank)") return label;
    const col = this.columns?.find((c) => c.key === fieldKey);
    const dt = String(col?.dataType || "").toUpperCase();
    if (
      col &&
      (col.isDate || col.isDateTime || ["DATE", "DATETIME"].includes(dt))
    ) {
      const granularity = this._dateGranularityMap[fieldKey] || "";
      if (granularity === "") {
        const dMatch = label.match(/^(\d{4})-(\d{2})-(\d{2})/);
        if (dMatch) {
          return `${dMatch[3]}/${dMatch[2]}/${dMatch[1]}`;
        }
      }
    }
    return label;
  }

  _parseMatrixDateString(str, key) {
    if (!str || str === "(blank)") return null;
    const granularity = this._dateGranularityMap[key] || "";
    if (granularity === "CALENDAR_YEAR") {
      const year = parseInt(str, 10);
      return isNaN(year) ? null : new Date(year, 0, 1);
    }
    if (granularity === "CALENDAR_MONTH") {
      const parts = str.split(" ");
      const monthNames = [
        "Jan",
        "Feb",
        "Mar",
        "Apr",
        "May",
        "Jun",
        "Jul",
        "Aug",
        "Sep",
        "Oct",
        "Nov",
        "Dec"
      ];
      const mIdx = monthNames.indexOf(parts[0]);
      const year = parseInt(parts[1], 10);
      if (mIdx !== -1 && !isNaN(year)) {
        return new Date(year, mIdx, 1);
      }
    }
    if (granularity === "CALENDAR_QUARTER") {
      const parts = str.split(" ");
      const q = parseInt(parts[0].replace("Q", ""), 10);
      const year = parseInt(parts[1], 10);
      if (!isNaN(q) && !isNaN(year)) {
        return new Date(year, (q - 1) * 3, 1);
      }
    }
    if (str.includes("/")) {
      const parts = str.split("/");
      if (parts.length === 3) {
        const d = parseInt(parts[0], 10);
        const m = parseInt(parts[1], 10);
        const y = parseInt(parts[2], 10);
        if (!isNaN(d) && !isNaN(m) && !isNaN(y)) {
          return new Date(y, m - 1, d);
        }
      }
    }
    const parsed = new Date(str);
    return isNaN(parsed.getTime()) ? null : parsed;
  }

  async buildMatrixRows(result) {
    const cellMap = {};
    const subtotalTotals = {};
    const grandTotals = {};
    for (const cell of result.cells) {
      const rowKey = this.normalizeMatrixKey(cell.rowKey);
      const colKey = this.normalizeMatrixKey(cell.colKey);
      if (!cellMap[rowKey]) cellMap[rowKey] = {};
      if (!cellMap[rowKey][colKey]) cellMap[rowKey][colKey] = {};
      cellMap[rowKey][colKey][cell.alias] = cell.value;
      if (cell.value !== null && cell.value !== undefined) {
        const topGroup = rowKey.split("|")[0] || "";
        if (!subtotalTotals[topGroup]) subtotalTotals[topGroup] = {};
        if (!subtotalTotals[topGroup][colKey])
          subtotalTotals[topGroup][colKey] = {};
        subtotalTotals[topGroup][colKey][cell.alias] =
          (subtotalTotals[topGroup][colKey][cell.alias] || 0) +
          Number(cell.value);

        if (!grandTotals[colKey]) grandTotals[colKey] = {};
        grandTotals[colKey][cell.alias] =
          (grandTotals[colKey][cell.alias] || 0) + Number(cell.value);
      }
    }

    const rows = [];
    let prevRowParts = [];
    const includePreviewSubtotals = !result.isPreviewTruncated;

    for (const rowParts of result.rowKeys) {
      const rowKey = this.normalizeMatrixKey(rowParts.join("|"));

      if (
        includePreviewSubtotals &&
        result.rowKeys.length > 1 &&
        prevRowParts.length > 0 &&
        prevRowParts[0] !== rowParts[0]
      ) {
        rows.push(this.buildSubtotalRow(prevRowParts[0], result, subtotalTotals));
        await this.yieldMatrixRenderChunk();
      }

      const rowCells = [];
      for (const colParts of result.colKeys) {
        const colKey = this.normalizeMatrixKey(colParts.join("|"));
        for (const alias of result.summaryAliases) {
          const val = cellMap[rowKey]?.[colKey]?.[alias] ?? null;
          rowCells.push({
            key: `${rowKey}__${colKey}__${alias}`,
            value: val !== null ? this.formatCellValue(val) : "",
            raw: val,
            isEmpty: val === null,
            cellClass: "data-cell"
          });
        }
      }

      const tabularLabels = [];
      for (let i = 0; i < result.rowFieldLabels.length; i++) {
        const currentPart = rowParts[i];
        let isSameAsPrev = false;

        if (prevRowParts.length > 0) {
          isSameAsPrev = true;
          for (let j = 0; j <= i; j++) {
            if (rowParts[j] !== prevRowParts[j]) {
              isSameAsPrev = false;
              break;
            }
          }
        }

        let text = "";
        if (!isSameAsPrev && currentPart) {
          const fieldKey = this._localRowGroupFields[i];
          text = this.formatMatrixLabel(currentPart, fieldKey);
        }

        let isCollapsible = false;
        if (
          i === rowParts.length - 1 &&
          i < result.rowFieldLabels.length - 1 &&
          !isSameAsPrev
        ) {
          isCollapsible = true;
        }

        tabularLabels.push({
          key: `tabLbl_${i}`,
          text: text,
          isCollapsible: isCollapsible,
          style: `flex: 0 0 150px; padding: 6px 12px; border-right: 1px solid #e0e0e0; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; display: flex; align-items: center;`
        });
      }

      const indentLevel = rowParts.length - 1;
      rows.push({
        key: rowKey,
        labelParts: rowParts,
        label: rowParts[rowParts.length - 1],
        tabularLabels: tabularLabels,
        indentLevel: indentLevel,
        indentStyle: `padding-left: ${indentLevel * 16 + 8}px;`,
        isSubtotal: false,
        isCollapsible: indentLevel < result.rowFieldLabels.length - 1,
        collapseIcon: "utility:chevrondown",
        cells: rowCells,
        rowClass: "matrix-data-row"
      });

      prevRowParts = rowParts;
      if (rows.length % 200 === 0) {
        await this.yieldMatrixRenderChunk();
      }
    }

    if (
      includePreviewSubtotals &&
      prevRowParts.length > 0 &&
      result.rowKeys.length > 1
    ) {
      rows.push(this.buildSubtotalRow(prevRowParts[0], result, subtotalTotals));
    }

    rows.push(this.buildGrandTotalRow(result, grandTotals));
    return rows;
  }

  yieldMatrixRenderChunk() {
    return new Promise((resolve) => {
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      setTimeout(resolve, 0);
    });
  }

  normalizeMatrixKey(value) {
    return value === null || value === undefined ? "" : String(value);
  }

  buildColHeaders(colKeys, colFieldLabels, summaryLabels) {
    if (!colKeys || colKeys.length === 0) return [];
    const depth = colKeys[0].length;
    const headerRows = [];
    const summaryCount = Math.max(1, summaryLabels?.length ?? 0);

    for (let level = 0; level < depth; level++) {
      const headerRow = [];
      const fieldKey = this._localColumnGroupFields[level];
      let i = 0;
      while (i < colKeys.length) {
        const currentVal = colKeys[i][level];
        const displayLabel = this.formatMatrixLabel(currentVal, fieldKey);
        let colspan = 1;
        while (
          i + colspan < colKeys.length &&
          colKeys[i + colspan][level] === currentVal &&
          this.upperLevelsMatch(colKeys[i], colKeys[i + colspan], level)
        ) {
          colspan++;
        }
        headerRow.push({
          key: `h_${level}_${i}`,
          label: displayLabel,
          colspan: colspan * summaryCount,
          isFirst: i === 0,
          fieldLabel: colFieldLabels?.[level] ?? ""
        });
        i += colspan;
      }
      headerRows.push(headerRow);
    }

    if (summaryLabels && summaryLabels.length > 0) {
      const summaryRow = [];
      for (let i = 0; i < colKeys.length; i++) {
        for (let j = 0; j < summaryLabels.length; j++) {
          summaryRow.push({
            key: `sum_${i}_${j}`,
            label: summaryLabels[j],
            colspan: 1,
            isFirst: i === 0 && j === 0,
            fieldLabel: "Summary"
          });
        }
      }
      headerRows.push(summaryRow);
    }

    return headerRows;
  }

  upperLevelsMatch(keyA, keyB, belowLevel) {
    for (let l = 0; l < belowLevel; l++) {
      if (keyA[l] !== keyB[l]) return false;
    }
    return true;
  }

  buildSubtotalRow(topLevelGroupValue, result, subtotalTotals) {
    const subCells = [];
    for (const colParts of result.colKeys) {
      const colKey = this.normalizeMatrixKey(colParts.join("|"));
      for (const alias of result.summaryAliases) {
        const total = subtotalTotals?.[topLevelGroupValue]?.[colKey]?.[alias];
        const hasValue = total !== null && total !== undefined;
        subCells.push({
          key: `sub_${topLevelGroupValue}__${colKey}__${alias}`,
          value: hasValue ? this.formatCellValue(total) : "",
          raw: hasValue ? total : null,
          isEmpty: !hasValue,
          cellClass: "data-cell subtotal-cell"
        });
      }
    }

    const tabularLabels = [];
    for (let i = 0; i < result.rowFieldLabels.length; i++) {
      tabularLabels.push({
        key: `sub_tabLbl_${i}`,
        text: i === 0 ? `${topLevelGroupValue} Total` : "",
        style: `flex: 0 0 150px; padding: 6px 12px; border-right: 1px solid #e0e0e0; font-weight: 600; background: #eef2ff; display: flex; align-items: center;`
      });
    }

    return {
      key: `subtotal_${topLevelGroupValue}`,
      label: `${topLevelGroupValue} Total`,
      tabularLabels: tabularLabels,
      indentLevel: 0,
      isSubtotal: true,
      cells: subCells,
      rowClass: "matrix-subtotal-row"
    };
  }

  buildGrandTotalRow(result, grandTotals) {
    const gtCells = [];
    const backendGrandTotals = {};
    (result.grandTotalCells || []).forEach((cell) => {
      if (!cell) return;
      const colKey = this.normalizeMatrixKey(cell.colKey);
      if (!backendGrandTotals[colKey]) backendGrandTotals[colKey] = {};
      backendGrandTotals[colKey][cell.alias] = cell.value;
    });

    for (const colParts of result.colKeys) {
      const colKey = this.normalizeMatrixKey(colParts.join("|"));
      for (const alias of result.summaryAliases) {
        const hasBackendTotal =
          backendGrandTotals[colKey] &&
          Object.prototype.hasOwnProperty.call(backendGrandTotals[colKey], alias);
        const total = hasBackendTotal
          ? backendGrandTotals[colKey][alias]
          : grandTotals?.[colKey]?.[alias];
        const hasValue = total !== null && total !== undefined;
        gtCells.push({
          key: `grand__${colKey}__${alias}`,
          value: hasValue ? this.formatCellValue(total) : "",
          raw: hasValue ? total : null,
          isEmpty: !hasValue,
          cellClass: "data-cell grandtotal-cell"
        });
      }
    }

    const tabularLabels = [];
    for (let i = 0; i < result.rowFieldLabels.length; i++) {
      tabularLabels.push({
        key: `gt_tabLbl_${i}`,
        text: i === 0 ? `Grand Total` : "",
        style: `flex: 0 0 150px; padding: 6px 12px; border-right: 1px solid #e0e0e0; font-weight: 700; background: #e8f0fe; display: flex; align-items: center;`
      });
    }

    return {
      key: "grand_total",
      label: "Grand Total",
      tabularLabels: tabularLabels,
      indentLevel: 0,
      isSubtotal: false,
      isGrandTotal: true,
      cells: gtCells,
      rowClass: "matrix-grand-total-row"
    };
  }

  formatCellValue(val) {
    if (val === null || val === undefined) return "";
    const num = Number(val);
    if (isNaN(num)) return String(val);
    return new Intl.NumberFormat("en-IN", {
      minimumFractionDigits: 0,
      maximumFractionDigits: 2
    }).format(num);
  }

  // ============================================================
  // VIRTUAL SCROLL GETTERS & HELPERS
  // ============================================================

  get spacerTopStyle() {
    return `height: ${this.vsSpacerTopPx}px;`;
  }

  get spacerBotStyle() {
    return `height: ${this.vsSpacerBotPx}px;`;
  }

  get virtualTotalHeightStyle() {
    return `min-height: ${this.vsTotalHeight}px; position: relative;`;
  }

  get skeletonRows() {
    return Array.from({ length: 8 }, (_, i) => ({ key: `skel_${i}` }));
  }

  get matrixColHeadersLevel0() {
    return this.matrixColHeaders?.[0] ?? [];
  }

  get matrixColHeadersDeep() {
    if (!this.matrixColHeaders || this.matrixColHeaders.length <= 1) return [];

    return this.matrixColHeaders.slice(1).map((headerRow, idx) => ({
      key: `deep_level_${idx + 1}`,
      fieldLabel:
        this.matrixResult?.colFieldLabels?.[idx + 1] ??
        (idx === this.matrixColHeaders.length - 2 ? "Summary" : ""),
      headers: headerRow
    }));
  }

  get matrixTableColumnCount() {
    const colCount = this.matrixResult?.colKeys?.length || 1;
    const summaryCount = this.matrixResult?.summaryAliases?.length || 1;
    return 1 + colCount * summaryCount;
  }

  get enrichedVsRows() {
    if (!this.vsRows) return [];

    return this.vsRows.map((row) => {
      const isCollapsible = this._vsEngine
        ? this._vsEngine._rowHasChildren(row)
        : false;

      const isCollapsed = this._vsEngine?.isCollapsed(row.key) ?? false;

      return {
        ...row,
        rowClass: this._buildRowClass(row),
        labelCellStyle: `padding-left: ${(row.indentPx ?? 0) + 12}px;`,
        ariaLevel: (row.indentLevel ?? 0) + 1,
        isCollapsible,
        collapseIcon: isCollapsed
          ? "utility:chevronright"
          : "utility:chevrondown",

        cells: row.cells?.map((cell) => ({
          ...cell,
          cellClass: this._buildCellClass(cell, row),
          rawTitle:
            cell.raw !== null && cell.raw !== undefined ? String(cell.raw) : ""
        }))
      };
    });
  }

  _buildRowClass(row) {
    const classes = ["matrix-data-row"];
    if (row.isSubtotal) classes.push("matrix-subtotal-row");
    if (row.isGrandTotal) classes.push("matrix-grand-total-row");
    if ((row.indentLevel ?? 0) === 0 && !row.isSubtotal && !row.isGrandTotal) {
      classes.push("matrix-top-group-row");
    }
    return classes.join(" ");
  }

  _buildCellClass(cell, row) {
    const classes = ["matrix-data-cell"];
    if (cell.isEmpty) classes.push("matrix-cell-empty");
    if (row.isSubtotal) classes.push("matrix-subtotal-cell");
    if (row.isGrandTotal) classes.push("matrix-grand-total-cell");
    return classes.join(" ");
  }

  handleMatrixKeyDown(event) {
    if (!this._scrollContainer) return;

    const ROW_H = MatrixVirtualScroll.ROW_HEIGHT_PX;
    const PAGE = MatrixVirtualScroll.VIEWPORT_HEIGHT_PX;

    const scrollMap = {
      ArrowDown: ROW_H,
      ArrowUp: -ROW_H,
      PageDown: PAGE,
      PageUp: -PAGE,
      Home: -Infinity,
      End: Infinity
    };

    const delta = scrollMap[event.key];
    if (delta === undefined) return;

    event.preventDefault();

    if (delta === -Infinity) {
      this._scrollContainer.scrollTop = 0;
    } else if (delta === Infinity) {
      this._scrollContainer.scrollTop = this.vsTotalHeight;
    } else {
      this._scrollContainer.scrollTop += delta;
    }
  }

  get matrixStatusText() {
    if (this.matrixLoading) return "Loading...";
    if (!this.matrixResult && !this.vsTotalCount) return "";

    const groupedRows = this.matrixResult?.totalMatrixRowCount || 0;
    const previewRows = this.matrixResult?.rowKeys?.length || 0;
    const renderedRows = this.vsTotalCount || 0;
    const totalCells = this.matrixResult?.totalCellCount || 0;
    const parts = [];

    if (groupedRows) {
      parts.push(`${groupedRows.toLocaleString("en-IN")} grouped rows`);
    }
    if (previewRows && previewRows !== groupedRows) {
      parts.push(`${previewRows.toLocaleString("en-IN")} preview rows`);
    }
    if (renderedRows && renderedRows !== previewRows) {
      parts.push(`${renderedRows.toLocaleString("en-IN")} rendered rows incl. totals`);
    }
    if (totalCells) {
      parts.push(`${totalCells.toLocaleString("en-IN")} distinct cells`);
    }
    if (this.matrixResult?.isPreviewTruncated) {
      parts.push("preview truncated");
    }

    return parts.length ? parts.join(" | ") : "";
  }

  get hasMoreRowsThanWindow() {
    return this.vsRows?.length < this.vsTotalCount;
  }

  // Virtual Browse Support
  handleTableScroll(event) {
    if (this._isVirtualMode) {
      const viewport = this.template.querySelector("c-virtual-table-viewport");
      if (viewport) {
        viewport.handleParentScroll(
          event.target.scrollTop,
          event.target.scrollHeight,
          event.target.clientHeight
        );
      }
    }
  }
}