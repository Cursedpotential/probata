"""Proof-stage selected-child updates through CocoIndex's public live operator.

EXPERIMENTAL: static mount_each -> live-parent adoption FAILED retention proof.
Fresh incremental-only bootstrap also FAILED for SelectedComponentUpdates.
CommittedSelectedComponentUpdates passed bounded SQLite retention checks only.
Neither class is integrated into Docstore or approved for production migration.
No full scan, deletion, background loop, alternate target or tracking database.
The caller must verify app/state/target ownership before using this primitive.
"""
from __future__ import annotations

import re

import cocoindex as coco
from selected_identity import SelectedBootstrapIdentity


class SelectedComponentUpdates:
    def __init__(self, processor, items, *args):
        if not isinstance(items, (list, tuple)) or not 1 <= len(items) <= 20:
            raise ValueError('Select 1 to 20 explicit keyed items')
        keys = [key for key, value in items]
        if any(not isinstance(key, str) or not key.strip() or len(key) > 1000 for key in keys):
            raise ValueError('Selected component keys must be nonempty bounded strings')
        if len(set(keys)) != len(keys):
            raise ValueError('Duplicate selected component keys')
        self.processor = processor
        self.items = tuple(items)
        self.args = args

    async def process(self):
        # A selected list is NOT a complete snapshot. Never permit update_full
        # to run GC against it, including a future accidental refactor.
        raise RuntimeError('Selected updates must not perform full reconciliation')

    async def process_live(self, operator: coco.LiveComponentOperator):
        for key, value in self.items:
            handle = await operator.update(
                coco.component_subpath(key), self.processor, value, *self.args)
            await handle.ready()
        await operator.mark_ready()


class CommittedSelectedComponentUpdates(SelectedComponentUpdates):
    """Proof-stage updater for an already bootstrapped live parent.

    Caller MUST use App.update(live=True), check error statistics and independently
    verify the exact targets. This never bootstraps, updates a marker, or scans.
    Not integrated into Docstore; a marker alone does not verify source identity.
    """

    def __init__(self, bootstrap_key, bootstrap_version, processor, items, *args):
        if not isinstance(bootstrap_key, str) or not bootstrap_key.strip():
            raise ValueError('Explicit bootstrap key required')
        if not isinstance(bootstrap_version, str) or not re.fullmatch(r'[0-9a-f]{64}', bootstrap_version):
            raise ValueError('Bootstrap version must be a lowercase SHA-256 identity digest')
        super().__init__(processor, items, *args)
        self.bootstrap_key = bootstrap_key
        self.bootstrap_version = bootstrap_version

    async def process_live(self, operator: coco.LiveComponentOperator):
        marker = await operator.read_committed_state(self.bootstrap_key)
        if type(marker) is not type(self.bootstrap_version) or marker != self.bootstrap_version:
            raise RuntimeError('Selected updates require a verified prior bootstrap; full scan refused')
        await operator.mark_ready()
        for key, value in self.items:
            handle = await operator.update(
                coco.component_subpath(key), self.processor, value, *self.args)
            await handle.ready()
