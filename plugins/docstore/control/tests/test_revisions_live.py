"""Opt-in bounded deployed-service test; retains clearly synthetic records, never deletes.

DOCSTORE_REVISION_LIVE=1 and dedicated Docstore credentials required. Schema 096
must already be installed. Does not invoke CocoIndex or access source files.
"""
import hashlib
import asyncio
import os
import uuid

import pytest
from fastmcp import Client

from cli import configuration
from server import build_server
from governance import query

pytestmark = pytest.mark.skipif(os.getenv('DOCSTORE_REVISION_LIVE') != '1',
    reason='Explicit synthetic live-write opt-in required')


async def test_deployed_revision_lifecycle():
    suffix=uuid.uuid4().hex
    key='note:synthetic_revision_'+suffix
    path='docs/_synthetic/revision_'+suffix+'.md'
    body='Synthetic test only.\r\n😀 A'
    capture={'document_key':key,'source_path':path,'title':'SYNTHETIC revision smoke',
        'body':body,'expected_generation':0,'actor':'automated-synthetic-test',
        'source_ref':'synthetic://docstore-revision-smoke/'+suffix}
    async with Client(build_server(configuration())) as client:
        async def call(name,params):
            return (await client.call_tool(name,params)).data
        async def state():
            return await call('docstore_revision_state',{'document_key':key})
        assert (await state())['approval_status']=='document_missing'
        first=await call('docstore_capture_revision',{'revision':capture})
        assert first['head']['generation']==1
        assert first['content_appended'] is True
        repeated=await call('docstore_capture_revision',{'revision':capture})
        assert repeated['unchanged'] is True
        approve={'document_key':key,'revision_number':1,'raw_sha256':hashlib.sha256(body.encode()).hexdigest(),
            'expected_generation':1,'actor':'automated-synthetic-test',
            'rationale':'Synthetic approval test, not owner approval of a real document',
            'source_ref':capture['source_ref'],'request_key':'synthetic-approval'}
        await call('docstore_approve_revision',{'approval':approve})
        assert (await state())['approval_status']=='approved_current'
        renamed={**capture,'source_path':path.replace('.md','_renamed.md'),'expected_generation':2}
        move=await call('docstore_capture_revision',{'revision':renamed})
        assert move['content_appended'] is False
        assert move['head']['latest_number']==1
        edited={**renamed,'body':body+' B','expected_generation':3}
        await call('docstore_capture_revision',{'revision':edited})
        changed=await state()
        assert changed['approval_status']=='changed_since_approval'
        assert changed['head']['latest_number']==2
        assert changed['events'][0]['revision']==changed['head']['current_revision']
        assert len(changed['aliases'])==2
        stale=await client.call_tool('docstore_capture_revision',{'revision':capture},raise_on_error=False)
        assert stale.is_error
        stale_approval=await client.call_tool('docstore_approve_revision',{'approval':{
            **approve,'request_key':'stale-approval','expected_generation':4}},raise_on_error=False)
        assert stale_approval.is_error
        replay=await call('docstore_approve_revision',{'approval':approve})
        assert replay['unchanged'] is True
        assert (await state())['approval_status']=='changed_since_approval'
        reverted=await call('docstore_capture_revision',{'revision':{**renamed,'expected_generation':4}})
        assert reverted['head']['latest_number']==3
        final=await state()
        assert final['approval_status']=='changed_since_approval'
        assert len(final['revisions'])==3
        assert final['cdc_execution']=='unproven'
        print('Retained synthetic test key:',key)


async def test_deployed_concurrency_and_flag_preservation():
    suffix=uuid.uuid4().hex
    key='note:synthetic_race_'+suffix
    config=configuration()
    capture={'document_key':key,'source_path':'docs/_synthetic/race_'+suffix+'.md',
        'title':'SYNTHETIC race test','body':'original','expected_generation':0,
        'actor':'automated-synthetic-test','source_ref':'synthetic://docstore-race/'+suffix}
    async with Client(build_server(config)) as c:
        await c.call_tool('docstore_capture_revision',{'revision':capture})
        await c.call_tool('docstore_set_flags',{'flag':{'subject':key,'title':'SYNTHETIC flag preservation test',
            'summary':'Synthetic test only, not an owner decision. '+suffix,'priority':'normal',
            'authority':'verified_finding','status':'active','domains':['docs'],
            'source_ref':capture['source_ref'],'rationale':'Test independent overlay preservation',
            'actor':'automated-synthetic-test','expected_revision':0}})
        before=await query(config,'SELECT * FROM docstore_flag WITH NOINDEX WHERE subject=$key;',{'key':key})
        results=await asyncio.gather(*[
            c.call_tool('docstore_capture_revision',{'revision':{**capture,'body':body,'expected_generation':1}},raise_on_error=False)
            for body in ('race-left','race-right')])
        assert sum(not r.is_error for r in results)==1
        saved=(await c.call_tool('docstore_revision_state',{'document_key':key})).data
        assert saved['head']['latest_number']==2
        assert len(saved['revisions'])==2
        assert saved['head']['generation']==2
        after=await query(config,'SELECT * FROM docstore_flag WITH NOINDEX WHERE subject=$key;',{'key':key})
        assert before==after
        print('Retained synthetic concurrency key:',key)
