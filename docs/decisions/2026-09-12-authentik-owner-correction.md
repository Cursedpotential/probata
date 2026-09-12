# Owner correction: Authentik and the two access lanes

**Status:** current owner authority, 2026-09-12  
**Supersedes:** the Authentik-rejection and OIDC-only portions of D-133, the matching `SETTLED.md` row, and downstream documents derived from those portions

Authentik was not rejected. The first Authentik deployment attempt was defective. The later claim that Authentik, its reverse-proxy integration, or Traefik forward authentication had been rejected was generated without owner authority and must not control implementation.

The required architecture has two intentionally different access lanes:

1. **Trusted owner lane:** the owner's enrolled systems use the existing Tailscale routes with unfettered, total access. These routes remain exactly as they are. They are not narrowed, removed, replaced, repointed, or forced through Authentik.
2. **Public browser lane:** any ordinary outside computer uses public HTTPS through the existing Coolify Traefik reverse proxy. Authentik owns login, access policy, session, and the application launcher. Only explicitly approved human-facing web surfaces are routed publicly.

Cloudflare is the DNS provider and its role ends at DNS. Do not add Cloudflare Tunnel, Cloudflare Access, Workers, or another Cloudflare application-authentication layer.

Applications that support OIDC should use the authorization-code flow and validate issuer, audience, signature, expiry, state, and nonce through a server-side session boundary. Applications without suitable native OIDC support may use an Authentik proxy provider/embedded outpost, but must accept identity headers only from the exact trusted Traefik peer. A signing key, service bearer, or shared secret must never be delivered to browser code.

The public proxy must not expose databases, workers, internal APIs, tool runtime, tool gateway, storage bridges, native/Tauri command surfaces, or other infrastructure endpoints. A same-origin server-side BFF may reach an internal API only under the authenticated application session and the product's own authorization rules.

Each public surface requires live proof of public DNS and TLS, unauthenticated redirect or denial, approved-user login, session-bound application use, direct-origin bypass resistance, logout/session expiry, and unchanged Tailscale access.
