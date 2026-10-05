import { LightningElement, api, track } from 'lwc';

export default class SdtMultiSelect extends LightningElement {
    @api label = '';
    @api placeholder = 'Select options...';
    
    @track _options = [];
    @track _value = []; // Array of selected values
    
    @api
    get options() {
        return this._options;
    }
    set options(val) {
        this._options = val ? JSON.parse(JSON.stringify(val)) : [];
        this.updateSelectionState();
    }
    
    @api
    get value() {
        return this._value.join(';');
    }
    set value(val) {
        if (typeof val === 'string') {
            this._value = val ? val.split(';') : [];
        } else if (Array.isArray(val)) {
            this._value = [...val];
        } else {
            this._value = [];
        }
        this.updateSelectionState();
    }
    
    @track isOpen = false;
    @track searchTerm = '';
    
    get filteredOptions() {
        if (!this.searchTerm) return this._options;
        const term = this.searchTerm.toLowerCase();
        return this._options.filter(o => o.label.toLowerCase().includes(term));
    }
    
    get hasFilteredOptions() {
        return this.filteredOptions.length > 0;
    }
    
    get selectedOptions() {
        return this._options.filter(o => o.selected);
    }
    
    get selectedCount() {
        return this.selectedOptions.length;
    }
    
    get hasSelection() {
        return this.selectedCount > 0;
    }
    
    get visiblePills() {
        // Show up to 1 pill to save space, rest as +X
        return this.selectedOptions.slice(0, 1);
    }
    
    get overflowCount() {
        const diff = this.selectedCount - 1;
        return diff > 0 ? diff : 0;
    }
    
    // --- Actions ---
    
    toggleDropdown() {
        this.isOpen = !this.isOpen;
        if (this.isOpen) {
            this.searchTerm = '';
        }
    }
    
    closeDropdown(event) {
        if (event) {
            event.stopPropagation();
        }
        this.isOpen = false;
        this.dispatchChangeEvent();
    }
    
    handleSearch(event) {
        this.searchTerm = event.target.value;
    }
    
    handleCheckboxChange(event) {
        const val = event.target.value;
        const checked = event.target.checked;
        
        const opt = this._options.find(o => o.value === val);
        if (opt) {
            opt.selected = checked;
        }
        this.updateValueArray();
    }
    
    removePill(event) {
        event.stopPropagation();
        const val = event.currentTarget.dataset.val;
        const opt = this._options.find(o => o.value === val);
        if (opt) {
            opt.selected = false;
            this.updateValueArray();
            this.dispatchChangeEvent();
        }
    }
    
    selectAllVisible() {
        this.filteredOptions.forEach(o => {
            o.selected = true;
        });
        this.updateValueArray();
    }
    
    clearSelections() {
        this._options.forEach(o => {
            o.selected = false;
        });
        this.updateValueArray();
    }
    
    // --- Internals ---
    
    updateSelectionState() {
        if (this._options) {
            this._options.forEach(o => {
                o.selected = this._value.includes(o.value);
            });
        }
    }
    
    updateValueArray() {
        this._value = this._options.filter(o => o.selected).map(o => o.value);
    }
    
    dispatchChangeEvent() {
        this.dispatchEvent(new CustomEvent('change', {
            detail: { value: this.value }
        }));
    }
}