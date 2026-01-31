defmodule RicqchetWeb.Schemas.Helpers do
  @moduledoc """
  Helper functions for reducing OpenApiSpex boilerplate.
  """

  alias OpenApiSpex.MediaType
  alias OpenApiSpex.Response
  alias OpenApiSpex.Schema
  alias RicqchetWeb.Schemas

  @doc """
  Extracts the resource name from a schema module.
  """
  @spec resource_name(module()) :: String.t()
  def resource_name(module) do
    module
    |> Module.split()
    |> List.last()
  end

  @doc """
  Generates standard show endpoint responses (200 + errors).
  """
  @spec show_responses(module(), [integer()]) :: map()
  def show_responses(schema, error_codes \\ [401, 404]) do
    Map.merge(
      %{200 => json_response(schema, "Success")},
      error_responses(error_codes)
    )
  end

  @doc """
  Generates standard create endpoint responses (201/202 + errors).
  """
  @spec create_responses(module(), integer(), [integer()]) :: map()
  def create_responses(schema, success_code \\ 202, error_codes \\ [401, 409, 422]) do
    Map.merge(
      %{success_code => json_response(schema, "Accepted")},
      error_responses(error_codes)
    )
  end

  @doc """
  Generates standard delete endpoint responses (200 + errors).
  """
  @spec delete_responses(module(), [integer()]) :: map()
  def delete_responses(schema, error_codes \\ [401, 404, 409]) do
    Map.merge(
      %{200 => json_response(schema, "Success")},
      error_responses(error_codes)
    )
  end

  @doc """
  Generates error responses for given status codes.
  """
  @spec error_responses([integer()]) :: map()
  def error_responses(status_codes) do
    error_descriptions = %{
      400 => "Bad Request",
      401 => "Unauthorized",
      403 => "Forbidden",
      404 => "Not Found",
      409 => "Conflict",
      422 => "Unprocessable Entity",
      429 => "Too Many Requests",
      500 => "Internal Server Error"
    }

    for code <- status_codes, code in 400..599, into: %{} do
      description = Map.get(error_descriptions, code, "Error")
      {code, json_response(Schemas.ErrorResponse, description)}
    end
  end

  @doc """
  Creates a JSON response with the given schema.
  """
  @spec json_response(module() | Schema.t(), String.t()) :: Response.t()
  def json_response(schema, description) do
    %Response{
      description: description,
      content: %{"application/json" => %MediaType{schema: schema}}
    }
  end
end
