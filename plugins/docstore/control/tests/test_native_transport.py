from contextlib import asynccontextmanager
import json
import logging
import httpx
import pytest
from native_transport import close_session


@pytest.mark.parametrize('status', [200,204,404])
async def test_immediate_close(status,caplog):
    requests=[]
    def respond(req):
        requests.append(req)
        return httpx.Response(status)
    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
        result=await close_session(client,'https://docs.invalid/mcp','private-id','2025-11-25')
    assert result['state']=='closed'
    assert len(requests)==1
    assert requests[0].method=='DELETE'
    assert 'private-id' not in caplog.text


@pytest.mark.parametrize('probe_status,expected', [(404,'closed_verified'),(200,'unconfirmed'),(401,'unconfirmed'),(500,'unconfirmed')])
async def test_202_requires_verification(probe_status,expected,caplog):
    requests=[]
    def respond(req):
        requests.append(req)
        return httpx.Response(202 if req.method=='DELETE' else probe_status)
    with caplog.at_level(logging.WARNING):
        async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
            result=await close_session(client,'https://docs.invalid/mcp','private-id','2025-11-25')
    assert result['state']==expected
    assert json.loads(requests[1].content)['method']=='ping'
    assert requests[1].headers['Mcp-Session-Id']=='private-id'
    assert requests[1].headers['MCP-Protocol-Version']=='2025-11-25'
    assert ('cleanup unconfirmed' in caplog.text)==(expected=='unconfirmed')
    assert 'private-id' not in caplog.text


async def test_timeout_reported_without_raising_or_leaking(caplog):
    def respond(req): raise httpx.ReadTimeout('private-token')
    async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
        result=await close_session(client,'https://docs.invalid/mcp','private-id')
    assert result['state']=='unconfirmed'
    assert 'cleanup unconfirmed' in caplog.text
    assert 'private-token' not in caplog.text


async def test_405_and_no_session():
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda req:httpx.Response(405))) as client:
        assert (await close_session(client,'https://docs.invalid/mcp','x'))['state']=='server_managed'
        assert (await close_session(client,'https://docs.invalid/mcp',None))['state']=='no_session'


async def test_updates_share_one_session(monkeypatch):
    import updates
    calls=[]
    sentinel=object()
    @asynccontextmanager
    async def connect(cfg):
        calls.append('open')
        yield sentinel
        calls.append('close')
    async def execute(cfg,sql,parameters=None,*,client=None):
        assert client is sentinel
        calls.append('query')
        return []
    monkeypatch.setattr(updates,'native_client',connect)
    monkeypatch.setattr(updates,'query',execute)
    result=await updates.related_updates(None,'session',execute=execute)
    assert result['complete']
    assert calls==['open','query','query','query','query','close']
