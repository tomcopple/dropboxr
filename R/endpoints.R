#' Create a Dropbox API request
#'
#' @param endpoint API endpoint path (e.g., "/files/download")
#' @param api_type Type of API: "api" or "content"
#' @param token OAuth token from dropbox_auth() (if NULL, uses cached token)
#' @param cache_path Path to cached token
#' @return An httr2 request object
#' @export
dropbox_request <- function(endpoint,
                            api_type = "api",
                            token = NULL,
                            cache_path = "~/R/.dropbox_token.rds") {

  base_url <- switch(api_type,
                     "api" = "https://api.dropboxapi.com/2",
                     "content" = "https://content.dropboxapi.com/2",
                     stop("Invalid api_type. Must be 'api' or 'content'")
  )

  # Load token if not provided
  if (is.null(token)) {
    if (file.exists(cache_path)) {
      token <- readRDS(cache_path)
    } else {
      stop("No token provided. Run dropbox_auth() first.")
    }
  }

  # Extract client info from token for refresh
  client <- httr2::oauth_client(
    id = token$client$id,
    secret = token$client$secret,
    token_url = token$client$token_url,
    name = token$client$name
  )

  httr2::request(base_url) |>
    httr2::req_url_path_append(endpoint) |>
    httr2::req_oauth_refresh(
      client = client,
      refresh_token = token$refresh_token
    )
}

#' Download a csv from Dropbox
#'
#' @param dropbox_path Path to file in Dropbox (e.g., "/data/myfile.csv")
#' @param token OAuth token from dropbox_auth() (if NULL, uses cached token)
#' @return A tibble with the CSV data
#' @export
download_dropbox_csv <- function(dropbox_path, token = NULL) {

  resp <- dropbox_request("/files/download",
                          api_type = "content",
                          token = token) |>
    httr2::req_headers(
      `Dropbox-API-Arg` = jsonlite::toJSON(
        list(path = dropbox_path),
        auto_unbox = TRUE
      )
    ) |>
    httr2::req_perform() |>
    httr2::resp_body_raw()

  readr::read_csv(rawToChar(resp), show_col_types = FALSE)
}

#' Upload a file to Dropbox
#'
#' @param local_path Path to local file to upload
#' @param dropbox_path Destination path in Dropbox (e.g., "/data/myfile.csv")
#' @param mode Write mode: "add", "overwrite", or "update"
#' @param token OAuth token from dropbox_auth() (if NULL, uses cached token)
#' @return Response from Dropbox API as a list
#' @details
#' **Important** Best practise is to create a tempfile, upload the tempfile,
#' then unlink the tempfile
#' @examples
#' \dontrun{
#' # E.g. to upload a csv file
#' temp_file <- tempfile(fileext = ".csv")
#' write_csv(data, temp_file)
#' upload_dropbox(temp_file, "/R/data/data.csv")
#' unlink(temp_file)
#' }
#' @export
upload_dropbox <- function(local_path,
                                dropbox_path,
                                mode = "overwrite",
                                token = NULL) {

  if (!file.exists(local_path)) {
    stop("File not found: ", local_path)
  }

  file_content <- readBin(local_path, "raw", file.info(local_path)$size)

  resp <- dropbox_request("/files/upload",
                          api_type = "content",
                          token = token) |>
    httr2::req_headers(
      `Dropbox-API-Arg` = jsonlite::toJSON(
        list(
          path = dropbox_path,
          mode = mode,
          autorename = FALSE,
          mute = FALSE
        ),
        auto_unbox = TRUE
      ),
      `Content-Type` = "application/octet-stream"
    ) |>
    httr2::req_body_raw(file_content) |>
    httr2::req_perform()

  httr2::resp_body_json(resp)
}
