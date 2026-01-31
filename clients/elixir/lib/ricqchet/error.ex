defmodule Ricqchet.Error do
  @moduledoc """
  Error types returned by Ricqchet client operations.
  """

  defstruct [:type, :message, :status, :details]

  @type t :: %__MODULE__{
          type: atom(),
          message: String.t(),
          status: integer() | nil,
          details: map() | nil
        }

  @doc """
  Creates an error from an HTTP response.
  """
  @spec from_response(integer(), map() | nil) :: t()
  def from_response(status, body) do
    %__MODULE__{
      type: type_from_status(status),
      message: extract_message(body),
      status: status,
      details: body
    }
  end

  @doc """
  Creates a connection error.
  """
  @spec connection_error(any()) :: t()
  def connection_error(reason) do
    %__MODULE__{
      type: :connection_error,
      message: "Connection failed: #{inspect(reason)}",
      status: nil,
      details: %{reason: reason}
    }
  end

  defp type_from_status(401), do: :unauthorized
  defp type_from_status(403), do: :forbidden
  defp type_from_status(404), do: :not_found
  defp type_from_status(409), do: :conflict
  defp type_from_status(422), do: :validation_error
  defp type_from_status(429), do: :rate_limited
  defp type_from_status(status) when status >= 500, do: :server_error
  defp type_from_status(_), do: :unknown_error

  defp extract_message(nil), do: "Unknown error"
  defp extract_message(%{"message" => message}), do: message
  defp extract_message(%{"error" => error}), do: error
  defp extract_message(_), do: "Unknown error"
end
