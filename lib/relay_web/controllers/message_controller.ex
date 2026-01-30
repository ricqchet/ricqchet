defmodule RelayWeb.MessageController do
  @moduledoc """
  Controller for message status and management.
  """

  use RelayWeb, :controller

  alias Relay.Messages

  action_fallback RelayWeb.FallbackController

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

    with message when not is_nil(message) <- Messages.get_by_tenant(tenant, id),
         {:ok, _message} <- Messages.cancel(message) do
      render(conn, :cancelled)
    else
      nil -> {:error, :not_found}
      {:error, :already_dispatched} -> {:error, :already_dispatched}
    end
  end
end
