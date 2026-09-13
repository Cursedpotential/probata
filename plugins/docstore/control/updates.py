"""Read related documentation updates across structured and indexed records.

Literal keyword lookup, not semantic search or proof that every note was captured.
"""
from typing import Annotated
from pydantic import Field
from fastmcp.exceptions import ToolError
from governance import query, native_client
from functools import partial
from compact import compact_result

QUERIES = {
    'documents': "SELECT id,title,source_path,status,updated FROM document WHERE string::lowercase(body ?? '') CONTAINS $term OR string::lowercase(title ?? '') CONTAINS $term ORDER BY updated DESC LIMIT $limit;",
    'notes': "SELECT id,subject,title,summary,priority,authority,status,domains,source_ref,revision,updated_at FROM docstore_flag WITH NOINDEX WHERE string::lowercase(summary ?? '') CONTAINS $term OR string::lowercase(title ?? '') CONTAINS $term OR string::lowercase(subject) CONTAINS $term ORDER BY updated_at DESC LIMIT $limit;",
    'decision_log': "SELECT id,subject,actor,action,rationale,at FROM decision_log WHERE string::lowercase(rationale ?? '') CONTAINS $term ORDER BY at DESC LIMIT $limit;",
    'adrs': "SELECT id,title,status,decision,decided_at,source_doc,<-supersedes<-adr.id AS superseded_by FROM adr WHERE string::lowercase(decision ?? '') CONTAINS $term OR string::lowercase(title ?? '') CONTAINS $term ORDER BY decided_at DESC LIMIT $limit;",
}


async def related_updates(config, term, limit=10, execute=query):
    term = term.strip().lower()
    if not 2 <= len(term) <= 200 or not 1 <= limit <= 20:
        raise ToolError('Use a 2–200 character literal term and limit 1–20')
    if execute is query:
        async with native_client(config) as client:
            return await related_updates(config, term, limit, execute=partial(query, client=client))
    results = {}
    for source, sql in QUERIES.items():
        try:
            rows = await execute(config, sql, {'term': term, 'limit': limit + 1})
            if not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows):
                raise ToolError('Invalid related-update rows')
            results[source] = {'ok': True, 'truncated': len(rows) > limit,
                               'records': compact_result(rows[:limit])}
        except Exception:
            # An unavailable table must never look like an empty successful search.
            results[source] = {'ok': False, 'error': 'Lookup failed; coverage incomplete'}
    return {'term': term, 'sources': results,
            'complete': all(r['ok'] and not r.get('truncated') for r in results.values()),
            'coverage': 'Literal matches in four known Docstore tables; absence is not proof that every external note was captured.',
            'instructions': 'Inspect relevant records and supersession before writing. Indexed document updated timestamps are not approval dates. Read back saved notes; source indexing is separate.',
            'indexing_triggered': False}


def register(mcp, config, read_annotations):
    @mcp.tool(annotations={**read_annotations, 'title': 'Query related Docstore updates before writing'})
    async def docstore_related_updates(term: Annotated[str, Field(min_length=2, max_length=200)],
                                       limit: Annotated[int, Field(ge=1, le=20)] = 10) -> dict:
        """Query notes, ADRs, decision log and indexed documents before updates. Compact, literal keyword search; includes inactive records and explicit partial coverage."""
        return await related_updates(config, term, limit)
