defmodule RicqchetWeb.PublishJSON do
  @moduledoc """
  JSON views for the publish endpoint.
  """

  alias Ricqchet.Messages.Message

  @doc """
  Renders publish endpoint responses.

  - `"created.json"` - Single message created, returns `%{message_id: id}`
  - `"fan_out_created.json"` - Fan-out messages created, returns `%{message_ids: [...]}`
  """
  def render(template, assigns)

  def render("created.json", %{message: %Message{} = message}) do
    %{message_id: message.id}
  end

  def render("fan_out_created.json", %{messages: messages}) do
    %{message_ids: Enum.map(messages, & &1.id)}
  end
end
