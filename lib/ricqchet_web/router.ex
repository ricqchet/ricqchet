defmodule RicqchetWeb.Router do
  use RicqchetWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :openapi do
    plug OpenApiSpex.Plug.PutApiSpec, module: RicqchetWeb.ApiSpec
  end

  pipeline :authenticated do
    plug RicqchetWeb.Plugs.Authenticate
    plug RicqchetWeb.Plugs.RateLimiter
  end

  pipeline :jwt_authenticated do
    plug RicqchetWeb.Plugs.JWTAuthenticate
    plug RicqchetWeb.Plugs.RateLimiter
  end

  pipeline :auth_rate_limited do
    plug RicqchetWeb.Plugs.AuthRateLimiter
  end

  # Health check endpoint (no auth required)
  scope "/", RicqchetWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end

  # OpenAPI documentation endpoints
  scope "/api" do
    pipe_through [:api, :openapi]

    get "/openapi", OpenApiSpex.Plug.RenderSpec, []
    get "/docs", OpenApiSpex.Plug.SwaggerUI, path: "/api/openapi"
  end

  # Public auth endpoints (no auth required)
  scope "/v1/auth", RicqchetWeb do
    pipe_through [:api]

    post "/register", AuthController, :register
    post "/verify-email", AuthController, :verify_email
    post "/login", AuthController, :login
    post "/refresh", AuthController, :refresh
    post "/accept-invite", AuthController, :accept_invite
  end

  # Rate-limited public auth endpoints (to prevent abuse)
  scope "/v1/auth", RicqchetWeb do
    pipe_through [:api, :auth_rate_limited]

    post "/forgot-password", AuthController, :forgot_password
    post "/reset-password", AuthController, :reset_password
  end

  # Protected auth endpoints (JWT auth required)
  scope "/v1/auth", RicqchetWeb do
    pipe_through [:api, :jwt_authenticated]

    post "/resend-verification", AuthController, :resend_verification
    post "/logout", AuthController, :logout
    post "/change-password", AuthController, :change_password
  end

  # User profile endpoints (JWT auth required)
  scope "/v1/users", RicqchetWeb do
    pipe_through [:api, :jwt_authenticated]

    get "/me", UserController, :show
  end

  # Tenant management (JWT auth required)
  scope "/v1/tenant", RicqchetWeb do
    pipe_through [:api, :jwt_authenticated]

    get "/", TenantController, :show
    patch "/", TenantController, :update

    # Tenant user management
    get "/users", TenantUserController, :index
    post "/users/invite", TenantUserController, :invite
    patch "/users/:id", TenantUserController, :update
    delete "/users/:id", TenantUserController, :delete
  end

  # Application management (JWT auth required, role-based access)
  scope "/v1", RicqchetWeb do
    pipe_through [:api, :jwt_authenticated]

    resources "/applications", ApplicationController,
      only: [:index, :show, :create, :update, :delete] do
      # API key management (nested under applications for create/list)
      resources "/api-keys", ApiKeyController, only: [:index, :create]
    end

    # API key operations (revoke and rotate use direct key ID)
    delete "/api-keys/:id", ApiKeyController, :delete
    post "/api-keys/:id/rotate", ApiKeyController, :rotate
  end

  # Dashboard statistics endpoints (JWT auth required)
  scope "/v1/stats", RicqchetWeb do
    pipe_through [:api, :jwt_authenticated]

    get "/messages", StatsController, :messages
    get "/message-sizes", StatsController, :message_sizes
    get "/delivery", StatsController, :delivery
    get "/errors", StatsController, :errors
    get "/destinations", StatsController, :destinations
    get "/activity", StatsController, :activity
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
