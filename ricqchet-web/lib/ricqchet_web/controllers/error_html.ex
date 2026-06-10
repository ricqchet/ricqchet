defmodule RicqchetWeb.ErrorHTML do
  @moduledoc """
  HTML error pages.
  """
  use RicqchetWeb, :html

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
