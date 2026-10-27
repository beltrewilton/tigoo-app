# ECF certification batch

Source: pos; /Users/beltre.wilton/apps/tigoo-app/data/pos-ecf-test/ans/e9f9d2d8-0662-41e4-91da-2960b6657843.source.json. Issuer RNC: 131362702.
1 signed ECFs; 0 signed RFCEs.

- `ecf/recepcion`: 1 full documents for normal reception.
- `rfce`: summaries for type 32 below DOP 250,000.00.
- `ecf/consumo-menor-250000`: corresponding full ECFs for portal upload after RFCE acceptance.
- `manifest.json`: schema/certificate fingerprints, field mappings, reference order and source observations.
- `documents.csv`: document inventory. `SHA256SUMS`: exact signed XML checksums.

Every XML passed XSD, source-field, signature and configured certificate-chain checks.
Source arithmetic observations: 0; review them in the manifest. Values were preserved.
External reference eNCFs may need acceptance before notes in this batch; dependency order only
resolves documents present in this workbook. Consult the referenced document when absent.
Follow `normal_reception_order` and wait for required acceptance before dependent notes.
No documents were submitted to DGII. DGII fiscal acceptance has not been evaluated.
Do not edit or reformat signed bytes. Re-signing an ECF requires regenerating its RFCE.
