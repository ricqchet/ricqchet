defmodule RicqchetWeb.MessageController do
  @moduledoc """
  Controller for message status and management.
  """

  use RicqchetWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Ricqchet.Messages
  alias RicqchetWeb.Schemas

  action_fallback RicqchetWeb.FallbackController

  tags(["messages"])

  operation(:show,
    summary: "Get message status",
    description: "Retrieves the current status and details of a message.",
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "Message ID"
      ]
    ],
    responses: Schemas.Helpers.show_responses(Schemas.Message),
    security: [%{"bearer_auth" => []}]
  )

  operation(:delete,
    summary: "Cancel a message",
    description: """
    Cancels a pending message. Returns 409 Conflict if the message has already
    been dispatched or completed.
    """,
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "Message ID"
      ]
    ],
    responses: Schemas.Helpers.delete_responses(Schemas.CancelledResponse),
    security: [%{"bearer_auth" => []}]
  )

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
