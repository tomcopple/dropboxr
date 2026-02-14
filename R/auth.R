#' Authenticate with Dropbox using OAuth2
#'
#' @param app_key Your Dropbox app key
#' @param app_secret Your Dropbox app secret
#' @param cache_path Where to cache the token (default: "~/R/.dropbox_token.rds")
#' @param force_refresh Force a new authentication even if token exists
#' @export
dropbox_auth <- function(app_key = NULL,
                         app_secret = NULL,
                         cache_path = "~/R/.dropbox_token.rds",
                         force_refresh = FALSE) {

  if (!force_refresh && file.exists(cache_path)) {
    token <- readRDS(cache_path)

    if (!.dropbox_token_is_expired(token)) {
      message("Using cached token from ", cache_path)
      return(token)
    }

    refresh_token <- .dropbox_token_field(token, "refresh_token")

    if (!is.null(refresh_token) && nzchar(refresh_token)) {
      creds <- .dropbox_resolve_app_credentials(app_key, app_secret)

      client <- httr2::oauth_client(
        id = creds$app_key,
        secret = creds$app_secret,
        token_url = "https://api.dropbox.com/oauth2/token",
        name = "RStudio_TC"
      )

      refreshed_token <- httr2::oauth_flow_refresh(
        client = client,
        refresh_token = refresh_token
      )

      saveRDS(refreshed_token, cache_path)
      message("Cached token expired and was refreshed: ", cache_path)
      return(refreshed_token)
    }

    message("Cached token is expired and has no refresh token; starting new authentication flow.")
  }

  creds <- .dropbox_resolve_app_credentials(app_key, app_secret)

  client <- httr2::oauth_client(
    id = creds$app_key,
    secret = creds$app_secret,
    token_url = "https://api.dropbox.com/oauth2/token",
    name = "RStudio_TC"
  )

  token <- httr2::oauth_flow_auth_code(
    client = client,
    auth_url = "https://www.dropbox.com/oauth2/authorize?token_access_type=offline",
    redirect_uri = "http://localhost:1410/"
  )

  saveRDS(token, cache_path)
  message("Token cached to ", cache_path)

  token
}

.dropbox_resolve_app_credentials <- function(app_key, app_secret) {
  if (is.null(app_key)) {
    app_key <- Sys.getenv("DROPBOX_KEY")
  }
  if (is.null(app_secret)) {
    app_secret <- Sys.getenv("DROPBOX_SECRET")
  }

  if (app_key == "" || app_secret == "") {
    stop("Dropbox app key and secret required. Set DROPBOX_KEY and DROPBOX_SECRET environment variables or pass them as arguments.")
  }

  list(app_key = app_key, app_secret = app_secret)
}

.dropbox_token_field <- function(token, field) {
  if (!is.null(token[[field]])) {
    return(token[[field]])
  }

  if (!is.null(token$credentials) && !is.null(token$credentials[[field]])) {
    return(token$credentials[[field]])
  }

  NULL
}

.dropbox_token_is_expired <- function(token, leeway_seconds = 60) {
  expires_at <- .dropbox_token_field(token, "expires_at")

  if (is.null(expires_at)) {
    return(FALSE)
  }

  expires_at_num <- suppressWarnings(as.numeric(expires_at))
  if (is.na(expires_at_num)) {
    return(FALSE)
  }

  now_num <- as.numeric(Sys.time())
  expires_at_num <= (now_num + leeway_seconds)
}

#' Clear cached Dropbox token
#'
#' @param cache_path Path to cached token
#' @export
dropbox_clear_token <- function(cache_path = "~/R/.dropbox_token.rds") {
  if (file.exists(cache_path)) {
    file.remove(cache_path)
    message("Token cleared from ", cache_path)
  } else {
    message("No cached token found")
  }
}
