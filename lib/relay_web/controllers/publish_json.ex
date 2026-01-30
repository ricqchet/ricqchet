defmodule RelayWeb.PublishJSON do
  @moduledoc """
  JSON views for the publish endpoint.
  """

  alias Relay.Messages.Message

  @doc """
  Renders the response for a newly created message.
  """
  def render("created.json", %{message: %Message{} = message}) do
    %{message_id: message.id}
  end
end
