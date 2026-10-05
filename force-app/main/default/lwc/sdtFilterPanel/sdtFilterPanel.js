import { LightningElement, api, track } from 'lwc';

// Operators per data type
const TYPE_OPERATORS = {
    text:     [{ label: 'Contains',        value: 'contains'      },
               { label: 'Equals',          value: 'equals'        },
               { label: 'Not Equals',      value: 'not_equals'    },
               { label: 'Starts With',     value: 'starts_with'   },
               { label: 'Is Blank',        value: 'is_blank'      },
               { label: 'Is Not Blank',    value: 'is_not_blank'  }],
    number:   [{ label: 'Equals',          value: 'equals'        },
               { label: 'Greater Than',    value: 'greater_than'  },
               { label: 'Less Than',       value: 'less_than'     },
               { label: 'Between',         value: 'between'       },
               { label: 'Is Blank',        value: 'is_blank'      }],
    currency: [{ label: 'Equals',          value: 'equals'        },
               { label: 'Greater Than',    value: 'greater_than'  },
               { label: 'Less Than',       value: 'less_than'     },
               { label: 'Between',         value: 'between'       }],
    percent:  [{ label: 'Equals',          value: 'equals'        },
               { label: 'Greater Than',    value: 'greater_than'  },
               { label: 'Less Than',       value: 'less_than'     },
               { label: 'Between',         value: 'between'       }],
    percentage:  [{ label: 'Equals',          value: 'equals'        },
               { label: 'Greater Than',    value: 'greater_than'  },
               { label: 'Less Than',       value: 'less_than'     },
               { label: 'Between',         value: 'between'       }],
    date:     [{ label: 'Equals',          value: 'equals'        },
               { label: 'Before',          value: 'before'        },
               { label: 'After',           value: 'after'         },
               { label: 'Between',         value: 'between'       },
               { label: 'Is Blank',        value: 'is_blank'      }],
    datetime: [{ label: 'Equals',          value: 'equals'        },
               { label: 'Before',          value: 'before'        },
               { label: 'After',           value: 'after'         },
               { label: 'Between',         value: 'between'       }],
    picklist: [{ label: 'Equals',          value: 'equals'        },
               { label: 'Not Equals',      value: 'not_equals'    },
               { label: 'In',              value: 'in'            },
               { label: 'Not In',          value: 'not_in'        }],
    multipicklist: [{ label: 'Includes',   value: 'includes'      },
                    { label: 'Excludes',   value: 'excludes'      }],
    boolean:  [{ label: 'Is True',         value: 'is_true'       },
               { label: 'Is False',        value: 'is_false'      }],
    lookup:   [{ label: 'Equals',          value: 'equals'        },
               { label: 'Not Equals',      value: 'not_equals'    },
               { label: 'Contains',        value: 'contains'      },
               { label: 'Is Blank',        value: 'is_blank'      }],
};

const RANGE_OPS   = new Set(['between']);
const NO_VAL_OPS  = new Set(['is_blank', 'is_not_blank', 'is_true', 'is_false']);

let _rowCounter = 0;
const newRow = () => ({
    id: `row-${++_rowCounter}`,
    fieldKey:        '',
    dataType:        '',
    operators:       [],
    operator:        '',
    value:           '',
    valueMin:        '',
    valueMax:        '',
    picklistOptions: [],
    inputType:       'text',
    showSingleInput: false,
    showRangeInput:  false,
    showPicklistInput: false,
});

export default class SdtFilterPanel extends LightningElement {

    /** All columns from parent — we only show filterable ones */
    @api columns = [];

    /** Currently applied filters (to pre-populate rows on re-open) */
    @api activeFilters = [];

    @track filterRows = [];

    // ─── Lifecycle ────────────────────────────────────────────────────────────

    connectedCallback() {
        // Pre-populate from activeFilters if any
        if (this.activeFilters && this.activeFilters.length > 0) {
            this.filterRows = this.activeFilters.map(f => {
                const col = this.columns.find(c => c.key === f.fieldKey);
                const dt  = col ? col.dataType.toLowerCase() : 'text';
                const row = newRow();
                row.fieldKey  = f.fieldKey;
                row.dataType  = dt;
                row.operators = TYPE_OPERATORS[dt] || TYPE_OPERATORS.text;
                row.operator  = f.operator;
                row.value     = f.value    || '';
                row.valueMin  = f.valueMin || '';
                row.valueMax  = f.valueMax || '';
                
                let selectedVals = row.value ? row.value.split(';') : [];
                if (col && col.picklistOptions) {
                    row.picklistOptions = col.picklistOptions.map(opt => ({
                        ...opt,
                        selected: selectedVals.includes(opt.value)
                    }));
                }

                this._refreshInputState(row);
                return row;
            });
        } else {
            this.filterRows = [];
        }
    }

    // ─── Computed ─────────────────────────────────────────────────────────────

    get filterableColumns() {
        return (this.columns || []).filter(c => c.filterable);
    }

    get hasFilterRows() {
        return this.filterRows.length > 0;
    }

    get noFilters() {
        return this.filterRows.length === 0;
    }

    // ─── Event Handlers ───────────────────────────────────────────────────────

    handleAddRow() {
        this.filterRows = [...this.filterRows, newRow()];
    }

    handleRemoveRow(event) {
        const id = event.currentTarget.dataset.id;
        this.filterRows = this.filterRows.filter(r => r.id !== id);
    }

    handleFieldChange(event) {
        const id       = event.currentTarget.dataset.id;
        const fieldKey = event.target.value;
        const col      = this.columns.find(c => c.key === fieldKey);
        const dt       = col ? col.dataType.toLowerCase() : 'text';

        this.filterRows = this.filterRows.map(r => {
            if (r.id !== id) return r;
            
            let picklistOptions = [];
            if (col && col.picklistOptions) {
                picklistOptions = col.picklistOptions.map(opt => ({ ...opt, selected: false }));
            }

            const updated = { ...r, fieldKey, dataType: dt,
                operators: TYPE_OPERATORS[dt] || TYPE_OPERATORS.text,
                operator: '', value: '', valueMin: '', valueMax: '',
                picklistOptions, showPicklistInput: false,
                showSingleInput: false, showRangeInput: false };
            return updated;
        });
    }

    handleOperatorChange(event) {
        const id  = event.currentTarget.dataset.id;
        const op  = event.target.value;
        this.filterRows = this.filterRows.map(r => {
            if (r.id !== id) return r;
            const updated = { ...r, operator: op };
            this._refreshInputState(updated);
            return updated;
        });
    }

    handleValueChange(event) {
        const id  = event.currentTarget.dataset.id;
        const col = event.currentTarget.dataset.col; // 'value' | 'valueMin' | 'valueMax'
        const val = event.target.value;
        this.filterRows = this.filterRows.map(r => {
            if (r.id !== id) return r;
            return { ...r, [col]: val };
        });
    }

    handleMultiSelectChange(event) {
        const id = event.currentTarget.dataset.id;
        const val = event.detail.value; // this will be the semicolon separated string
        
        this.filterRows = this.filterRows.map(r => {
            if (r.id !== id) return r;
            
            // Also update the selected state in picklistOptions so it stays in sync
            let selectedVals = val ? val.split(';') : [];
            let newOptions = [];
            if (r.picklistOptions) {
                newOptions = r.picklistOptions.map(opt => ({
                    ...opt,
                    selected: selectedVals.includes(opt.value)
                }));
            }
            
            return { ...r, picklistOptions: newOptions, value: val };
        });
    }

    handleApply() {
        // Build filter payload and fire event
        const filters = this.filterRows
            .filter(r => r.fieldKey && r.operator)
            .map(r => ({
                fieldKey: r.fieldKey,
                operator: r.operator,
                value:    r.value,
                valueMin: r.valueMin,
                valueMax: r.valueMax,
            }));

        this.dispatchEvent(new CustomEvent('filterchange', {
            detail: { logic: 'AND', filters },
            bubbles: true,
        }));
    }

    handleClear() {
        this.filterRows = [];
        this.dispatchEvent(new CustomEvent('filterchange', {
            detail: { logic: 'AND', filters: [] },
            bubbles: true,
        }));
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close', { bubbles: true }));
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    _refreshInputState(row) {
        const op = row.operator;
        const dt = row.dataType;
        const isPicklist = dt === 'picklist' || dt === 'multipicklist';
        
        row.showRangeInput  = RANGE_OPS.has(op);
        row.showPicklistInput = isPicklist && op && !NO_VAL_OPS.has(op);
        row.showSingleInput = !isPicklist && op && !RANGE_OPS.has(op) && !NO_VAL_OPS.has(op);

        row.inputType = (dt === 'date') ? 'date'
                      : (dt === 'datetime') ? 'datetime-local'
                      : (dt === 'number' || dt === 'currency' || dt === 'percent' || dt === 'percentage') ? 'number'
                      : 'text';
    }
}
