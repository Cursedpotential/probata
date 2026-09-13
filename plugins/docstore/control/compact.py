"""Bounded presentation adapter derived from scripts/docstore/sq.py.

No database writes, temporary files, arbitrary SQL, or semantic summarization.
Only explicit body/vector fields are abbreviated; diagnostic fields stay intact.
"""
import json


def compact_result(value):
    import duckdb
    encoded = json.dumps(value, ensure_ascii=False)
    if len(encoded.encode('utf-8')) > 2 * 1024 * 1024:
        raise ValueError('Compact input exceeds 2 MiB')
    omissions = []
    def normalize(item, path='$', key=None):
        if key in {'embedding', 'vector'} and isinstance(item, list):
            omissions.append({'path': path, 'kind': 'vector', 'dimensions': len(item)})
            return f'<vector {len(item)} dimensions>'
        if key in {'body', 'content', 'text'} and isinstance(item, str) and len(item) > 600:
            omissions.append({'path': path, 'kind': 'text', 'original_chars': len(item), 'shown_chars': 600})
            return item[:600] + '… [excerpt; retrieve document for full text]'
        if isinstance(item, dict):
            return {k: normalize(v, path + '.' + k, k) for k,v in item.items()}
        if isinstance(item, list):
            return [normalize(v, f'{path}[{i}]') for i,v in enumerate(item)]
        return item
    normalized = normalize(value)
    # One short-lived in-memory connection, one thread. Buffer limit is not an RSS ceiling.
    with duckdb.connect(':memory:', config={'threads': '1', 'memory_limit': '64MB',
            'enable_external_access': 'false', 'temp_directory': '',
            'autoinstall_known_extensions': 'false', 'autoload_known_extensions': 'false'}) as con:
        def tables(item):
            if isinstance(item, list) and item and all(isinstance(r, dict) for r in item):
                columns = list(dict.fromkeys(k for row in item for k in row))
                if len(columns) > 128:
                    raise ValueError('Compact rowset exceeds 128 columns')
                if not columns:
                    return item
                # Values and JSON Pointer paths are bound; no result data becomes SQL.
                pointers = ['/' + k.replace('~','~0').replace('/','~1') for k in columns]
                sql = 'SELECT ' + ','.join('json_extract(value, ?)' for _ in columns)
                sql += ' FROM json_each(?) ORDER BY CAST(key AS BIGINT)'
                rows = con.execute(sql, [*pointers, json.dumps(item)]).fetchall()
                return {'columns': columns, 'rows': [[json.loads(v) if v is not None else None for v in row] for row in rows],
                        'row_count': len(rows)}
            if isinstance(item, dict):
                return {k: tables(v) for k,v in item.items()}
            return item
        result = tables(normalized)
    return {'format': 'compact-columns-v1', 'data': result, 'omissions': omissions,
            'rows_dropped': 0, 'instruction': 'Rows follow columns in order. Omitted text is an excerpt, not a summary. Use docstore_get for full documents.'}
