defmodule RicqchetWeb.HealthController do
  @moduledoc """
  Health check endpoint for load balancers and monitoring.
  """

  use RicqchetWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias RicqchetWeb.Schemas.HealthResponse

  tags(["health"])

  operation(:index,
    summary: "Health check",
    description: "Returns the health status of the service. No authentication required.",
    responses: %{
      200 => {"Health status", "application/json", HealthResponse}
    }
  )

  def index(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
