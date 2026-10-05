@IsTest
private class SimpleTableRecordLinkTest {
    private static SimpleTableDTO.ColumnDef columnDef(String path, String objectName) {
        SimpleTableDTO.ColumnDef result = new SimpleTableDTO.ColumnDef();
        result.key = path; result.soqlFieldPath = path; result.isLookup = false;
        SimpleTableService.configureRecordLink(result, objectName);
        return result;
    }
    @IsTest static void detectsNameReferencesAndNestedPaths() {
        System.assertEquals('Id', columnDef('Name', 'Account').linkIdPath);
        System.assertEquals('AccountId', columnDef('AccountId', 'Contact').linkIdPath);
        System.assertEquals('Account.Name', columnDef('AccountId', 'Contact').linkLabelPath);
        System.assertEquals('Account.Id', columnDef('Account.Name', 'Contact').linkIdPath);
        System.assertEquals('Account.Parent.Id', columnDef('Account.Parent.Name', 'Contact').linkIdPath);
        System.assertEquals(null, columnDef('Account.Industry', 'Contact').linkIdPath);
        System.assertEquals(null, columnDef('Description', 'Account').linkIdPath);
        System.assertEquals('OwnerId', columnDef('OwnerId', 'Account').linkIdPath);
    }
    @IsTest static void mapsLinkTargetsAndKeepsRawValues() {
        Account related = new Account(Id='001000000000001AAA', Name='Acme');
        Contact source = new Contact(Id='003000000000001AAA', AccountId=related.Id);
        source.putSObject('Account', related);
        SimpleTableDTO.ColumnDef lookupColumn = columnDef('AccountId', 'Contact');
        List<SimpleTableDTO.RowData> rows = SimpleTableService.mapRecords(new List<SObject>{source}, new List<SimpleTableDTO.ColumnDef>{lookupColumn}, new Map<String,String>{'AccountId'=>'AccountId'});
        System.assertEquals(related.Id, rows[0].fields.get('AccountId'));
        System.assertEquals('Acme', rows[0].recordLinks.get('AccountId').label);
        System.assertEquals('Account', rows[0].recordLinks.get('AccountId').objectApiName);
        Contact blank = new Contact(Id='003000000000002AAA', AccountId=null);
        rows = SimpleTableService.mapRecords(new List<SObject>{blank}, new List<SimpleTableDTO.ColumnDef>{lookupColumn}, new Map<String,String>{'AccountId'=>'AccountId'});
        System.assertEquals(0, rows[0].recordLinks.size());
    }
    @IsTest static void configuredTextColumnUsesExplicitIdPath() {
        SimpleTableDTO.ColumnDef configured = columnDef('Account.Name', 'Contact');
        configured.dataType = 'Text';
        SimpleTableService.applyConfiguredLookupPath(configured, 'Contact', 'Account.Id');
        System.assertEquals('Account.Id', configured.linkIdPath);
        System.assertEquals('Account.Name', configured.linkLabelPath);
        // Explicit target can differ from the inferred display relationship.
        SimpleTableService.applyConfiguredLookupPath(configured, 'Contact', 'Account.ParentId');
        System.assertEquals('Account.ParentId', configured.linkIdPath);
        System.assertEquals('Account.Name', configured.linkLabelPath);
        SimpleTableService.applyConfiguredLookupPath(configured, 'Contact', '');
        System.assertEquals('Account.ParentId', configured.linkIdPath);
        SimpleTableDTO.ColumnDef ownName = columnDef('Name', 'Account');
        SimpleTableService.applyConfiguredLookupPath(ownName, 'Account', 'ParentId');
        System.assertEquals('Id', ownName.linkIdPath);
        for (String invalid : new List<String>{'Account.Name', 'Account.DoesNotExist', 'Account.Id OR Name'}) {
            Boolean rejected = false;
            try { SimpleTableService.applyConfiguredLookupPath(configured, 'Contact', invalid); }
            catch (Exception e) { rejected = true; }
            System.assert(rejected, invalid);
        }
    }
    @IsTest static void explicitTargetMapsIdAndPreservesDisplay() {
        Account related = new Account(Id='001000000000001AAA', Name='Acme', ParentId='001000000000002AAA');
        Contact source = new Contact(Id='003000000000001AAA', AccountId=related.Id);
        source.putSObject('Account', related);
        SimpleTableDTO.ColumnDef configured = columnDef('Account.Name', 'Contact');
        SimpleTableService.applyConfiguredLookupPath(configured, 'Contact', 'Account.ParentId');
        List<SimpleTableDTO.RowData> rows = SimpleTableService.mapRecords(new List<SObject>{source}, new List<SimpleTableDTO.ColumnDef>{configured}, new Map<String,String>{'Account.Name'=>'Account.Name'});
        System.assertEquals(String.valueOf(related.ParentId), rows[0].recordLinks.get('Account.Name').recordId);
        System.assertEquals('Acme', rows[0].recordLinks.get('Account.Name').label);
        System.assertEquals('Acme', rows[0].fields.get('Account.Name'));
    }
}
