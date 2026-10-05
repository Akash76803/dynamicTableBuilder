@IsTest
private class SimpleTableFilterLogicTest {
    @IsTest static void groupingAndPrecedence() {
        List<String> conditions = new List<String>{'A = 1', 'B = 2', 'C = 3'};
        System.assertEquals('((A = 1) OR ((B = 2) AND (C = 3)))', SimpleTableService.compileFilterLogic('1 OR 2 AND 3', conditions));
        System.assertEquals('((((A = 1) OR (B = 2))) AND (C = 3))', SimpleTableService.compileFilterLogic('(1 OR 2) AND 3', conditions));
    }
    @IsTest static void rejectsUnsafeOrIncompleteLogic() {
        for (String expression : new List<String>{'', '1 OR', '(1 OR 2', '1 OR 4', '1; DROP', '1 OR 2', '1 2 AND 3', '1 XOR 2 AND 3'}) {
            Boolean rejected = false;
            try { SimpleTableService.compileFilterLogic(expression, new List<String>{'A', 'B', 'C'}); }
            catch (Exception e) { rejected = true; }
            System.assert(rejected, 'Should reject: ' + expression);
        }
    }
    @IsTest static void scopedOrQueryAndLegacyArray() {
        SimpleTableDTO.ColumnDef columnDef = new SimpleTableDTO.ColumnDef();
        columnDef.key = 'name'; columnDef.soqlFieldPath = 'Name';
        columnDef.dataType = 'Text'; columnDef.filterable = true;
        List<SimpleTableDTO.ColumnDef> columns = new List<SimpleTableDTO.ColumnDef>{columnDef};
        String filters = '[{"fieldKey":"name","operator":"equals","value":"A"},{"fieldKey":"name","operator":"equals","value":"B"}]';
        String queryText = SimpleTableService.buildQuery('Contact', new List<String>{'Id', 'Name'}, '001000000000001AAA', 'AccountId', columns, null, '{"logic":"OR","filters":' + filters + '}', null, null);
        System.assert(queryText.contains('AccountId = \'001000000000001AAA\' AND ((Name = \'A\') OR (Name = \'B\'))'));
        System.assert(queryText.endsWith(' LIMIT 2000'));
        queryText = SimpleTableService.buildQuery('Contact', new List<String>{'Id'}, null, null, columns, null, filters, null, null);
        System.assert(queryText.contains('((Name = \'A\') AND (Name = \'B\'))'));
    }
}
