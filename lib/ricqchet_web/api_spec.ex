defmodule RicqchetWeb.ApiSpec do
  @moduledoc """
  OpenAPI specification for the Ricqchet API.

  This module implements the `OpenApiSpex.OpenApi` behaviour and defines
  the complete API specification including info, servers, and security schemes.
  """

  alias OpenApiSpex.Components
  alias OpenApiSpex.Info
  alias OpenApiSpex.OpenApi
  alias OpenApiSpex.Paths
  alias OpenApiSpex.SecurityScheme
  alias OpenApiSpex.Server
  alias RicqchetWeb.Router

  @behaviour OpenApi

  @impl OpenApi
  def spec do
    spec = %OpenApi{
      info: %Info{
        title: "Ricqchet API",
        version: "1.0.0",
        description: """
        Ricqchet is a reliable message queue service for HTTP webhooks and callbacks.

        ## Authentication

        All API endpoints (except `/health`) require Bearer token authentication.
        Include your API key in the Authorization header:

        ```
        Authorization: Bearer your-api-key
        ```

        ## Rate Limiting

        API requests are rate-limited per tenant. When rate limited, the API returns
        HTTP 429 Too Many Requests.

        ## Custom Headers

        The publish endpoint supports custom `Ricqchet-*` headers to control message
        behavior including delays, deduplication, retries, and batching.

        Headers prefixed with `Ricqchet-Forward-*` will be forwarded to the destination
        URL with the prefix stripped.
        """
      },
      servers: servers(),
      paths: Paths.from_router(Router),
      components: %Components{
        securitySchemes: %{
          "bearer_auth" => %SecurityScheme{
            type: "http",
            scheme: "bearer",
            bearerFormat: "API Key",
            description: "API key authentication via Bearer token"
          }
        }
      }
    }

    OpenApiSpex.resolve_schema_modules(spec)
  end

  defp servers do
    base_url = System.get_env("RICQCHET_API_BASE_URL", "http://localhost:4000")

    [%Server{url: base_url, description: "API Server"}]
  end
end
