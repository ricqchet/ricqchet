defmodule RicqchetWeb.PublishJSON do
  @moduledoc """
  JSON views for the publish endpoint.
  """

  alias Ricqchet.Messages.Message

  @doc """
  Renders the response for a newly created message.
  """
  def render("created.json", %{message: %Message{} = message}) do
    %{message_id: message.id}
  end
end
