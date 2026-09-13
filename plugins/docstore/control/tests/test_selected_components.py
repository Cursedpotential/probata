"""Admission/order tests only; real SDK retention proof is a separate harness."""
import importlib.util
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest


@pytest.fixture
def components(monkeypatch):
    monkeypatch.setitem(sys.modules, 'cocoindex', SimpleNamespace(component_subpath=lambda key: key))
    path=Path(__file__).resolve().parents[4]/'scripts/docstore/selected_components.py'
    monkeypatch.syspath_prepend(str(path.parent))
    spec=importlib.util.spec_from_file_location('selected_components_under_test',path)
    module=importlib.util.module_from_spec(spec)
    monkeypatch.setitem(sys.modules,spec.name,module)
    spec.loader.exec_module(module)
    return module


@pytest.fixture
def marker(components):
    return components.SelectedBootstrapIdentity(app='app',environment='env',topology='topology',
        source='source',tracking='tracking',target='target',processing_profile='profile').digest()


class Operator:
    def __init__(self,marker):
        self.marker=marker
        self.events=[]

    async def read_committed_state(self,key):
        self.events.append(('read',key))
        return self.marker

    async def mark_ready(self):
        self.events.append(('ready',))

    async def update(self,key,processor,value,*args):
        self.events.append(('update',key,value))
        async def ready():
            self.events.append(('child_ready',key))
        return SimpleNamespace(ready=ready)


@pytest.mark.asyncio
@pytest.mark.parametrize('observed',[None,False,True,0,2,'1','0'*64])
async def test_marker_mismatch_never_updates_or_bootstraps(components,marker,observed):
    instance=components.CommittedSelectedComponentUpdates('identity',marker,object(),[('alpha','text')])
    operator=Operator(observed)
    with pytest.raises(RuntimeError,match='full scan refused'):
        await instance.process_live(operator)
    assert operator.events==[('read','identity')]


@pytest.mark.asyncio
async def test_selected_updates_follow_commit_readiness(components,marker):
    instance=components.CommittedSelectedComponentUpdates('identity',marker,object(),[('alpha','a'),('beta','b')])
    operator=Operator(marker)
    await instance.process_live(operator)
    assert operator.events==[('read','identity'),('ready',),('update','alpha','a'),
        ('child_ready','alpha'),('update','beta','b'),('child_ready','beta')]


@pytest.mark.asyncio
async def test_full_reconciliation_is_always_refused(components,marker):
    instance=components.CommittedSelectedComponentUpdates('identity',marker,object(),[('alpha','a')])
    with pytest.raises(RuntimeError,match='full reconciliation'):
        await instance.process()


@pytest.mark.parametrize('items',[[],[('same','a'),('same','b')],[(str(n),'v') for n in range(21)]])
def test_entire_selection_admitted_before_execution(components,marker,items):
    with pytest.raises(ValueError):
        components.CommittedSelectedComponentUpdates('identity',marker,object(),items)


@pytest.mark.parametrize('key,version',[('', '0'*64),(' ', '0'*64),('identity',False),
    ('identity',''),('identity',0),('identity','A'*64),('identity','0'*63)])
def test_explicit_marker_contract_required(components,key,version):
    with pytest.raises(ValueError):
        components.CommittedSelectedComponentUpdates(key,version,object(),[('alpha','a')])


def test_membership_snapshot_does_not_follow_caller_list_mutation(components,marker):
    items=[('alpha','a')]
    instance=components.CommittedSelectedComponentUpdates('identity',marker,object(),items)
    items.append(('beta','b'))
    assert instance.items==( ('alpha','a'), )


def test_identity_digest_is_stable_and_field_sensitive(components):
    base=dict(app='app',environment='env',topology='topology',source='source',tracking='tracking',target='target',processing_profile='profile')
    first=components.SelectedBootstrapIdentity(**base).digest()
    assert first==components.SelectedBootstrapIdentity(**base).digest()
    assert len(first)==64
    for field in base:
        changed=dict(base)
        changed[field]+='-changed'
        assert components.SelectedBootstrapIdentity(**changed).digest()!=first


@pytest.mark.parametrize('field,value',[('app',''),('environment',' '),('topology',None),
    ('source','x'*501),('tracking',''),('target',''),('processing_profile','')])
def test_identity_rejects_empty_or_unbounded_fields(components,field,value):
    data=dict(app='app',environment='env',topology='topology',source='source',tracking='tracking',target='target',processing_profile='profile')
    data[field]=value
    with pytest.raises(ValueError):
        components.SelectedBootstrapIdentity(**data)
