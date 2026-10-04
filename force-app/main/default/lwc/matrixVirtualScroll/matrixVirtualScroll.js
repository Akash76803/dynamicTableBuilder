export default class MatrixVirtualScroll {
  // ── Configuration ─────────────────────────────────────────────
  static _staticRowHeight = 36;
  static _staticViewportHeight = 400;

  static get ROW_HEIGHT_PX() {
    return MatrixVirtualScroll._staticRowHeight;
  }
  static get VIEWPORT_HEIGHT_PX() {
    return MatrixVirtualScroll._staticViewportHeight;
  }

  static get OVERSCAN_ROWS() {
    return 10;
  }

  get rowHeightPx() {
    return MatrixVirtualScroll._staticRowHeight;
  }
  set rowHeightPx(val) {
    MatrixVirtualScroll._staticRowHeight = val;
  }

  get viewportHeightPx() {
    return MatrixVirtualScroll._staticViewportHeight;
  }
  set viewportHeightPx(val) {
    MatrixVirtualScroll._staticViewportHeight = val;
  }

  overscanRows = 10;

  // ── State ─────────────────────────────────────────────────────
  _allRows = []; // Poori flat rows list (Module B se aayi)
  _windowStart = 0; // Current visible window — start index
  _windowEnd = 0; // Current visible window — end index
  _scrollTop = 0; // Last known scrollTop

  // Collapse state: rowKey → true means collapsed
  // Collapsed group ke children skip honge window mein
  _collapsedGroups = new Set();
  _expandedKeys = new Set();

  // Flattened rows — collapse apply hone ke baad
  // Yeh _allRows ka subset hai jab koi group collapse ho
  _visibleFlatRows = [];
  _childParentMap = new Map();

  // ──────────────────────────────────────────────────────────────
  // init
  // ──────────────────────────────────────────────────────────────
  init(allRows) {
    this._allRows = allRows ?? [];
    this._collapsedGroups = new Set(); // reset on new data
    this._expandedKeys = new Set();
    this._scrollTop = 0;
    this._rebuildFlatRows();
    this._recalcWindow(0);
  }

  // ──────────────────────────────────────────────────────────────
  // onScroll
  // ──────────────────────────────────────────────────────────────
  onScroll(scrollTop) {
    const prev = this._scrollTop;
    this._scrollTop = scrollTop;
    this._recalcWindow(scrollTop);

    return { changed: this._windowHasChanged(prev, scrollTop) };
  }

  // ──────────────────────────────────────────────────────────────
  // toggleGroup
  // ──────────────────────────────────────────────────────────────
  toggleGroup(groupKey) {
    if (this._collapsedGroups.has(groupKey)) {
      this._collapsedGroups.delete(groupKey);
    } else {
      this._collapsedGroups.add(groupKey);
    }
    this._rebuildFlatRows();
    this._recalcWindow(this._scrollTop);
  }

  isCollapsed(groupKey) {
    return this._collapsedGroups.has(groupKey);
  }

  _rowHasChildren(row) {
    if (!row) return false;
    return this._childParentMap.has(row.rowKey || row.key);
  }

  // ──────────────────────────────────────────────────────────────
  // getWindowSlice
  // ──────────────────────────────────────────────────────────────
  getWindowSlice() {
    if (!this._visibleFlatRows.length) {
      return {
        rows: [],
        spacerTopPx: 0,
        spacerBotPx: 0,
        totalHeight: 0,
        totalRowCount: 0,
        windowStart: 0,
        windowEnd: 0
      };
    }

    const start = Math.max(
      0,
      this._windowStart - this.overscanRows
    );
    const end = Math.min(
      this._visibleFlatRows.length,
      this._windowEnd + this.overscanRows
    );

    const visibleRows = this._visibleFlatRows.slice(start, end);
    const totalHeight =
      this._visibleFlatRows.length * this.rowHeightPx;
    const spacerTopPx = start * this.rowHeightPx;
    const spacerBotPx = Math.max(
      0,
      totalHeight - end * this.rowHeightPx
    );

    return {
      rows: visibleRows, // rendered slice
      spacerTopPx, // invisible top div height
      spacerBotPx, // invisible bottom div height
      totalHeight, // total scroll area height
      totalRowCount: this._visibleFlatRows.length,
      windowStart: start,
      windowEnd: end
    };
  }

  // ──────────────────────────────────────────────────────────────
  // PRIVATE: _rebuildFlatRows
  // ──────────────────────────────────────────────────────────────
  _rebuildFlatRows() {
    this._childParentMap = new Map();
    for (let i = 0; i < this._allRows.length; i++) {
      const row = this._allRows[i];
      if (row.parentKey) {
        this._childParentMap.set(row.parentKey, true);
      }
      const nextRow = this._allRows[i + 1];
      if (nextRow && nextRow.indentLevel > row.indentLevel) {
        this._childParentMap.set(row.rowKey || row.key, true);
      }
    }

    const flat = [];
    let skipUntilIndent = -1; // -1 = not skipping

    for (const row of this._allRows) {
      const indent = row.indentLevel ?? 0;

      if (row.isGrandTotal) {
        skipUntilIndent = -1;
        flat.push(row);
        continue;
      }

      if (skipUntilIndent >= 0) {
        if (indent > skipUntilIndent) {
          continue;
        } else {
          skipUntilIndent = -1;
        }
      }

      flat.push(row);

      if (
        !row.isSubtotal &&
        !row.isGrandTotal &&
        this._collapsedGroups.has(row.key) &&
        this._childParentMap.has(row.rowKey || row.key)
      ) {
        skipUntilIndent = indent;
      }
    }

    this._visibleFlatRows = flat;
  }

  // ──────────────────────────────────────────────────────────────
  // PRIVATE: _recalcWindow
  // ──────────────────────────────────────────────────────────────
  _recalcWindow(scrollTop) {
    const rowH = this.rowHeightPx;
    const vpH = this.viewportHeightPx;
    const totalRows = this._visibleFlatRows.length;
    const visibleRowCount = Math.max(1, Math.ceil(vpH / rowH));
    const maxStart = Math.max(0, totalRows - visibleRowCount);

    this._windowStart = Math.min(
      maxStart,
      Math.max(0, Math.floor(scrollTop / rowH))
    );
    this._windowEnd = Math.min(totalRows, this._windowStart + visibleRowCount);
  }

  // ──────────────────────────────────────────────────────────────
  // PRIVATE: _windowHasChanged
  // ──────────────────────────────────────────────────────────────
  _windowHasChanged(prevScrollTop, newScrollTop) {
    const rowH = this.rowHeightPx;
    const overscan = this.overscanRows;

    const prevStart = Math.max(0, Math.floor(prevScrollTop / rowH) - overscan);
    const newStart = Math.max(0, Math.floor(newScrollTop / rowH) - overscan);

    return prevStart !== newStart;
  }

  // ──────────────────────────────────────────────────────────────
  // Static config setters
  // ──────────────────────────────────────────────────────────────
  static setRowHeight(px) {
    MatrixVirtualScroll._staticRowHeight = px;
  }
  static setViewportHeight(px) {
    MatrixVirtualScroll._staticViewportHeight = px;
  }

  destroy() {
    this._allRows = [];
    this._visibleFlatRows = [];
    if (this._collapsedGroups) this._collapsedGroups.clear();
    if (this._expandedKeys) this._expandedKeys.clear();
  }
}