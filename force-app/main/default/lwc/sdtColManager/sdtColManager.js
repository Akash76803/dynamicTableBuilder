import { LightningElement, api, track } from 'lwc';

const STORAGE_PREFIX = 'sdt_cols_';

export default class SdtColManager extends LightningElement {

    /** All column definitions from parent (SimpleTableDTO.ColumnDef[]) */
    @api columns = [];

    /** tableName — used as localStorage key suffix */
    @api tableName = '';

    @track localColumns = [];

    // ─── Lifecycle ────────────────────────────────────────────────────────────

    connectedCallback() {
        this._initFromColumnsAndStorage();
    }

    /** Reinitialize whenever parent passes new columns */
    @api
    refreshColumns() {
        this._initFromColumnsAndStorage();
    }

    // ─── Init ─────────────────────────────────────────────────────────────────

    _initFromColumnsAndStorage() {
        const saved = this._loadFromStorage();

        let cols = (this.columns || []).map(col => ({
            key:     col.key,
            label:   col.label,
            visible: true,  // default visible
        }));

        // Apply saved order + visibility if available and keys match
        if (saved && saved.length > 0) {
            const savedKeys = saved.map(s => s.key);
            const allKeysMatch = cols.every(c => savedKeys.includes(c.key));
            if (allKeysMatch) {
                // Reorder by saved order
                const keyMap = {};
                cols.forEach(c => { keyMap[c.key] = c; });
                cols = saved
                    .filter(s => keyMap[s.key])
                    .map(s => ({ ...keyMap[s.key], visible: s.visible }));
            }
        }

        this.localColumns = this._withFirstLast(cols);
    }

    // ─── Computed ─────────────────────────────────────────────────────────────

    _withFirstLast(cols) {
        return cols.map((c, i) => ({
            ...c,
            isFirst: i === 0,
            isLast:  i === cols.length - 1,
        }));
    }

    // ─── Handlers ─────────────────────────────────────────────────────────────

    handleMoveUp(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        if (idx <= 0) return;
        const cols = [...this.localColumns];
        [cols[idx - 1], cols[idx]] = [cols[idx], cols[idx - 1]];
        this.localColumns = this._withFirstLast(cols);
    }

    handleMoveDown(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        if (idx >= this.localColumns.length - 1) return;
        const cols = [...this.localColumns];
        [cols[idx], cols[idx + 1]] = [cols[idx + 1], cols[idx]];
        this.localColumns = this._withFirstLast(cols);
    }

    handleVisibilityToggle(event) {
        const key     = event.currentTarget.dataset.key;
        const checked = event.target.checked;
        this.localColumns = this.localColumns.map(c =>
            c.key === key ? { ...c, visible: checked } : c
        );
    }

    handleApply() {
        this._saveToStorage();
        // Fire event: array of { key, visible } in user-preferred order
        this.dispatchEvent(new CustomEvent('columnupdate', {
            detail:  this.localColumns.map(c => ({ key: c.key, visible: c.visible })),
            bubbles: true,
        }));
    }

    handleReset() {
        this._clearStorage();
        this._initFromColumnsAndStorage();
        // Fire reset with original order, all visible
        this.dispatchEvent(new CustomEvent('columnupdate', {
            detail:  this.localColumns.map(c => ({ key: c.key, visible: true })),
            bubbles: true,
        }));
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close', { bubbles: true }));
    }

    // ─── localStorage ─────────────────────────────────────────────────────────

    _storageKey() {
        return STORAGE_PREFIX + (this.tableName || 'default');
    }

    _saveToStorage() {
        try {
            const payload = this.localColumns.map(c => ({ key: c.key, visible: c.visible }));
            localStorage.setItem(this._storageKey(), JSON.stringify(payload));
        } catch (e) { /* storage might be blocked */ }
    }

    _loadFromStorage() {
        try {
            const raw = localStorage.getItem(this._storageKey());
            return raw ? JSON.parse(raw) : null;
        } catch (e) {
            return null;
        }
    }

    _clearStorage() {
        try { localStorage.removeItem(this._storageKey()); } catch (e) { }
    }
}
