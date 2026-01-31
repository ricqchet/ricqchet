defmodule RicqchetWeb.Schemas.JsonResponse do
  @moduledoc """
  Helper functions for generating JSON API response schemas.
  """

  alias OpenApiSpex.MediaType
  alias OpenApiSpex.Response
  alias OpenApiSpex.Schema

  import RicqchetWeb.Schemas.Helpers, only: [resource_name: 1]

  @doc """
  Creates a list response schema wrapping resources in a data array.
  """
  @spec list(module()) :: Response.t()
  def list(resource) do
    name = resource_name(resource)

    %Response{
      description: "#{name} List Response",
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            description: "A collection of #{name} resources",
            type: :object,
            properties: %{
              data: %Schema{
                description: "The list of #{name} resources",
                type: :array,
                items: resource
              }
            }
          }
        }
      }
    }
  end

  @doc """
  Creates a show response schema wrapping a resource in data.
  """
  @spec show(module()) :: Response.t()
  def show(resource) do
    name = resource_name(resource)

    %Response{
      description: "#{name} Response",
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            description: "A #{name} resource",
            type: :object,
            properties: %{
              data: resource
            }
          }
        }
      }
    }
  end
end
