defmodule RicqchetWeb.Plugs.RequireAuthenticated do
  @moduledoc """
  Plug that ensures the current user is authenticated.

  Redirects to the login page if no user is in session.
  """
  import Plug.Conn
  import Phoenix.Controller

  use RicqchetWeb, :verified_routes

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_flash(:error, "You must log in to access this page.")
      |> redirect(to: ~p"/login")
      |> halt()
    end
  end
end
