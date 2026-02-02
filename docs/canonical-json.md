# Canonical JSON Rules v1 (Watchtower)

All hashes and signatures rely on canonical serialization.

- UTF-8 encoding without BOM
- LF newlines when writing JSON files
- Object keys sorted lexicographically
- Arrays preserve order as authored by schema rules
- No insignificant whitespace (minified form recommended for hashing)
- Timestamps are data fields; never used as implicit ordering keys
- All hashes are sha256 over exact bytes of canonical JSON