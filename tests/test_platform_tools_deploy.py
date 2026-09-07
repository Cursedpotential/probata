"""Deployment-contract tests for the consolidated platform-tools image.

Byline: Codex · GPT-5 · 2026-08-16
"""

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]

REPAIR_PYTHON_PINS = {
    "beautifulsoup4": "4.15.0",
    "charset-normalizer": "3.4.9",
    "clevercsv": "0.8.5",
    "ijson": "3.5.1",
    "json-repair": "0.62.0",
    "lxml": "6.1.1",
    "pdf2image": "1.17.0",
    "pdfplumber": "0.11.10",
    "pikepdf": "10.11.0",
    "pillow": "12.3.0",
    "pypdf": "6.15.0",
    "pytesseract": "0.3.13",
}
REPAIR_FORMATS = {"xml", "html", "json", "ndjson", "csv", "pdf", "image"}


def test_sbv_image_is_immutable_and_state_uses_the_mounted_path() -> None:
    """SBV releases and SQLite state must survive a container replacement."""
    dockerfile = (ROOT / "deploy" / "docker" / "tools" / "Dockerfile").read_text(encoding="utf-8")
    supervisor = (ROOT / "deploy" / "docker" / "tools" / "supervisord.conf").read_text(encoding="utf-8")
    deployment = (ROOT / "deploy" / "platform-tools.yaml").read_text(encoding="utf-8")

    assert "FROM ghcr.io/cursedpotential/sbv-forensic@sha256:" in dockerfile
    assert 'DB_PATH_PREFIX="/opt/sbv/data"' in supervisor
    assert "/data/probata/volumes/sbv_data:/opt/sbv/data" in deployment


def test_platform_tools_image_pins_every_repair_runtime_dependency() -> None:
    dockerfile = (ROOT / "deploy" / "docker" / "tools" / "Dockerfile").read_text(encoding="utf-8")
    requirements = (ROOT / "requirements.txt").read_text(encoding="utf-8")

    for package, version in REPAIR_PYTHON_PINS.items():
        assert f"{package}=={version}" in dockerfile
        if package not in {"pdf2image", "pytesseract"}:
            assert re.search(rf"(?m)^{re.escape(package)}=={re.escape(version)}$", requirements)

    assert "poppler-utils" in dockerfile
    assert "tesseract-ocr" in dockerfile
    assert "command -v tesseract" in dockerfile
    assert "command -v pdftoppm" in dockerfile
    for forbidden_local_model_runtime in ("onnxruntime", "torch==", "transformers==", "docling=="):
        assert forbidden_local_model_runtime not in dockerfile.lower()


def test_platform_tools_build_fails_when_a_repair_engine_is_unavailable() -> None:
    dockerfile = (ROOT / "deploy" / "docker" / "tools" / "Dockerfile").read_text(encoding="utf-8")

    assert "from server.tools.repair.engines import manifest" in dockerfile
    assert "assert not missing" in dockerfile
    for format_name in REPAIR_FORMATS:
        assert f"'{format_name}'" in dockerfile
    assert "import pikepdf; assert pikepdf.__version__" in dockerfile


def test_platform_tools_deployment_healthcheck_requires_all_repair_engines() -> None:
    deployment = (ROOT / "deploy" / "platform-tools.yaml").read_text(encoding="utf-8")

    assert "/tools/repair.capabilities/run" in deployment
    assert "assert not missing" in deployment
    for format_name in REPAIR_FORMATS:
        assert f"'{format_name}'" in deployment
