-- Memory scope root: probata -> propria.
-- Byline: Claude Code · Opus 5 · 2026-09-19 — owner: "probata isn't the whole project, propria is,
-- and that's the root." Target: SurrealDB probata_memory/memory (surreal-case, ovh-files :8471).
-- Order matters: widen the ASSERT, move the rows, then narrow the ASSERT to propria only.
-- Mapping: 'probata' -> 'propria'; 'probata/propria/<x>' -> 'propria/<x>'; 'probata/<x>' -> 'propria/<x>'.
-- The recall/reflect/memory_stats functions match scopes by prefix, so they need no change.

BEGIN TRANSACTION;

DEFINE FIELD OVERWRITE scope ON memory TYPE string
    ASSERT string::matches($value, '^(probata|propria)(/[a-z0-9_-]+)*$')
    COMMENT 'transitional during the 2026-09-19 root move';
DEFINE FIELD OVERWRITE scope ON episode TYPE string
    ASSERT string::matches($value, '^(probata|propria)(/[a-z0-9_-]+)*$')
    COMMENT 'transitional during the 2026-09-19 root move';

UPDATE memory SET scope = string::replace(scope, 'probata/propria/', 'propria/')
    WHERE string::starts_with(scope, 'probata/propria/');
UPDATE memory SET scope = 'propria' + string::slice(scope, 7)
    WHERE scope = 'probata' OR string::starts_with(scope, 'probata/');
UPDATE episode SET scope = string::replace(scope, 'probata/propria/', 'propria/')
    WHERE string::starts_with(scope, 'probata/propria/');
UPDATE episode SET scope = 'propria' + string::slice(scope, 7)
    WHERE scope = 'probata' OR string::starts_with(scope, 'probata/');

DEFINE FIELD OVERWRITE scope ON memory TYPE string
    ASSERT string::matches($value, '^propria(/[a-z0-9_-]+)*$')
    COMMENT 'hierarchical scope path; root propria = the whole project; propria/<module>[/<agent>] narrows';
DEFINE FIELD OVERWRITE scope ON episode TYPE string
    ASSERT string::matches($value, '^propria(/[a-z0-9_-]+)*$')
    COMMENT 'hierarchical scope path; root propria = the whole project; propria/<module>[/<agent>] narrows';

COMMIT TRANSACTION;
