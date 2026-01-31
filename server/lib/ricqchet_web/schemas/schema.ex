defmodule RicqchetWeb.Schema do
  @moduledoc """
  Base module for OpenApiSpex schemas.

  Use this in schema modules:

      use RicqchetWeb.Schema
  """

  defmacro __using__(_opts) do
    quote do
      require OpenApiSpex

      alias OpenApiSpex.Schema
      alias RicqchetWeb.Schemas
    end
  end
end
