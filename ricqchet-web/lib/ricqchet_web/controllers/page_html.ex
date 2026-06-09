defmodule RicqchetWeb.PageHTML do
  @moduledoc """
  HTML templates for public pages (login, password recovery).
  """
  use RicqchetWeb, :html

  embed_templates "page_html/*"
end
