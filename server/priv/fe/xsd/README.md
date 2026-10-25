# Runtime schema registry

The offline generation tools select the matching e-CF type schema from this
directory and select `RFCE 32 v.1.0.xsd` for consumption summaries. Exact element
names, sequence and cardinalities come from the selected XSD, including
`MontoSubRecargo`. Source spreadsheets do not determine XML element casing.

Original DGII files are retained unchanged under the repository's `fe/xsd`.
The existing runtime ECF/ARECF schemas group RNC alternations for xmerl
compatibility. The existing type-31 schema also removes leading whitespace from
the declaration of `IndicadorServicioTodoIncluidoType` to match its references.

The runtime RFCE copy replaces four PCRE noncapturing group openings `(?:` with
ordinary XSD regular-expression group openings `(`. XML Schema regular
expressions do not support noncapturing groups; the substitution preserves the
accepted values. No other RFCE bytes or element names were changed.

Every generated manifest records the actual validation schema path and SHA256.
The generator validates complete signed XML with `xmllint --nonet` and verifies
the signature and configured certificate chain separately. The XSD's Signature
wildcard alone does not establish signature validity.

This resource does not change the receiver controllers or add RFCE support to
`TigooServer.FeXml`.
