"""Credential-free static view of real flag results. No remote scripts or HTML injection."""
from html import escape


def render(result: dict) -> str:
    cards = []
    for flag in result["flags"]:
        text = lambda key: escape(str(flag.get(key, "")))
        cards.append(f'<article><div class="badges"><b>{text("priority").upper()}</b>'
                     f'<span>{text("authority")}</span><span>{text("status")}</span></div>'
                     f'<h2>{text("title")}</h2><p>{text("summary")}</p>'
                     f'<dl><dt>Subject</dt><dd>{text("subject")}</dd><dt>Source</dt><dd>{text("source_ref")}</dd>'
                     f'<dt>Rationale</dt><dd>{text("rationale")}</dd><dt>Revision / actor</dt><dd>{text("revision")} / {text("actor")}</dd></dl></article>')
    return ('<!doctype html><html lang="en"><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width,initial-scale=1">'
            '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; style-src \'unsafe-inline\'">'
            '<title>Docstore — critical notes and decisions</title><style>'
            'body{font:16px system-ui;background:#101722;color:#e8edf4;max-width:1000px;margin:40px auto;padding:0 24px}'
            'article{background:#1c2634;padding:24px;margin:20px 0;border:1px solid #40516b;border-radius:12px}'
            '.badges{display:flex;gap:12px;flex-wrap:wrap}.badges>*{padding:5px 10px;background:#33455e;border-radius:5px}'
            'b{color:#ffd68a}p,dd{white-space:pre-wrap;overflow-wrap:anywhere;line-height:1.6}dt{color:#a8b7cb;margin-top:12px}dd{margin:4px 0}'
            '</style><h1>Docstore · notes and decisions</h1><p>Scope: '
            + escape(result["domain"]) + '. Priority is not authority. Snapshot, not live monitoring.</p>'
            + ("<p>More flags exist: narrow the scope or query the store.</p>" if result.get("truncated") else "")
            + ("".join(cards) or "<p>No matching flags.</p>") + '</html>')
