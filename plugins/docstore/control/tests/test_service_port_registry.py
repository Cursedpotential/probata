"""Service-addressing registry is static, classified and Tailscale-only."""
import importlib.util
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[4]
SCRIPT = ROOT / "scripts/validate_service_ports.py"
spec = importlib.util.spec_from_file_location("service_port_registry_test", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def test_canonical_registry_passes_without_network_or_mutation():
    result = module.validate(ROOT / "deploy/service-port-registry.json")
    assert result == {
        "ok": True,
        "products": 3,
        "endpoints": 4,
        "canonical_ports": [8072, 8471, 8472, 8473],
        "network_accessed": False,
        "live_state_modified": False,
    }


@pytest.mark.parametrize("change", [
    lambda data: data["products"]["docstore"].update(code="73"),
    lambda data: data["products"]["docstore"]["endpoints"][1].update(canonical_backend_port=8074),
    lambda data: data["products"]["docstore"]["endpoints"][1].update(client_endpoint="http://100.91.190.107:8072"),
    lambda data: data["products"]["docstore"]["endpoints"][1].update(client_endpoint="https://docstore-api.example.com"),
])
def test_registry_rejects_identity_or_addressing_drift(tmp_path, change):
    data = json.loads((ROOT / "deploy/service-port-registry.json").read_text(encoding="utf-8"))
    change(data)
    path = tmp_path / "registry.json"
    path.write_text(json.dumps(data), encoding="utf-8")
    with pytest.raises(module.RegistryError):
        module.validate(path)
