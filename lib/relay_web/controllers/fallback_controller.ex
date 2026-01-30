defmodule RelayWeb.FallbackController do
  @moduledoc """
  Handles errors from controller actions.

  Use `action_fallback RelayWeb.FallbackController` in your controllers
  to have errors automatically rendered as JSON responses.
  """

  use RelayWeb, :controller

  @doc """
  Handles various error types and renders appropriate JSON responses.

  Supported errors:
  - `{:error, %Ecto.Changeset{}}` - Validation errors (422)
  - `{:error, :not_found}` - Resource not found (404)
  - `{:error, :already_dispatched}` - Message already dispatched (409)
  - `{:error, :duplicate, existing_id}` - Duplicate message (409)
  """
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: RelayWeb.ErrorJSON)
    |> render(:error,
      error: "validation_error",
      message: format_changeset_errors(changeset)
    )
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: RelayWeb.ErrorJSON)
    |> render(:error, error: "not_found", message: "Resource not found")
  end

  def call(conn, {:error, :already_dispatched}) do
    conn
    |> put_status(:conflict)
    |> put_view(json: RelayWeb.ErrorJSON)
    |> render(:error, error: "already_dispatched", message: "Message already dispatched")
  end

  def call(conn, {:error, :duplicate, existing_id}) do
    conn
    |> put_status(:conflict)
    |> put_view(json: RelayWeb.ErrorJSON)
    |> render(:error,
      error: "duplicate_message",
      message: "A message with this dedup_key already exists: #{existing_id}"
    )
  end

  defp format_changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end
end
