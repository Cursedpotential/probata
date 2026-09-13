$ErrorActionPreference = 'Stop'
$sql = (& (Join-Path $PSScriptRoot 'reconcile.ps1')) -join "`n"
function Assert-True($Condition, $Description) {
    if (!$Condition) { throw "FAIL: $Description" }
    "PASS: $Description"
}
Assert-True ($sql.TrimEnd().EndsWith('ROLLBACK;')) 'Default output rolls back'
Assert-True ($sql -notmatch '(?m)^COMMIT;') 'Default output cannot commit'
Assert-True (([regex]::Matches($sql, '(?m)^CREATE TABLE context\.handler_')).Count -eq 6) 'Exactly six snapshot-derived handler tables'
Assert-True (([regex]::Matches($sql, 'ADD CONSTRAINT handler_.* PRIMARY KEY')).Count -eq 6) 'Six primary keys'
Assert-True (([regex]::Matches($sql, 'ADD CONSTRAINT handler_.* FOREIGN KEY')).Count -eq 18) '18 foreign keys'
Assert-True (([regex]::Matches($sql, 'ADD CONSTRAINT handler_.* UNIQUE')).Count -eq 7) 'Seven unique constraints'
Assert-True ($sql -notmatch 'ADD CONSTRAINT handler_recommendation_signature_key') 'Append-only recovery may reuse a content signature'
Assert-True (([regex]::Matches($sql, '(?m)^GRANT .* ON TABLE context\.handler_')).Count -eq 18) '18 canonical table grants'
Assert-True ($sql -match "'custody','raw_source_verification'") 'Legacy receipt type remains allowed'
Assert-True ($sql -notmatch '(?im)^\s*(DELETE FROM|TRUNCATE |DROP TABLE|UPDATE context\.|INSERT INTO context\.)') 'No existing-table data mutations or removal'
Assert-True ($sql -match 'Preservation failure' -and $sql -match 'LOCK TABLE %s IN SHARE MODE') 'Locked pre/post row count and SHA-256 proof'
Assert-True ($sql -match 'Expected absent context' -and $sql -match 'Unexpected receipt CHECK drift') 'Partial schema and CHECK drift fail closed'
$apply = (& (Join-Path $PSScriptRoot 'reconcile.ps1') -Apply) -join "`n"
Assert-True ($apply.TrimEnd().EndsWith('COMMIT;')) 'Commit requires explicit Apply switch'
