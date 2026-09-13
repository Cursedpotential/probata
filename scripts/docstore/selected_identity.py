"""Pure, non-secret identity digest for Docstore selected-CDC topology."""
from dataclasses import asdict, dataclass
import hashlib
import json


@dataclass(frozen=True)
class SelectedBootstrapIdentity:
    """Fields whose exact digest admits an already bootstrapped topology."""

    app: str
    environment: str
    topology: str
    source: str
    tracking: str
    target: str
    processing_profile: str

    def __post_init__(self):
        for name, value in asdict(self).items():
            if not isinstance(value, str) or not value.strip() or len(value) > 500:
                raise ValueError(f'Bootstrap identity {name} must be a nonempty bounded string')

    def digest(self) -> str:
        payload=json.dumps(asdict(self),sort_keys=True,separators=(',',':'),ensure_ascii=True)
        return hashlib.sha256(payload.encode('utf-8')).hexdigest()
