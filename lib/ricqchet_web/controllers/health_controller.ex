defmodule RicqchetWeb.HealthController do
  @moduledoc """
  Health check endpoint for load balancers and monitoring.
  """

  use RicqchetWeb, :controller

  def index(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
