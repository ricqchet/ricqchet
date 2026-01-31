defmodule RicqchetWeb.FallbackController do
  @moduledoc """
  Handles errors from controller actions.

  Use `action_fallback RicqchetWeb.FallbackController` in your controllers
  to have errors automatically rendered as JSON responses.
  """

  use RicqchetWeb, :controller

  @doc """
  Handles various error types and renders appropriate JSON responses.

  Supported errors:
  - `{:error, %Ecto.Changeset{}}` - Validation errors (422) or duplicate (409)
  - `{:error, :not_found}` - Resource not found (404)
  - `{:error, :already_dispatched}` - Message already dispatched (409)
  - `{:error, :duplicate, existing_id}` - Duplicate message (409)
  """
  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    # Check if this is a duplicate dedup_key constraint violation
    # This handles race conditions where two requests with same dedup_key
    # both pass the initial check but one fails at insert time
    if duplicate_dedup_error?(changeset) do
      conn
      |> put_status(:conflict)
      |> put_view(json: RicqchetWeb.ErrorJSON)
      |> render(:error,
        error: "duplicate_message",
        message: "A message with this dedup_key already exists"
      )
    else
      conn
      |> put_status(:unprocessable_entity)
      |> put_view(json: RicqchetWeb.ErrorJSON)
      |> render(:error,
        error: "validation_error",
        message: format_changeset_errors(changeset)
      )
    end
  end

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: RicqchetWeb.ErrorJSON)
    |> render(:error, error: "not_found", message: "Resource not found")
  end

  def call(conn, {:error, :already_dispatched}) do
    conn
    |> put_status(:conflict)
    |> put_view(json: RicqchetWeb.ErrorJSON)
    |> render(:error, error: "already_dispatched", message: "Message already dispatched")
  end

  def call(conn, {:error, :duplicate, existing_id}) do
    conn
    |> put_status(:conflict)
    |> put_view(json: RicqchetWeb.ErrorJSON)
    |> render(:error,
      error: "duplicate_message",
      message: "A message with this dedup_key already exists: #{existing_id}"
    )
  end

  defp format_changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts
        |> Keyword.get(String.to_existing_atom(key), key)
        |> to_string()
      end)
    end)
    |> Enum.map_join("; ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end

  # Check if the changeset error is due to duplicate dedup_key
  defp duplicate_dedup_error?(changeset) do
    case changeset.errors[:dedup_key] do
      {_msg, [constraint: :unique, constraint_name: "messages_dedup_index"]} -> true
      _ -> false
    end
  end
end
