defmodule RicqchetWeb.Router do
  use RicqchetWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug RicqchetWeb.Plugs.Authenticate
    plug RicqchetWeb.Plugs.RateLimiter
  end

  pipeline :jwt_authenticated do
    plug RicqchetWeb.Plugs.JWTAuthenticate
    plug RicqchetWeb.Plugs.RateLimiter
  end

  # Health check endpoint (no auth required)
  scope "/", RicqchetWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end

  # OpenAPI documentation endpoints
  scope "/api" do
    pipe_through :api

    get "/openapi", OpenApiSpex.Plug.RenderSpec, spec: RicqchetWeb.ApiSpec
    get "/docs", OpenApiSpex.Plug.SwaggerUI, path: "/api/openapi"
  end

  # Public auth endpoints (no auth required)
  scope "/v1/auth", RicqchetWeb do
    pipe_through [:api]

    post "/register", AuthController, :register
    post "/verify-email", AuthController, :verify_email
  end

  # Protected auth endpoints (JWT auth required)
  scope "/v1/auth", RicqchetWeb do
    pipe_through [:api, :jwt_authenticated]

    post "/resend-verification", AuthController, :resend_verification
  end

  # API v1 endpoints (API key auth required for relay operations)
  scope "/v1", RicqchetWeb do
    pipe_through [:api, :authenticated]

    post "/publish", PublishController, :create
    get "/messages/:id", MessageController, :show
    delete "/messages/:id", MessageController, :delete
    get "/signing-secret", TenantController, :signing_secret
  end

  # Enable LiveDashboard in development with basic auth protection
  if Application.compile_env(:ricqchet, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    pipeline :dashboard_auth do
      plug :fetch_session
      plug :protect_from_forgery
      plug :dashboard_basic_auth
    end

    scope "/dev" do
      pipe_through [:dashboard_auth]

      live_dashboard "/dashboard", metrics: RicqchetWeb.Telemetry
    end

    # Basic auth for dashboard - uses env vars or defaults for dev
    # Defined inside the compile-time block to avoid unused function warning
    defp dashboard_basic_auth(conn, _opts) do
      username = System.get_env("DASHBOARD_USER") || "admin"
      password = System.get_env("DASHBOARD_PASSWORD") || "ricqchet_dev_password"

      Plug.BasicAuth.basic_auth(conn, username: username, password: password)
    end
  end
end
