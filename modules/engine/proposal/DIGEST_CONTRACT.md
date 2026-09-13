# Proposal table digest contract

`proffer-table-json-v1` is the required logical table-digest algorithm. It is
independent of DuckDB file bytes and remains stable when the database container,
page layout, or in-database freeze fields change.

For each required logical relation, compute SHA-256 over the UTF-8 encoding of
one canonical JSON object with this shape:

```json
{"columns":["column_a","column_b"],"rows":[{"column_a":"value","column_b":1}],"table":"proposed_records"}
```

Canonicalization rules:

1. `columns` contains every table column once, in DuckDB schema order.
2. Every entry in `rows` is an object keyed by column name. It contains every
   column, including columns whose value is `null`.
3. A DuckDB `JSON` cell is represented by its stored JSON text as a JSON string.
   Do not parse or structurally normalize the cell before table hashing.
4. Timestamps are normalized to UTC and encoded as RFC3339 strings.
5. Canonicalize each row using sorted object keys, no insignificant whitespace,
   and unescaped Unicode. Sort rows lexicographically by the UTF-8 bytes of that
   row's canonical JSON.
6. Build the outer `{table,columns,rows}` object using sorted object keys, no
   insignificant whitespace, and unescaped Unicode.
7. Hash the resulting UTF-8 bytes with SHA-256 and encode the digest as 64
   lowercase hexadecimal characters.

The manifest records `table`, `algorithm`, `rows`, and `digest` for each logical
relation. `proposal_control` is excluded because it stores the resulting logical
proposal digest and mutable lifecycle fields. The external bundle envelope,
created only after the DuckDB file is closed, carries the finalized database
byte hash and bundle digest. Approval binds the logical proposal digest and,
when that external envelope exists, the bundle digest as a separate value.
