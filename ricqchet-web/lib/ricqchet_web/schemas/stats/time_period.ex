defmodule RicqchetWeb.Schemas.Stats.TimePeriod do
  @moduledoc """
  Schema for time period parameter.
  """

  use RicqchetWeb.Schema

  OpenApiSpex.schema(%{
    title: "TimePeriod",
    description: "Time period for statistics filtering",
    type: :string,
    enum: ["5m", "1h", "4h", "1d", "1w"],
    default: "1h",
    example: "1h"
  })
end
