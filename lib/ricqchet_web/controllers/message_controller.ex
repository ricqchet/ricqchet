defmodule RicqchetWeb.MessageController do
  @moduledoc """
  Controller for message status and management.
  """

  use RicqchetWeb, :controller

  alias Ricqchet.Messages

  action_fallback RicqchetWeb.FallbackController

  @doc """
  Gets the status and details of a message.
  """
  def show(conn, %{"id" => id}) do
    tenant = conn.assigns.current_tenant

    case Messages.get_by_tenant(tenant, id) do
      nil -> {:error, :not_found}
      message -> render(conn, :show, message: message)
    end
  end

  @doc """
  Cancels a pending message.

  Returns 409 Conflict if the message is already dispatched or completed.
  """
  def delete(conn, %{"id" => id}) do
    tenant = conn.assigns.current_tenant

    case Messages.get_by_tenant(tenant, id) do
      nil ->
        {:error, :not_found}

      message ->
        case Messages.cancel(message) do
          {:ok, _message} -> render(conn, :cancelled)
          {:error, :already_dispatched} -> {:error, :already_dispatched}
        end
    end
  end
end
