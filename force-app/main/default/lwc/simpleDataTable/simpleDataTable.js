import { LightningElement, api, wire, track } from 'lwc';
import getTableData from '@salesforce/apex/SimpleTableController.getTableData';
export default class SimpleDataTable extends LightningElement {
    
    @api tableName;
    @api recordId; // Optional, for record pages
    @api pageSize = 50; // Number of records per page

    // State
    @track columns = [];
    @track rows = [];
    @track filteredRows = [];
    @track aggregateRow = [];
    @track activeFilters = [];
    @track columnOrder = [];

    searchTerm = '';
    sortColumn = null;
    sortDirection = 'asc';
    
    // Pagination State
    currentPage = 1;
    totalPages = 1;
    totalRecords = 0;

    isLoading = true;
    error = null;

    viewMode = 'table'; // 'table' or 'card'
    showFilterPanel = false;
    showColManager = false;
    wrapText = false;
    columnWidths = {};
    _resizeState;
    _moveResize;
    _endResize;

    // ─── Data Fetching ────────────────────────────────────────────────────────
    
    _parentId = '';
    _searchTimeout;

    connectedCallback() {
        this._parentId = this.recordId || '';
        this._loadWidthPreferences();
        this.loadData();
    }

    disconnectedCallback() {
        clearTimeout(this._searchTimeout);
        this._stopResize();
    }

    loadData() {
        this.isLoading = true;
        const filtersJson = this.activeFilters.length > 0 ? JSON.stringify(this.activeFilters) : null;
        
        getTableData({
            tableName: this.tableName,
            parentId: this._parentId,
            searchTerm: this.searchTerm,
            filtersJson: filtersJson,
            sortColumn: this.sortColumn,
            sortDirection: this.sortDirection
        })
        .then(data => {
            this._processData(data);
            this.error = null;
            this.isLoading = false;
        })
        .catch(error => {
            this.error = error.body ? error.body.message : 'Unknown Apex error';
            this.isLoading = false;
        });
    }

    // ─── Data Processing ──────────────────────────────────────────────────────

    _processData(data) {
        // 1. Process Columns
        const loadedCols = data.columns || [];
        
        // Check for saved column order/visibility in localStorage
        const savedCols = this._loadColumnState();
        if (savedCols && savedCols.length === loadedCols.length) {
            const keyMap = {};
            loadedCols.forEach(c => { keyMap[c.key] = c; });
            
            this.columns = savedCols
                .filter(sc => keyMap[sc.key])
                .map(sc => ({ ...keyMap[sc.key], visible: sc.visible }));
        } else {
            // Use default order from Apex
            this.columns = loadedCols.map(c => ({ ...c, visible: true }));
        }

        // 2. Process Rows
        this.rows = (data.rows || []).map(r => {
            // Create a flat record object for the filter engine
            // where keys are col.key and values are row.fields[col.key]
            const flatRecord = { Id: r.recordId };
            Object.keys(r.fields).forEach(k => {
                flatRecord[k] = r.fields[k];
            });

            return {
                recordId: r.recordId,
                fields: r.fields,
                _flatRecord: flatRecord
            };
        });

        // 3. Apply Filters and Render
        this._applyFiltersAndFormat();
    }

    // ─── UI Getters ───────────────────────────────────────────────────────────

    get isTableView() {
        return this.viewMode === 'table';
    }

    get showTableView() {
        return this.isTableView && this.filteredRows.length > 0;
    }

    get showCardView() {
        return !this.isTableView && this.filteredRows.length > 0;
    }

    get isEmpty() {
        return this.filteredRows.length === 0;
    }

    get hasActiveFilters() {
        return this.activeFilters.length > 0;
    }

    get visibleColumns() {
        return this.columns.filter(c => c.visible).map(c => ({
            ...c,
            isSorted: this.sortColumn === c.key,
            widthStyle: `width: ${this._columnWidth(c)}px;`,
            resizeLabel: `Resize ${c.label}`,
            width: this._columnWidth(c),
            sortIcon: this.sortColumn === c.key && this.sortDirection === 'asc' ? '▲' : '▼'
        }));
    }

    get tableClass() {
        return `sdt-table ${this.wrapText ? 'sdt-table-wrap' : ''}`;
    }

    get tableStyle() {
        return `width: ${this.visibleColumns.reduce((sum, c) => sum + c.width, 0)}px;`;
    }

    get wrapLabel() { return this.wrapText ? 'Clip text' : 'Wrap text'; }

    get recordRange() {
        const start = this.totalRecords ? (this.currentPage - 1) * this.pageSize + 1 : 0;
        return `${start}–${Math.min(this.currentPage * this.pageSize, this.totalRecords)} of ${this.totalRecords} records`;
    }

    handleRefresh() { this.loadData(); }

    toggleWrapText() { this.wrapText = !this.wrapText; }

    _widthKey(col) { return col.fieldName || col.key; }

    _columnWidth(col) {
        const saved = Number(this.columnWidths[this._widthKey(col)]);
        if (Number.isFinite(saved) && saved >= 90 && saved <= 600) return saved;
        if (col.isCurrency || col.isNumber || col.isPercent) return 150;
        if (col.isDate || col.isDateTime || col.isBoolean) return 150;
        return /description/i.test(col.fieldName || col.label || '') ? 300 : 200;
    }

    _setColumnWidth(key, value) {
        const col = this.columns.find(c => c.key === key);
        if (!col) return;
        this.columnWidths = { ...this.columnWidths, [this._widthKey(col)]: Math.max(90, Math.min(600, Math.round(value))) };
    }

    handleResizeStart(event) {
        if (event.button !== undefined && event.button !== 0) return;
        event.preventDefault();
        event.stopPropagation();
        this._stopResize();
        const key = event.currentTarget.dataset.col;
        const col = this.columns.find(c => c.key === key);
        if (!col) return;
        this._resizeState = { key, x: event.clientX, width: this._columnWidth(col), pointerId: event.pointerId };
        this._moveResize = ev => {
            if (!this._resizeState || ev.pointerId !== this._resizeState.pointerId) return;
            this._setColumnWidth(key, this._resizeState.width + ev.clientX - this._resizeState.x);
        };
        this._endResize = ev => {
            if (this._resizeState && ev.pointerId === this._resizeState.pointerId) {
                this._saveWidthPreferences();
                this._stopResize();
            }
        };
        window.addEventListener('pointermove', this._moveResize);
        window.addEventListener('pointerup', this._endResize);
        window.addEventListener('pointercancel', this._endResize);
    }

    handleResizeKey(event) {
        if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
        event.preventDefault();
        event.stopPropagation();
        const col = this.columns.find(c => c.key === event.currentTarget.dataset.col);
        if (!col) return;
        this._setColumnWidth(col.key, this._columnWidth(col) + (event.key === 'ArrowRight' ? 10 : -10));
        this._saveWidthPreferences();
    }

    _stopResize() {
        if (this._moveResize) window.removeEventListener('pointermove', this._moveResize);
        if (this._endResize) {
            window.removeEventListener('pointerup', this._endResize);
            window.removeEventListener('pointercancel', this._endResize);
        }
        this._resizeState = null;
        this._moveResize = null;
        this._endResize = null;
    }

    resetColumnWidths() {
        this._stopResize();
        this.columnWidths = {};
        try { localStorage.removeItem('sdt_widths_' + (this.tableName || 'default')); } catch (e) { /* Optional browser preference. */ }
    }

    _loadWidthPreferences() {
        try {
            const saved = JSON.parse(localStorage.getItem('sdt_widths_' + (this.tableName || 'default')) || '{}');
            this.columnWidths = saved && typeof saved === 'object' && !Array.isArray(saved) ? saved : {};
        } catch (e) { this.columnWidths = {}; }
    }

    _saveWidthPreferences() {
        try { localStorage.setItem('sdt_widths_' + (this.tableName || 'default'), JSON.stringify(this.columnWidths)); } catch (e) { /* Optional browser preference. */ }
    }

    get filterBtnClass() {
        return `sdt-btn sdt-btn-icon ${this.showFilterPanel || this.hasActiveFilters ? 'active' : ''}`;
    }

    get colBtnClass() {
        return `sdt-btn sdt-btn-icon ${this.showColManager ? 'active' : ''}`;
    }

    // Pagination Getters
    get isFirstPage() {
        return this.currentPage <= 1;
    }

    get isLastPage() {
        return this.currentPage >= this.totalPages;
    }

    get paginationText() {
        return `Page ${this.currentPage} of ${this.totalPages || 1}`;
    }

    // ─── Handlers ─────────────────────────────────────────────────────────────

    toggleViewMode() {
        this.viewMode = this.viewMode === 'table' ? 'card' : 'table';
    }

    toggleFilterPanel() {
        this.showFilterPanel = !this.showFilterPanel;
        if (this.showFilterPanel) this.showColManager = false;
    }

    toggleColManager() {
        this.showColManager = !this.showColManager;
        if (this.showColManager) this.showFilterPanel = false;
    }

    // From sdtColManager
    handleColumnUpdate(event) {
        const updatedColState = event.detail; // Array of { key, visible }
        
        const keyMap = {};
        this.columns.forEach(c => { keyMap[c.key] = c; });
        
        this.columns = updatedColState.map(cs => ({
            ...keyMap[cs.key],
            visible: cs.visible
        }));
        
        this._applyFiltersAndFormat(); // Re-format rows (e.g. card cells might change)
    }

    // From sdtFilterPanel
    handleFilterChange(event) {
        const payload = event.detail; // { logic: 'AND', filters: [...] }
        this.activeFilters = payload.filters;
        this.currentPage = 1;
        this.loadData();
    }

    removeFilter(event) {
        const keyToRemove = event.currentTarget.dataset.key;
        this.activeFilters = this.activeFilters.filter(f => f.fieldKey !== keyToRemove);
        this.currentPage = 1;
        this.loadData();
    }

    clearAllFilters() {
        this.activeFilters = [];
        this.currentPage = 1;
        this.loadData();
    }

    handleSearch(event) {
        this.searchTerm = event.target.value;
        this.currentPage = 1;
        
        // Debounce search
        if (this._searchTimeout) {
            clearTimeout(this._searchTimeout);
        }
        this._searchTimeout = setTimeout(() => {
            this.loadData();
        }, 300);
    }

    handleSort(event) {
        const colKey = event.currentTarget.dataset.col;
        if (this.sortColumn === colKey) {
            // Toggle direction
            this.sortDirection = this.sortDirection === 'asc' ? 'desc' : 'asc';
        } else {
            // New column, default asc
            this.sortColumn = colKey;
            this.sortDirection = 'asc';
        }
        this.currentPage = 1;
        this.loadData();
    }

    handlePrevPage() {
        if (this.currentPage > 1) {
            this.currentPage -= 1;
            this._applyFiltersAndFormat();
        }
    }

    handleNextPage() {
        if (this.currentPage < this.totalPages) {
            this.currentPage += 1;
            this._applyFiltersAndFormat();
        }
    }

    // ─── Formatting & Filtering ───────────────────────────────────────────────

    _applyFiltersAndFormat() {
        let displayRows = this.rows;
        
        // Enrich activeFilters for UI chip display (actual filtering is now server-side)
        if (this.activeFilters.length > 0) {
            this.activeFilters = this.activeFilters.map(f => {
                const col = this.columns.find(c => c.key === f.fieldKey);
                let displayVal = f.value || '';
                if (f.valueMin && f.valueMax) displayVal = `${f.valueMin} - ${f.valueMax}`;
                
                return {
                    ...f,
                    fieldLabel: col ? col.label : f.fieldKey,
                    operatorLabel: f.operator.replace(/_/g, ' '),
                    displayValue: displayVal
                };
            });
        }

        // 1.9 Pagination Calculation
        this.totalRecords = displayRows.length;
        this.totalPages = Math.ceil(this.totalRecords / this.pageSize) || 1;
        if (this.currentPage > this.totalPages) {
            this.currentPage = this.totalPages;
        }

        // Slice for current page
        const startIndex = (this.currentPage - 1) * this.pageSize;
        const pagedRows = displayRows.slice(startIndex, startIndex + this.pageSize);

        // 2. Format for UI
        const visCols = this.visibleColumns;
        const topCardCols = visCols.slice(0, 4);

        this.filteredRows = pagedRows.map(r => {
            // Cells for table view
            const cells = visCols.map(c => ({
                key: c.key,
                value: this._formatValue(r.fields[c.key], c)
            }));

            // Cells for card view
            const cardCells = topCardCols.map(c => ({
                key: c.key,
                label: c.label,
                value: this._formatValue(r.fields[c.key], c)
            }));

            return {
                ...r,
                cells,
                cardCells
            };
        });

        // 3. Aggregate Calculation
        const aggCells = [];
        let hasAgg = false;
        visCols.forEach((c, index) => {
            if (c.aggregate && c.aggregate !== 'None') {
                hasAgg = true;
                let aggVal = 0;
                if (c.aggregate === 'Count') {
                    aggVal = displayRows.length;
                } else if (c.aggregate === 'Sum' || c.aggregate === 'Average') {
                    let sum = 0;
                    displayRows.forEach(r => {
                        const v = Number(r.fields[c.key]);
                        if (!isNaN(v)) sum += v;
                    });
                    aggVal = c.aggregate === 'Average' && displayRows.length > 0 ? sum / displayRows.length : sum;
                } else if (c.aggregate === 'Max') {
                    let max = -Infinity;
                    displayRows.forEach(r => {
                        const v = Number(r.fields[c.key]);
                        if (!isNaN(v) && v > max) max = v;
                    });
                    aggVal = max === -Infinity ? 0 : max;
                } else if (c.aggregate === 'Min') {
                    let min = Infinity;
                    displayRows.forEach(r => {
                        const v = Number(r.fields[c.key]);
                        if (!isNaN(v) && v < min) min = v;
                    });
                    aggVal = min === Infinity ? 0 : min;
                }
                aggCells.push({ key: c.key, className: '', value: this._formatValue(aggVal, c) });
            } else {
                if (index === 0 && hasAgg) {
                    aggCells.push({ key: c.key, className: 'sdt-aggregate-label', value: 'Total' });
                } else {
                    aggCells.push({ key: c.key, className: '', value: '' });
                }
            }
        });
        
        // Ensure "Total" is present if there's any aggregate
        if (hasAgg && aggCells.length > 0 && aggCells[0].value === '') {
             aggCells[0].className = 'sdt-aggregate-label';
             aggCells[0].value = 'Total';
        }

        this.aggregateRow = hasAgg ? aggCells : null;
    }

    _formatValue(val, col) {
        if (val === null || val === undefined) return '';
        if (col.isBoolean) return val ? '✓' : '✗';
        if (col.isCurrency) return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(val);
        if (col.isPercent) return new Intl.NumberFormat('en-US', { style: 'percent' }).format(val / 100);
        if (col.isDate) return new Intl.DateTimeFormat('en-US').format(new Date(val));
        if (col.isDateTime) return new Intl.DateTimeFormat('en-US', { dateStyle: 'short', timeStyle: 'short' }).format(new Date(val));
        return val;
    }

    // ─── Storage Helpers ──────────────────────────────────────────────────────

    _loadColumnState() {
        try {
            const key = 'sdt_cols_' + (this.tableName || 'default');
            const raw = localStorage.getItem(key);
            return raw ? JSON.parse(raw) : null;
        } catch (e) {
            return null;
        }
    }
}
