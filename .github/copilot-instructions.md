# GitHub Copilot instructions for dropboxr 🔧

## Quick summary
- This is an R package that wraps Dropbox HTTP endpoints using `httr2`.
- Key exported functions: `dropbox_auth()`, `dropbox_request()`, `download_dropbox_csv()`, `upload_dropbox()`, `dropbox_clear_token()`.
- Tokens are cached to a file by default (code: `"~/R/.dropbox_token.rds"`), and credentials come from `DROPBOX_KEY` / `DROPBOX_SECRET` environment variables.

---

## Big picture & patterns 💡
- Architecture: a small R package (R/ + man/) that encapsulates Dropbox API calls using `httr2` request building and `|>` pipes. Endpoints build requests then call `httr2::req_perform()` and convert responses (e.g. `resp_body_raw()` + `readr::read_csv()`, or `resp_body_json()`).
- API split: code distinguishes API hosts by `api_type`:
  - "api" → `https://api.dropboxapi.com/2`
  - "content" → `https://content.dropboxapi.com/2`
  Example: `download_dropbox_csv()` uses `/files/download` on the "content" base and sends `Dropbox-API-Arg` JSON header.
- OAuth flow: uses `httr2::oauth_flow_auth_code()` with `token_access_type=offline` (refresh tokens supported). Tokens are saved as RDS and contain `access_token`, `refresh_token`, and `client` info.

---

## Project-specific conventions & gotchas ⚠️
- Token cache path mismatch: documentation strings show `~/.dropbox_token.rds` but the code currently uses `~/R/.dropbox_token.rds`. Treat the code's `~/R/.dropbox_token.rds` as canonical until the code/docs are harmonized.
- Duplicate function definitions: there are two definitions of `dropbox_request()` (see `R/auth.R` and `R/endpoints.R`). The `R/endpoints.R` variant is the more feature-complete (supports endpoints, api_type, and token refresh). Be careful when editing—remove or consolidate duplicates to avoid unexpected behavior.
- Re-export: the magrittr pipe (`%>%`) is re-exported in `NAMESPACE` to keep compatibility, even though code uses the base `|>` pipe.
- Upload pattern: `upload_dropbox()` reads file bytes with `readBin()` and sets `Content-Type: application/octet-stream` plus `Dropbox-API-Arg` header (JSON with `path`, `mode`, etc.). Prefer uploading tempfiles (see function docs example).

---

## How I (an AI agent) should change code or add features ✅
- Prefer editing `R/endpoints.R` implementation of `dropbox_request()` and remove the duplicate in `R/auth.R` (or rename the simpler helper if both are needed). Update `man/` by running `devtools::document()` after changes.
- Standardize the token cache path (pick `~/.dropbox_token.rds` or `~/R/.dropbox_token.rds`) and update all places (docs + examples).
- When adding new endpoints, follow the `httr2` pattern used in `download_dropbox_csv()` and `upload_dropbox()` (build request with base/url, add `Dropbox-API-Arg` header for content endpoints, use `req_perform()`, then appropriate `resp_body_*`).

---

## Developer workflows & commands 🧰
- Regenerate docs & NAMESPACE:
  - In R: `devtools::document()` (relies on roxygen2). That updates `man/` and `NAMESPACE`.
- Run checks locally:
  - `devtools::check()` or `R CMD check .`
- Build package tarball:
  - `devtools::build()` or `R CMD build .`
- Authentication & quick manual testing:
  - Set env vars: `export DROPBOX_KEY=... && export DROPBOX_SECRET=...`
  - Run: `token <- dropbox_auth(force_refresh = TRUE)` (this opens the OAuth flow using `http://localhost:1410/`).
  - Example: `download_dropbox_csv("/path/in/dropbox.csv")` to verify download flow.

---

## Integration & external deps 🔗
- Primary runtime deps: `httr2`, `jsonlite`, `readr`, `magrittr` (re-exported `%>%`).
- OAuth redirect and refresh are implemented via `httr2`. Tokens produced by `oauth_flow_auth_code()` must be saved/loaded as RDS for subsequent calls.
- `.gitignore` already excludes `.httr-oauth` session files; ensure any created token RDS files are not accidentally committed.

---

## Notes for reviewers / future AI agents 📋
- If behavior seems wrong for token refreshing, inspect which `dropbox_request()` implementation is actually exported (search for duplicates) and test flows that use refresh tokens.
- Check and fix inconsistencies between docs and code (cache path, exported symbols).

---

If any section is unclear, or you'd like more examples (e.g., a new helper for chunked uploads or tests for token refresh), tell me which part to expand or a preferred canonical `cache_path` and I'll iterate. ✅