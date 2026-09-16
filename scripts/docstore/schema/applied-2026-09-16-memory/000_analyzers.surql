-- 000_analyzers.surql
-- Analyzers must exist before any FULLTEXT index references them.
-- Copied verbatim from surreal-docstore kit schema/000_analyzers.surql.

DEFINE ANALYZER OVERWRITE doc_text
  TOKENIZERS class
  FILTERS lowercase, ascii, snowball(english);

-- Code/identifier-friendly analyzer: no stemming, keeps camelCase splits usable.
DEFINE ANALYZER OVERWRITE doc_code
  TOKENIZERS class, punct
  FILTERS lowercase, ascii;
