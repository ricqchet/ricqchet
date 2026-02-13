defmodule RicqchetWeb.ChannelMembersJSON do
  @moduledoc """
  JSON views for channel members endpoints.
  """

  def render("index.json", %{members: members}) do
    %{members: members}
  end
end
