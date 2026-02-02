#' Create a Dropbox API request
#'
#' @description
#' Creates an authenticated request to the Dropbox API. This is a low-level
#' function used by other dropboxr functions. You typically won't need to
#' call this directly unless you're implementing additional Dropbox API
#' endpoints.
#'
#' @param endpoint API endpoint path (e.g., "/files/download")
#' @param api_type Type of API: "api" or "content"
#' @param token OAuth token from dropbox_auth() (if NULL, uses cached token)
#' @param cache_path Path to cached token
#'
#' @return An httr2 request object ready to be executed with req_perform()
#'
#' @details
#' The Dropbox API has two base URLs:
#' - "api" for metadata operations (listing files, getting info, etc.)
#' - "content" for content operations (downloading/uploading files)
#'
#' If a cached token exists and contains refresh token information, the
#' request will automatically refresh the token when needed.
#'
#' @examples
#' \dontrun{
#' # Create a request for file metadata
#' req <- dropbox_request("/files/get_metadata", api_type = "api")
#'
#' # Execute the request
#' resp <- req |>
#'   httr2::req_body_json(list(path = "/my/file.txt")) |>
#'   httr2::req_perform()
#' }
#'
#' @seealso [dropbox_auth()], [download_dropbox_file()], [upload_dropbox_file()]
#'
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

  print("Extracting access token")
  # Extract access token based on what we received
  if (is.character(token)) {
    # Plain string - use directly
    access_token <- token
  } else if (!is.null(token$credentials$access_token)) {
    # httr2_token object
    access_token <- token$credentials$access_token
  } else if (!is.null(token$access_token)) {
    # Simple list with access_token
    access_token <- token$access_token
  } else {
    stop("Could not extract access token from token object")
  }


  # Check if we have refresh token capability
  # if (!is.null(token$refresh_token) && !is.null(token$client)) {
  #   # Use refresh flow
  #   httr2::request(base_url) |>
  #     httr2::req_url_path_append(endpoint) |>
  #     httr2::req_oauth_refresh(
  #       client = token$client,
  #       refresh_token = token$refresh_token
  #     )
  # } else {
    # Fall back to bearer token
    httr2::request(base_url) |>
      httr2::req_url_path_append(endpoint) |>
      httr2::req_auth_bearer_token(access_token)
  # }
}

#' Download a file from Dropbox
#'
#' @description
#' Downloads a CSV file from Dropbox and reads it directly into R as a tibble.
#' The file is not saved to disk - it's read directly from the API response
#' into memory.
#'
#' @param dropbox_path Path to file in Dropbox (e.g., "/data/myfile.csv").
#'   Must start with a forward slash.
#' @param token OAuth token from dropbox_auth() (if NULL, uses cached token)
#' @param cache_path Path to cached token (default: "~/.dropbox_token.rds")
#'
#' @return A tibble containing the CSV data
#'
#' @details
#' This function currently only supports CSV files. The file is downloaded
#' as raw bytes, converted to a character string, and parsed by readr::read_csv().
#'
#' For non-CSV files or more control over the download process, you'll need
#' to use dropbox_request() directly and handle the response yourself.
#'
#' @examples
#' \dontrun{
#' # Download a CSV file
#' sales_data <- download_dropbox_file("/data/sales_2024.csv")
#'
#' # Use with specific token
#' work_token <- dropbox_auth(cache_path = "~/.dropbox_work.rds")
#' data <- download_dropbox_file("/reports/monthly.csv", token = work_token)
#'
#' # Download and process in a pipeline
#' data <- download_dropbox_file("/raw/data.csv") |>
#'   filter(date >= "2024-01-01") |>
#'   mutate(total = price * quantity)
#' }
#'
#' @note
#' Make sure your Dropbox path starts with "/" and uses forward slashes,
#' not backslashes.
#'
#' @seealso [upload_dropbox_file()], [upload_df_to_dropbox()], [dropbox_request()]
#'
#' @export
download_dropbox_file <- function(dropbox_path,
                                  token = NULL,
                                  cache_path = "~/R/.dropbox_token.rds") {

  resp <- dropbox_request("/files/download",
                          api_type = "content",
                          token = token,
                          cache_path = cache_path) |>
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
#' @description
#' Uploads a file from your local filesystem to Dropbox. This function reads
#' the entire file into memory before uploading, so it's best suited for
#' files under 150MB. For larger files, consider using Dropbox's upload
#' session API.
#'
#' @param local_path Path to local file to upload. File must exist.
#' @param dropbox_path Destination path in Dropbox (e.g., "/data/myfile.csv").
#'   Must start with a forward slash.
#' @param mode Write mode:
#'   - "add": Fail if file exists (default)
#'   - "overwrite": Replace existing file
#'   - "update": Update existing file (fails if file doesn't exist)
#' @param token OAuth token from dropbox_auth() (if NULL, uses cached token)
#' @param cache_path Path to cached token (default: "~/.dropbox_token.rds")
#'
#' @return Response from Dropbox API as a list containing file metadata
#'   including: name, path_display, id, client_modified, server_modified,
#'   rev, size, and content_hash
#'
#' @details
#' **Important:** If you're creating data programmatically (like a data frame),
#' you'll need to write it to a temporary file first, upload it, then clean up.
#' See examples below or use the convenience function upload_df_to_dropbox().
#'
#' The function reads the entire file into memory as raw bytes before uploading,
#' so very large files may cause memory issues. The Dropbox API limit for
#' single uploads is 150MB.
#'
#' @examples
#' \dontrun{
#' # Upload an existing file
#' upload_dropbox_file("mydata.csv", "/backup/mydata.csv")
#'
#' # Overwrite an existing file
#' upload_dropbox_file("updated.csv", "/data/report.csv", mode = "overwrite")
#'
#' # Create and upload a data frame (manual approach)
#' temp_file <- tempfile(fileext = ".csv")
#' write_csv(my_data, temp_file)
#' upload_dropbox_file(temp_file, "/data/my_data.csv", mode = "overwrite")
#' unlink(temp_file)  # Don't forget to clean up!
#'
#' # Better pattern with on.exit() - ensures cleanup even if upload fails
#' upload_my_data <- function(df, dropbox_path) {
#'   temp_file <- tempfile(fileext = ".csv")
#'   on.exit(unlink(temp_file))  # Automatic cleanup
#'   write_csv(df, temp_file)
#'   upload_dropbox_file(temp_file, dropbox_path, mode = "overwrite")
#' }
#'
#' # Or just use the convenience function!
#' upload_df_to_dropbox(my_data, "/data/my_data.csv")
#' }
#'
#' @note
#' **Remember to clean up temporary files!**
#' - Use `tempfile()` to create temporary files
#' - Use `unlink()` to delete them after upload
#' - Use `on.exit(unlink(temp_file))` to ensure cleanup happens even if errors occur
#'
#' For uploading data frames directly, consider using upload_df_to_dropbox()
#' which handles the temporary file creation and cleanup automatically.
#'
#' @seealso [download_dropbox_file()], [upload_df_to_dropbox()], [tempfile()], [unlink()]
#'
#' @export
upload_dropbox_file <- function(local_path,
                                dropbox_path,
                                mode = "add",
                                token = NULL,
                                cache_path = "~/R/.dropbox_token.rds") {

  if (!file.exists(local_path)) {
    stop("File not found: ", local_path)
  }

  file_content <- readBin(local_path, "raw", file.info(local_path)$size)

  resp <- dropbox_request("/files/upload",
                          api_type = "content",
                          token = token,
                          cache_path = cache_path) |>
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

#' Upload a data frame to Dropbox as CSV
#'
#' @description
#' Convenience wrapper that writes a data frame to a temporary CSV file,
#' uploads it to Dropbox, and automatically cleans up the temporary file.
#' This is the recommended way to upload data frames to Dropbox.
#'
#' @param df Data frame or tibble to upload
#' @param dropbox_path Destination path in Dropbox (e.g., "/data/myfile.csv").
#'   Must start with a forward slash and should end with .csv
#' @param mode Write mode:
#'   - "add": Fail if file exists (default)
#'   - "overwrite": Replace existing file
#'   - "update": Update existing file (fails if file doesn't exist)
#' @param token OAuth token from dropbox_auth() (if NULL, uses cached token)
#' @param cache_path Path to cached token (default: "~/.dropbox_token.rds")
#' @param ... Additional arguments passed to `readr::write_csv()`
#'
#' @return Response from Dropbox API as a list containing file metadata
#'
#' @details
#' This function handles all the temporary file management for you:
#' 1. Creates a temporary CSV file
#' 2. Writes your data frame to it
#' 3. Uploads it to Dropbox
#' 4. Deletes the temporary file (even if upload fails)
#'
#' The temporary file is automatically cleaned up using on.exit(), so you
#' don't need to worry about orphaned temp files even if something goes wrong.
#'
#' @examples
#' \dontrun{
#' # Simple upload
#' upload_df_to_dropbox(mtcars, "/data/mtcars.csv")
#'
#' # Overwrite existing file
#' upload_df_to_dropbox(iris, "/data/iris.csv", mode = "overwrite")
#'
#' # Use in a pipeline
#' mtcars |>
#'   filter(mpg > 20) |>
#'   mutate(kpl = mpg * 0.425) |>
#'   upload_df_to_dropbox("/data/efficient_cars.csv", mode = "overwrite")
#'
#' # Pass additional arguments to write_csv
#' upload_df_to_dropbox(
#'   my_data,
#'   "/data/output.csv",
#'   mode = "overwrite",
#'   na = "NULL",
#'   quote = "all"
#' )
#' }
#'
#' @seealso [upload_dropbox_file()], [download_dropbox_file()], [readr::write_csv()]
#'
#' @export
upload_df_to_dropbox <- function(df,
                                 dropbox_path,
                                 mode = "overwrite",
                                 token = NULL,
                                 cache_path = "~/R/.dropbox_token.rds",
                                 ...) {

  temp_file <- tempfile(fileext = ".csv")
  on.exit(unlink(temp_file))

  readr::write_csv(df, temp_file, ...)
  upload_dropbox_file(temp_file, dropbox_path, mode = mode, token = token, cache_path = cache_path)
}
