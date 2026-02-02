#' Authenticate with Dropbox using OAuth2
#'
#' @param app_key Your Dropbox app key
#' @param app_secret Your Dropbox app secret
#' @param cache_path Where to cache the token (default: "~/.dropbox_token.rds")
#' @param force_refresh Force a new authentication even if token exists
#' @export
dropbox_auth <- function(app_key = NULL,
                         app_secret = NULL,
                         cache_path = "~/R/.dropbox_token.rds",
                         force_refresh = FALSE) {

  # Try to load cached token first
  if (!force_refresh && file.exists(cache_path)) {
    message("Using cached token from ", cache_path)
    token <- readRDS(cache_path)
    return(token)
  }

  # Get credentials from environment if not provided
  if (is.null(app_key)) {
    app_key <- Sys.getenv("DROPBOX_KEY")
  }
  if (is.null(app_secret)) {
    app_secret <- Sys.getenv("DROPBOX_SECRET")
  }

  if (app_key == "" || app_secret == "") {
    stop("Dropbox app key and secret required. Set DROPBOX_KEY and DROPBOX_SECRET environment variables or pass them as arguments.")
  }

  # Create OAuth client
  client <- httr2::oauth_client(
    id = app_key,
    secret = app_secret,
    token_url = "https://api.dropbox.com/oauth2/token",
    name = "RStudio_TC"
  )

  # Perform OAuth flow
  token <- httr2::oauth_flow_auth_code(
    client = client,
    auth_url = "https://www.dropbox.com/oauth2/authorize?token_access_type=offline",
    redirect_uri = "http://localhost:1410/"
  )

  # Cache the token
  saveRDS(token, cache_path)
  message("Token cached to ", cache_path)

  token
}

#' Clear cached Dropbox token
#'
#' @param cache_path Path to cached token
#' @export
dropbox_clear_token <- function(cache_path = "~/.dropbox_token.rds") {
  if (file.exists(cache_path)) {
    file.remove(cache_path)
    message("Token cleared from ", cache_path)
  } else {
    message("No cached token found")
  }
}
