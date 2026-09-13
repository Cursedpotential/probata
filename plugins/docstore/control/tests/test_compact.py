import json
import pytest
from compact import compact_result

def test_flags_and_diagnostics_preserved():
    source = {'flags': [{'id':'note:x','priority':'critical','authority':'owner_decision','status':'active','summary':'do not overwrite'}],
              'warning':'CDC unproven', 'truncated': True}
    result = compact_result(source)
    table = result['data']['flags']
    assert dict(zip(table['columns'],table['rows'][0])) == source['flags'][0]
    assert result['data']['warning'] == source['warning']
    assert result['data']['truncated'] is True
    assert source['flags'][0]['summary'] == 'do not overwrite'

def test_excerpts_vectors_and_numeric_lists():
    source = {'body':'x'*9000,'embedding':[0.1]*2048,'counts':list(range(15))}
    result = compact_result(source)
    assert result['data']['counts'] == source['counts']
    assert len(result['omissions']) == 2
    assert len(json.dumps(result)) < len(json.dumps(source)) / 4
    assert result['rows_dropped'] == 0

def test_bound_keys_order_types_and_no_dedup():
    row = {'a/b~c': 1, '"; DROP TABLE x;--': False, 'id':'x', 'nothing': None}
    result = compact_result([row,row])['data']
    assert len(result['rows']) == 2
    assert dict(zip(result['columns'],result['rows'][0])) == row

def test_input_limit_and_empty():
    with pytest.raises(ValueError, match='2 MiB'):
        compact_result({'body':'x'*(2*1024*1024)})
    assert compact_result([])['data'] == []
