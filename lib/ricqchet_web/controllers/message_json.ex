defmodule RicqchetWeb.MessageJSON do
  @moduledoc """
  JSON views for message endpoints.
  """

  alias Ricqchet.Messages.Message

  @doc """
  Renders message responses.

  - `index.json` - Renders list of messages
  - `show.json` - Renders message details including status, attempts, timestamps
  - `cancelled.json` - Renders cancellation confirmation
  """
  def render("index.json", %{messages: messages}) do
    %{
      messages: Enum.map(messages, &message_to_json/1),
      has_more: false
    }
  end

  def render("show.json", %{message: %Message{} = message}) do
    message_to_json(message)
  end

  def render("cancelled.json", _assigns) do
    %{cancelled: true}
  end

  defp message_to_json(%Message{} = message) do
    %{
      id: message.id,
      status: message.status,
      destination_url: message.destination_url,
      method: message.method,
      attempts: message.attempts,
      max_retries: message.max_retries,
      created_at: message.inserted_at,
      scheduled_at: message.scheduled_at,
      dispatched_at: message.dispatched_at,
      completed_at: message.completed_at,
      last_error: message.last_error,
      last_response_status: message.last_response_status
    }
  end
end
