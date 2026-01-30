defmodule RelayWeb.Router do
  use RelayWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated do
    plug RelayWeb.Plugs.Authenticate
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

  # Enable LiveDashboard in development
  if Application.compile_env(:relay, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: RelayWeb.Telemetry
    end
  end
end
