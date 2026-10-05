# Shree Tech deployment

This branch targets an org with the Shree_Tech package configuration schema. The independent branch retains unprefixed code. Baseline: eb5009dfaa22223a00a0cb8f17a482083d076c2f.

## References

Apex configuration object, field and relationship references use Shree_Tech__. The Configurator maintains unprefixed editor state and maps configuration keys at the Apex payload boundary. Business object API names and field paths selected in the UI are passed as entered; they must match their actual org schema. Apex classes and LWC bundles remain local unpackaged components, so their imports and class names are not prefixed. sfdx-project.json remains namespace empty; this is not a managed-package build.

## Deploy to the existing namespace org

The package objects and all referenced namespaced fields must already exist, including Shree_Tech__Aggregate__c. A custom field added outside the package may have an unprefixed API name even on a package object; validate actual schema before deployment.

Use the code-only manifest to avoid deploying duplicate unprefixed configuration objects:

```bash
sf project deploy start --manifest manifest/namespace-runtime.xml --target-org YOUR_ORG --dry-run
sf project deploy start --manifest manifest/namespace-runtime.xml --target-org YOUR_ORG
```

Do not use an unscoped full project deploy for this branch against a subscriber org. The unprefixed object XML remains the source schema inventory for the independent edition; it is excluded from this deployment manifest.

## Validate

Open the Configurator; list, edit, save and clone a configuration. Test feature override CRUD and lookup selections. Open Simple Data Table against that saved configuration; test search, typed filters, sorting, related fields, parent context, page navigation and aggregates. Local checks verify references and payload mapping only; live Salesforce compilation and UI validation are required.

## Maintain both editions

Make feature changes deliberately in each branch, preserving namespace boundary differences. Do not merge namespace-specific references directly into independent. Update project reference baseline after releases.
