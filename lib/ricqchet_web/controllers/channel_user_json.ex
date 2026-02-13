defmodule RicqchetWeb.ChannelUserJSON do
  def render("deleted.json", %{user_id: user_id}) do
    %{status: "ok", user_id: user_id}
  end
end
