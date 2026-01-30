defmodule RelayWeb.HealthController do
  @moduledoc """
  Health check endpoint for load balancers and monitoring.
  """

  use RelayWeb, :controller

  def index(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
