"""Source contracts for Authentik provider and Workbench consumer manifests.

These tests are intentionally offline. Live Traefik routing, Authentik provider
creation, DNS, and Coolify deployment remain separate release gates.

Byline: Codex · GPT-5 · 2026-08-29
Byline amendment: Codex · GPT-5 · 2026-08-29 (official 2026.8 contract)
"""

from __future__ import annotations

from pathlib import Path

import yaml


AUTHENTIK_PATH = Path("deploy/authentik.yaml")
WORKBENCH_PATH = Path("deploy/workbench.yaml")
AUTHENTIK_IMAGE = (
    "ghcr.io/goauthentik/server:2026.8.0@sha256:7421753cfea67e89a6d295a1f0173ccea3866b33768c88dad90453b151cdcfd5"
)
AUTHENTIK_RUNTIME_IMAGE = "probata-authentik:2026.8.0"
AUTHENTIK_DOCKERFILE = Path("deploy/docker/authentik/Dockerfile")
AUTHENTIK_BLUEPRINT = Path("deploy/docker/authentik/blueprints/probata-workbench.yaml")
POSTGRES_IMAGE = (
    "docker.io/library/postgres:18-alpine@sha256:d3e1620b530c944afa6e887d22eb899824da68e19c52024bf98f5220c88a65b2"
)
AUTHENTIK_EXACT_PROXY_SETTING = "${TRAEFIK_PROXY_CIDR:?exact Traefik proxy CIDR required}"
# Coolify 4.1.2 renders Compose's `:?message` form as the literal message when
# the variable is absent. Workbench uses plain substitution and its own auth
# boundary rejects an empty or malformed value at runtime.
WORKBENCH_EXACT_PROXY_SETTING = "${TRAEFIK_PROXY_CIDR}"
FORWARD_AUTH_ADDRESS = "http://authentik-server:9000/outpost.goauthentik.io/auth/traefik"


def _load(path: Path) -> dict:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def _labels(service: dict) -> str:
    return "\n".join(str(label) for label in service.get("labels", []))


def _secret_mounts(service: dict) -> list[str]:
    return [mount for mount in service.get("volumes", []) if isinstance(mount, str) and "/run/secrets/" in mount]


class TestAuthentikProvider:
    def test_official_2026_8_service_shape(self) -> None:
        services = _load(AUTHENTIK_PATH)["services"]
        assert set(services) == {
            "authentik-postgres",
            "authentik-server",
            "authentik-worker",
        }
        assert services["authentik-server"]["command"] == "server"
        assert services["authentik-worker"]["command"] == "worker"

    def test_images_are_exact_tag_and_digest_pinned(self) -> None:
        services = _load(AUTHENTIK_PATH)["services"]
        for name in ("authentik-server", "authentik-worker"):
            assert services[name]["image"] == AUTHENTIK_RUNTIME_IMAGE
            assert services[name]["build"] == {
                "context": ".",
                "dockerfile": "deploy/docker/authentik/Dockerfile",
            }
        dockerfile = AUTHENTIK_DOCKERFILE.read_text(encoding="utf-8")
        assert f"FROM {AUTHENTIK_IMAGE}" in dockerfile
        assert services["authentik-postgres"]["image"] == POSTGRES_IMAGE

    def test_redis_removed_from_current_contract(self) -> None:
        compose = _load(AUTHENTIK_PATH)
        assert "authentik-redis" not in compose["services"]
        for service in compose["services"].values():
            assert all(not key.startswith("AUTHENTIK_REDIS__") for key in service.get("environment", {}))

    def test_official_authentik_environment_names_and_file_uris(self) -> None:
        services = _load(AUTHENTIK_PATH)["services"]
        expected = {
            "AUTHENTIK_POSTGRESQL__HOST": "authentik-postgres",
            "AUTHENTIK_POSTGRESQL__PORT": "5432",
            "AUTHENTIK_POSTGRESQL__USER": "authentik",
            "AUTHENTIK_POSTGRESQL__NAME": "authentik",
            "AUTHENTIK_POSTGRESQL__PASSWORD": ("file:///run/secrets/authentik/postgres-password"),
            "AUTHENTIK_SECRET_KEY": "file:///run/secrets/authentik/secret-key",
            "AUTHENTIK_LISTEN__TRUSTED_PROXY_CIDRS": AUTHENTIK_EXACT_PROXY_SETTING,
        }
        for name in ("authentik-server", "authentik-worker"):
            assert services[name]["environment"] == expected

        text = AUTHENTIK_PATH.read_text(encoding="utf-8")
        assert "AUTHENTIK_POSTGRES__" not in text
        assert "AUTHENTIK_SECRET_KEY_FILE" not in text

    def test_secret_mounts_are_read_only(self) -> None:
        services = _load(AUTHENTIK_PATH)["services"]
        for name in services:
            for mount in _secret_mounts(services[name]):
                assert mount.endswith(":ro")
        for name in ("authentik-server", "authentik-worker"):
            assert len(_secret_mounts(services[name])) == 2

    def test_empty_host_templates_do_not_shadow_packaged_templates(self) -> None:
        services = _load(AUTHENTIK_PATH)["services"]
        for name in ("authentik-server", "authentik-worker"):
            assert all(
                not str(mount).split(":", maxsplit=1)[0].endswith("/templates")
                for mount in services[name].get("volumes", [])
            )

    def test_official_authentik_healthcheck_is_used(self) -> None:
        services = _load(AUTHENTIK_PATH)["services"]
        for name in ("authentik-server", "authentik-worker"):
            assert services[name]["healthcheck"]["test"] == [
                "CMD",
                "ak",
                "healthcheck",
            ]

    def test_postgres_gate_is_readiness_not_unrequired_extensions(self) -> None:
        postgres = _load(AUTHENTIK_PATH)["services"]["authentik-postgres"]
        command = " ".join(postgres["healthcheck"]["test"])
        assert "pg_isready" in command
        assert "pgcrypto" not in command
        assert "uuid-ossp" not in command
        assert all("docker-entrypoint-initdb.d" not in volume for volume in postgres["volumes"])

    def test_no_host_port_or_docker_socket_bypass(self) -> None:
        services = _load(AUTHENTIK_PATH)["services"]
        for service in services.values():
            assert not service.get("ports")
            assert "docker.sock" not in "\n".join(service.get("volumes", []))

    def test_authentik_router_uses_traefik_only(self) -> None:
        server = _load(AUTHENTIK_PATH)["services"]["authentik-server"]
        labels = _labels(server)
        assert "traefik.enable=true" in labels
        assert "Host(`auth.int.mitechconsult.com`)" in labels
        assert "entrypoints=https" in labels
        assert "loadbalancer.server.port=9000" in labels
        assert "basicauth" not in labels.lower()

    def test_workbench_outpost_path_routes_to_embedded_outpost(self) -> None:
        server = _load(AUTHENTIK_PATH)["services"]["authentik-server"]
        labels = _labels(server)
        assert "authentik-workbench-outpost.rule=Host(`workbench.int.mitechconsult.com`)" in labels
        assert "PathPrefix(`/outpost.goauthentik.io/`)" in labels
        assert "authentik-workbench-outpost.priority=15" in labels
        assert "authentik-workbench-outpost.service=authentik" in labels

    def test_blueprint_pins_single_app_provider_and_embedded_outpost(self) -> None:
        text = AUTHENTIK_BLUEPRINT.read_text(encoding="utf-8")
        assert "mode: forward_single" in text
        assert "external_host: https://workbench.int.mitechconsult.com" in text
        assert "name: authentik Embedded Outpost" in text
        assert "- !KeyOf probata-workbench-provider" in text


class TestWorkbenchConsumer:
    def test_private_tailscale_door_is_loopback_only_and_port_translated(self) -> None:
        service = _load(WORKBENCH_PATH)["services"]["workbench"]
        assert service.get("ports") == ["127.0.0.1:18080:8020"]
        assert all("0.0.0.0" not in binding for binding in service["ports"])

    def test_exact_proxy_boundary_is_required_in_manifest(self) -> None:
        service = _load(WORKBENCH_PATH)["services"]["workbench"]
        assert service["environment"]["TRUSTED_AUTH_PROXY_CIDRS"] == WORKBENCH_EXACT_PROXY_SETTING
        text = WORKBENCH_PATH.read_text(encoding="utf-8")
        assert 'TRUSTED_AUTH_PROXY_CIDRS: "10.0.0.0/8' not in text
        assert 'TRUSTED_AUTH_PROXY_CIDRS: "172.16.0.0/12' not in text

    def test_forward_auth_is_defined_and_attached(self) -> None:
        service = _load(WORKBENCH_PATH)["services"]["workbench"]
        labels = _labels(service)
        assert (f"traefik.http.middlewares.workbench-authentik.forwardauth.address={FORWARD_AUTH_ADDRESS}") in labels
        assert ("traefik.http.middlewares.workbench-authentik.forwardauth.trustForwardHeader=true") in labels
        assert "X-authentik-uid" in labels
        assert "X-authentik-username" in labels
        assert "traefik.http.routers.workbench.middlewares=workbench-authentik" in labels
        assert "coolify.traefik.middlewares=workbench-authentik" in labels

    def test_https_router_targets_workbench(self) -> None:
        labels = _labels(_load(WORKBENCH_PATH)["services"]["workbench"])
        assert "Host(`workbench.int.mitechconsult.com`)" in labels
        assert "traefik.http.routers.workbench.priority=10" in labels
        assert "entrypoints=https" in labels
        assert "loadbalancer.server.port=8020" in labels

    def test_no_basic_auth_or_password_ingress_contract(self) -> None:
        service = _load(WORKBENCH_PATH)["services"]["workbench"]
        labels = _labels(service).lower()
        assert "basicauth" not in labels
        assert "OPENCODE_PASSWORD" not in service["environment"]


class TestSharedBoundary:
    def test_both_manifests_use_external_agno_network(self) -> None:
        for path in (AUTHENTIK_PATH, WORKBENCH_PATH):
            compose = _load(path)
            assert compose["networks"]["probata"]["external"] is True

    def test_no_literal_credentials_in_authentik_manifest(self) -> None:
        services = _load(AUTHENTIK_PATH)["services"]
        for service in services.values():
            for key, value in service.get("environment", {}).items():
                if key in {"AUTHENTIK_SECRET_KEY", "AUTHENTIK_POSTGRESQL__PASSWORD"}:
                    assert value.startswith("file:///run/secrets/authentik/")
                if key == "POSTGRES_PASSWORD_FILE":
                    assert value.startswith("/run/secrets/authentik/")

    def test_no_basic_auth_anywhere_in_provider_or_consumer(self) -> None:
        for path in (AUTHENTIK_PATH, WORKBENCH_PATH):
            compose = _load(path)
            for service in compose["services"].values():
                assert "basicauth" not in _labels(service).lower()
