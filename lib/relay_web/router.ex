defmodule RelayWeb.Router do
  use RelayWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug RelayWeb.Plugs.Authenticate
    plug RelayWeb.Plugs.RateLimiter
  end

  # Health check endpoint (no auth required)
  scope "/", RelayWeb do
    pipe_through :api

    get "/health", HealthController, :index
  end

  # API v1 endpoints (auth required)
  scope "/v1", RelayWeb do
    pipe_through [:api, :authenticated]

    post "/publish/*destination_url", PublishController, :create
    get "/messages/:id", MessageController, :show
    delete "/messages/:id", MessageController, :delete
  end

  # Enable LiveDashboard in development with basic auth protection
  if Application.compile_env(:relay, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    pipeline :dashboard_auth do
      plug :fetch_session
      plug :protect_from_forgery
      plug :dashboard_basic_auth
    end

    scope "/dev" do
      pipe_through [:dashboard_auth]

      live_dashboard "/dashboard", metrics: RelayWeb.Telemetry
    end

    # Basic auth for dashboard - uses env vars or defaults for dev
    # Defined inside the compile-time block to avoid unused function warning
    defp dashboard_basic_auth(conn, _opts) do
      username = System.get_env("DASHBOARD_USER") || "admin"
      password = System.get_env("DASHBOARD_PASSWORD") || "relay_dev_password"

      Plug.BasicAuth.basic_auth(conn, username: username, password: password)
    end
  end
end
