"""contracts — import-light cross-domain contracts.

Deliberately dependency-free at package-import time (no sqlalchemy / agno /
duckdb): the tool-runtime facade container is dep-light and imports the
parsers, which import ``server.contracts.records``. Any heavy import here would
FATAL-loop the facade. Keep this package's ``__init__`` free of heavy deps.
"""
