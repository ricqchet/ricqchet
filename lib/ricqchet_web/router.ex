defmodule RicqchetWeb.Router do
  use RicqchetWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {RicqchetWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug RicqchetWeb.Plugs.SessionAuthenticate
  end

  pipeline :require_auth do
    plug RicqchetWeb.Plugs.RequireAuthenticated
  end

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

  # ──────────────────────────────────────────────────────────────
  # Browser routes (UI)
  # ──────────────────────────────────────────────────────────────

  # Public browser routes (no auth required)
  scope "/", RicqchetWeb do
    pipe_through [:browser]

    get "/", PageController, :index
    get "/login", PageController, :login
    get "/forgot-password", PageController, :forgot_password
    get "/reset-password", PageController, :reset_password

    post "/session", SessionController, :create
    delete "/session", SessionController, :delete

    post "/forgot-password", PageController, :submit_forgot_password
  end

  # Authenticated browser routes
  scope "/", RicqchetWeb do
    pipe_through [:browser, :require_auth]

    live_session :authenticated,
      on_mount: [{RicqchetWeb.Auth.LiveAuth, :ensure_authenticated}] do
      live "/dashboard", DashboardLive
      live "/applications", ApplicationsLive
      live "/applications/:id", ApplicationDetailLive
      live "/team", TeamLive
    end

    get "/settings", SettingsController, :index
    put "/settings/tenant", SettingsController, :update_tenant
    put "/settings/password", SettingsController, :change_password
  end

  # ──────────────────────────────────────────────────────────────
  # API routes
  # ──────────────────────────────────────────────────────────────

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

    post "/login", AuthController, :login
    post "/refresh", AuthController, :refresh
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

    # User management (admin only for create/update/delete)
    get "/users", TenantUserController, :index
    post "/users", TenantUserController, :create
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

      # Channel namespace configuration
      resources "/channel-namespaces", ChannelNamespaceController,
        only: [:index, :create, :update, :delete]
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

    # Channel endpoints
    post "/channels/events", ChannelController, :create
    post "/channels/events/batch", ChannelController, :batch_create
    get "/channels", ChannelController, :index
    get "/channels/:channel_name", ChannelController, :show
    get "/channels/:channel_name/events", ChannelEventController, :index
    get "/channels/:channel_name/members", ChannelMembersController, :index
    delete "/channels/users/:user_id/connections", ChannelUserController, :delete
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
