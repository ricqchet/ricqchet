defmodule RicqchetWeb.CorsConfig do
  @moduledoc """
  CORS configuration for the API.

  In development, allows localhost origins by default.
  In production, reads allowed origins from the CORS_ALLOWED_ORIGINS environment variable.

  ## Configuration

  The following options are configurable in `config/config.exs`:

    * `:allowed_origins` - List of allowed origins (default: localhost origins)
    * `:allow_credentials` - Whether to allow credentials (default: true)
    * `:max_age` - Cache duration for preflight responses in seconds (default: 86400)

  ## Environment Variables

  In production, set the following environment variable:

    * `CORS_ALLOWED_ORIGINS` - Comma-separated list of allowed origins
      Example: "https://app.example.com,https://dashboard.example.com"
  """

  @doc """
  Checks if the given origin is allowed.

  Returns true if the origin is in the allowed origins list.
  In production, reads from CORS_ALLOWED_ORIGINS environment variable.

  This function is called by Corsica with (conn, origin) arguments.
  """
  def allowed_origin?(_conn, origin) do
    allowed_origins = get_allowed_origins()
    origin in allowed_origins
  end

  @doc """
  Gets the list of allowed origins from configuration or environment.
  """
  def get_allowed_origins do
    case System.get_env("CORS_ALLOWED_ORIGINS") do
      nil ->
        config = Application.get_env(:ricqchet, :cors, [])
        Keyword.get(config, :allowed_origins, [])

      origins_string ->
        origins_string
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
    end
  end
end
