defmodule RicqchetWeb.PageHTML do
  @moduledoc """
  HTML templates for public pages (login, register, etc.)
  """
  use RicqchetWeb, :html

  embed_templates "page_html/*"
end
