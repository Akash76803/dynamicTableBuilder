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
}
