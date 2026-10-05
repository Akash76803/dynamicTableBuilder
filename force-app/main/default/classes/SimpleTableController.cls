/**
 * SimpleTableController
 * ─────────────────────────────────────────────────────────────────────────────
 * Thin AuraEnabled controller for SimpleDataTable LWC.
 * No business logic here — delegates everything to SimpleTableService.
 *
 * Layer:  Controller (AuraEnabled entry points)
 * Calls:  SimpleTableService
 * Called by: simpleDataTable LWC via @wire
 */
public with sharing class SimpleTableController {

    /**
     * Returns column definitions + row data for the given table config name.
     *
     * Used as @wire in simpleDataTable.js (cacheable=true).
     *
     * @param tableName  Name field on Shree_Tech__Table__c — which config to load
     * @param parentId   Optional — record page context; filters child records.
     *                   Pass null when used on an App/Home page.
     */
    @AuraEnabled(cacheable=true)
    public static SimpleTableDTO.TableResult getTableData(
        String tableName,
        String parentId,
        String searchTerm,
        String filtersJson,
        String sortColumn,
        String sortDirection
    ) {
        try {
            return SimpleTableService.getData(tableName, parentId, searchTerm, filtersJson, sortColumn, sortDirection);
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception ex) {
            throw new AuraHandledException(
                'SimpleTable: Failed to load data — ' + ex.getMessage()
            );
        }
    }
}
