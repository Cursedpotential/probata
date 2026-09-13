import pytest
from updates import related_updates
from fastmcp.exceptions import ToolError

async def test_four_sources_bound_term_and_explicit_truncation():
    calls=[]
    async def execute(cfg,sql,params):
        calls.append((sql,params))
        return [{'id':'x','status':'superseded'}, {'id':'y','status':'active'}]
    result=await related_updates(None,"Dragonfly'; --",1,execute)
    assert len(calls)==4
    assert all("Dragonfly" not in sql for sql,_ in calls)
    assert all(p['limit']==2 for _,p in calls)
    assert result['complete'] is False
    assert all(r['truncated'] for r in result['sources'].values())
    assert result['sources']['notes']['records']['data']['rows'][0][1]=='superseded'

async def test_errors_not_empty_results():
    async def execute(cfg,sql,params):
        if 'decision_log' in sql: raise RuntimeError('private failure details')
        return []
    result=await related_updates(None,'Dragonfly',execute=execute)
    assert not result['complete']
    assert not result['sources']['decision_log']['ok']
    assert result['sources']['notes']['ok']
    assert 'private' not in str(result)

async def test_invalid_term_no_query():
    with pytest.raises(ToolError): await related_updates(None,'  ')
