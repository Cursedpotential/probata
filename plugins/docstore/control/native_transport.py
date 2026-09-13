"""Docstore lifecycle adapter using the public MCP transport and ClientSession.

The deployed endpoint acknowledges DELETE with 202. Confirm closure with a
read-only ping of that same session (404), rather than suppressing SDK logs or
rewriting HTTP status codes. Session IDs and credentials never enter diagnostics.
"""
import logging
from contextlib import asynccontextmanager

import anyio
from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client
from fastmcp.client.transports import StreamableHttpTransport

logger = logging.getLogger(__name__)


async def close_session(http, url, session_id, protocol=None):
    if not session_id:
        return {'state': 'no_session'}
    headers = {'Mcp-Session-Id': session_id, 'Accept': 'application/json, text/event-stream'}
    if protocol:
        headers['MCP-Protocol-Version'] = protocol
    outcome = {'state': 'unconfirmed'}
    try:
        with anyio.move_on_after(8, shield=True):
            response = await http.delete(url, headers=headers, timeout=3, follow_redirects=False)
            outcome['delete_status'] = response.status_code
            if response.status_code in (200, 204, 404):
                outcome['state'] = 'closed'
            elif response.status_code == 202:
                probe = await http.post(url, headers=headers, timeout=3, follow_redirects=False,
                                        json={'jsonrpc': '2.0', 'id': 'docstore-close-check', 'method': 'ping'})
                outcome['probe_status'] = probe.status_code
                if probe.status_code == 404:
                    outcome['state'] = 'closed_verified'
            elif response.status_code == 405:
                outcome['state'] = 'server_managed'
    except Exception:
        # Cleanup must not turn a committed write into an apparent failed write.
        outcome['state'] = 'unconfirmed'
    if outcome['state'] == 'unconfirmed':
        logger.warning('Docstore session cleanup unconfirmed (DELETE=%s, probe=%s); operation result is separate',
                       outcome.get('delete_status'), outcome.get('probe_status'))
    return outcome


class DocstoreTransport(StreamableHttpTransport):
    """Same official wire transport; endpoint-specific verified termination."""
    @asynccontextmanager
    async def connect_session(self, **session_kwargs):
        protocol = None
        async def remember_protocol(request):
            nonlocal protocol
            protocol = request.headers.get('MCP-Protocol-Version', protocol)
        self.cleanup_result = {'state': 'not_closed'}
        if self.httpx_client_factory is None:
            raise ValueError('Docstore requires its dedicated HTTP client factory')
        http = self.httpx_client_factory(headers=dict(self.headers), auth=self.auth)
        http.event_hooks.setdefault('request', []).append(remember_protocol)
        async with http:
            async with streamable_http_client(self.url, http_client=http, terminate_on_close=False) as transport:
                read, write, session_id = transport
                self._get_session_id_cb = session_id
                try:
                    async with ClientSession(read, write, **session_kwargs) as session:
                        yield session
                finally:
                    self.cleanup_result = await close_session(http, self.url, session_id(), protocol)
