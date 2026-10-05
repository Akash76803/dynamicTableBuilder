# Dynamic Table Builder (Simple Data Table)

This repository contains the source code for a lightweight, server-driven dynamic table component for Salesforce Lightning Web Components (LWC). It dynamically renders data, supports server-side filtering, searching, and provides column configuration out of the box.

## Core Features

- **Server-Side Filtering & Searching:** 
  - Dynamic SOQL generation in the backend (`SimpleTableService.cls`).
  - Implements a 300ms debounce on search queries for optimal performance.
  - Supports operators like equals, contains, between, greater than, etc., applied at the database level.
- **Server-Side Aggregations:**
  - Dynamic `SUM`, `AVG`, `MIN`, `MAX` calculated based on the returned server-side dataset.
  - Aggregate definitions configurable per column via `Aggregate__c` picklist on the `Table_Columns__c` object.
- **Dynamic Column Configuration:**
  - Configurable UI to define visibility, order, and properties of columns.
  - Utilizes `sdtColManager` to adjust the view seamlessly.
- **Pagination & Limitations:**
  - Integrated server-side limit (`LIMIT 2000`) for robust dataset handling, preventing client-side heap issues with large lists.
- **Filter Panel UI & Multi-Select Picklists:**
  - `sdtFilterPanel` component for an intuitive filtering interface.
  - Custom `sdtMultiSelect` combobox UI for filtering `Picklist` and `Multipicklist` fields with pill-based tag display.
  - Cross-object relationship field support (e.g., dynamically fetching picklists for `Account.Industry` from a child object).

## Architecture & Components

The project is simplified to contain only the essential components required to run the `Simple Data Table`:

### LWC (Frontend)
- **`simpleDataTable`**: The core component that handles the table rendering, debounce search logic, imperative data fetching, and passing data down to subcomponents.
- **`sdtColManager`**: Handles column visibility and dynamic sorting UI.
- **`sdtFilterPanel`**: The side-panel/UI dedicated to building complex filter logic to send back to the server.
- **`sdtMultiSelect`**: A standalone custom dropdown component supporting advanced search, multi-selection, and compact pill UI for Picklist/Multipicklist filters.
- **`dynamicTableConfigurator`**: Builder/Admin UI to configure the properties of the table and columns dynamically.

### Apex (Backend)
- **`SimpleTableController.cls`**: AuraEnabled endpoint for LWC. Handles passing search terms, filters, and sorting parameters to the service layer.
- **`SimpleTableService.cls`**: The core engine for dynamic query generation (`buildQuery`, `buildFilterCondition`), SOQL injection prevention, and executing server-side searches.
- **`SimpleTableDTO.cls`**: Data Transfer Object holding classes like `FilterDef`, and the wrapper for the table response data.

### Objects & Fields (Database)
- **`Table__c`**: The primary configuration object that drives the logic for table settings.
- **`Table_Columns__c`**: Defines the columns, field API names, and specific properties (e.g., `Aggregate__c` for sum/average).
- **Other supportive objects**: `Table_Action__c`, `Table_User_View__c`, `Table_Matrix_Job__c`, etc.

## Setup & Deployment

1. **Deploy Metadata**:
   Deploy all components and custom objects to your Salesforce org:
   ```bash
   sf project deploy start
   ```
2. **Configure Table**:
   Use the `Table__c` object in Salesforce to define a new table configuration and add columns via `Table_Columns__c`.
3. **Use in App**:
   Drop the `simpleDataTable` component onto a Lightning Page in the App Builder and pass the `Table Name` as a property.


## Namespace branch deployment

This edition references `Shree_Tech__` configuration metadata. Use `manifest/namespace-runtime.xml` for existing namespace orgs. See [namespace deployment instructions](doc/namespace-deployment.md). Use branch `independent` for unprefixed orgs.
