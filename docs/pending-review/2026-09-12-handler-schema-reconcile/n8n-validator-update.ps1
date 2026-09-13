param([switch]$Apply)
$ErrorActionPreference='Stop'
$config=@{}
Get-Content C:/Users/matts/.secrets/n8n-ovh2.env | ForEach-Object {
    if ($_ -match '^([A-Z0-9_]+)=(.*)$') { $config[$matches[1]]=$matches[2].Trim().Trim('"').Trim("'") }
}
if (!$config['N8N_API_KEY']) { throw 'Missing API key' }
$headers=@{'X-N8N-API-KEY'=$config['N8N_API_KEY']}
$base='http://100.91.190.107:5678/api/v1/workflows'
function Hash-Value($value) {
    $bytes=[Text.Encoding]::UTF8.GetBytes(($value|ConvertTo-Json -Depth 100 -Compress))
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
}
$specs=@(
    @{id='fvKS2gcsRUdEKUun';file='wf-select-parser-activity.json';prior='3870c5fc-d036-4868-887f-8f2fe90cd7a0'},
    @{id='YQoFBykpZoDrU0n6';file='wf-execute-parser-activity.json';prior='a839c59b-a0ad-4504-b412-538c925db703'}
)
foreach($spec in $specs) {
    $uri="$base/$($spec.id)"
    $original=Invoke-RestMethod $uri -Headers $headers
    if (!$original.active -or $original.versionId -ne $original.activeVersionId -or $original.versionId -ne $spec.prior) {
        throw "Unexpected prior/activation state $($spec.id); review before replacing"
    }
    $fingerprint=Hash-Value $original
    $local=Get-Content (Join-Path $PSScriptRoot "../../../deploy/docker/n8n/workflows/proffer/$($spec.file)") -Raw | ConvertFrom-Json
    $desired=@($local.nodes|Where-Object name -eq 'Validate + Shape StageRequest')
    $target=@($original.nodes|Where-Object name -eq 'Validate + Shape StageRequest')
    if($desired.Count -ne 1 -or $target.Count -ne 1) {throw 'Ambiguous validator node'}
    if($desired[0].parameters.jsCode -notmatch 'handlerRefs' -or $desired[0].parameters.jsCode -notmatch 'allowedRefSets') {throw 'Wrong local validator contract'}
    $nodeId=$target[0].id
    $oldCodeHash=Hash-Value $target[0].parameters.jsCode
    $newCodeHash=Hash-Value $desired[0].parameters.jsCode
    $payload=[ordered]@{name=$original.name;nodes=$original.nodes;connections=$original.connections;settings=$original.settings;staticData=$original.staticData}
    $target[0].parameters.jsCode=$desired[0].parameters.jsCode
    $body=$payload|ConvertTo-Json -Depth 100 -Compress
    $expectedPayloadHash=Hash-Value $payload
    # Compare full fetched document immediately before PUT. Never overwrite unseen edits.
    $latest=Invoke-RestMethod $uri -Headers $headers
    if((Hash-Value $latest) -ne $fingerprint) {throw "Concurrent workflow drift $($spec.id)"}
    if(!$Apply) {
        [pscustomobject]@{mode='read-only';id=$spec.id;prior=$spec.prior;priorFingerprint=$fingerprint;oldCodeHash=$oldCodeHash;newCodeHash=$newCodeHash}|ConvertTo-Json -Compress
        continue
    }
    $updated=Invoke-RestMethod $uri -Method Put -Headers $headers -ContentType 'application/json' -Body $body
    $after=Invoke-RestMethod $uri -Headers $headers
    $afterPayload=[ordered]@{name=$after.name;nodes=$after.nodes;connections=$after.connections;settings=$after.settings;staticData=$after.staticData}
    if((Hash-Value $afterPayload) -ne $expectedPayloadHash -or $after.versionId -ne $updated.versionId -or !$after.active) {throw 'Updated graph/state verification failed; inspect before any retry'}
    # n8n draft/publish: publish only this reviewed version, keeping existing workflow active.
    if($after.activeVersionId -ne $after.versionId) {
        $publishBody=@{versionId=$after.versionId}|ConvertTo-Json -Compress
        $published=Invoke-RestMethod "$uri/activate" -Method Post -Headers $headers -ContentType 'application/json' -Body $publishBody
    }
    $verified=Invoke-RestMethod $uri -Headers $headers
    $verifiedPayload=[ordered]@{name=$verified.name;nodes=$verified.nodes;connections=$verified.connections;settings=$verified.settings;staticData=$verified.staticData}
    if((Hash-Value $verifiedPayload) -ne $expectedPayloadHash -or !$verified.active -or $verified.activeVersionId -ne $verified.versionId -or $verified.versionId -ne $updated.versionId) {throw 'Published exact version/code verification failed'}
    [pscustomobject]@{mode='updated-and-published';id=$spec.id;nodeId=$nodeId;prior=$spec.prior;priorFingerprint=$fingerprint;oldCodeHash=$oldCodeHash;newCodeHash=$newCodeHash;version=$verified.versionId;activeVersion=$verified.activeVersionId;active=$verified.active}|ConvertTo-Json -Compress
}
