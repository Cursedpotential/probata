"""The worker source registry preserves current IDs and gates multi-root activation."""
from __future__ import annotations

import importlib.util
import json
import sys
from pathlib import Path

import pytest


MODULE_PATH = Path(__file__).parents[4] / "scripts" / "docstore" / "source_registry.py"
SPEC = importlib.util.spec_from_file_location("docstore_pipeline_source_registry", MODULE_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)
load_sources = MODULE.load_sources


def registry(tmp_path: Path) -> tuple[Path, Path]:
    root = tmp_path / "propria"
    current = root / "Probata" / "probata" / "docs"
    other = root / "projects" / "consignatio"
    current.mkdir(parents=True)
    other.mkdir(parents=True)
    payload = {
        "schema": "propria-docstore-source-registry-v1",
        "monorepo_root": str(root),
        "projects": [
            {
                "project_id": "probata", "source_root": "Probata/probata/docs",
                "canonical_prefix": "docs", "domains": ["docs"],
                "included_patterns": ["**/*.md"], "excluded_patterns": ["private/**"],
                "registration_status": "active", "ingestion_status": "current-full-source",
            },
            {
                "project_id": "consignatio", "source_root": "projects/consignatio",
                "canonical_prefix": "consignatio", "domains": ["consignatio", "intake"],
                "included_patterns": ["**/*.md"], "excluded_patterns": [],
                "registration_status": "active", "ingestion_status": "pending-multi-root-cdc",
            },
        ],
    }
    path = tmp_path / "registry.json"
    path.write_text(json.dumps(payload), encoding="utf-8")
    return path, current


def test_legacy_mode_preserves_existing_probata_source_identity(tmp_path):
    legacy = tmp_path / "docs"
    legacy.mkdir()
    sources, fingerprint = load_sources(None, legacy, multi_root_enabled=False)
    assert fingerprint == "legacy-probata-docs-v1"
    assert len(sources) == 1
    assert sources[0].canonical_prefix == "docs/"


def test_registry_without_activation_selects_only_current_source(tmp_path):
    path, current = registry(tmp_path)
    sources, _ = load_sources(path, current, multi_root_enabled=False)
    assert [source.project_id for source in sources] == ["probata"]
    assert sources[0].canonical_prefix == "docs/"


def test_registry_activation_declares_complete_source_set(tmp_path):
    path, current = registry(tmp_path)
    sources, fingerprint = load_sources(path, current, multi_root_enabled=True)
    assert [source.project_id for source in sources] == ["probata", "consignatio"]
    assert len(fingerprint) == 64


def test_multi_root_activation_requires_explicit_registry(tmp_path):
    with pytest.raises(ValueError, match="requires DOCSTORE_PROJECT_REGISTRY"):
        load_sources(None, tmp_path, multi_root_enabled=True)
