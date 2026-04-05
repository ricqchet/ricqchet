defmodule RicqchetWeb.Plugs.SessionAuthenticate do
  @moduledoc """
  Plug that loads the current user from the session.

  If a valid user_id is found in the session, assigns `current_user`
  and `current_tenant` to the connection. Otherwise, assigns nil.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> get_session(:user_id)
    |> load_user_and_tenant(conn)
  end

  defp load_user_and_tenant(nil, conn), do: assign_empty(conn)

  defp load_user_and_tenant(user_id, conn) do
    with %{status: "active"} = user <- Ricqchet.Users.get_user(user_id),
         %{} = tenant <- Ricqchet.Tenants.get_tenant(user.tenant_id) do
      conn
      |> assign(:current_user, user)
      |> assign(:current_tenant, tenant)
    else
      _ ->
        conn
        |> delete_session(:user_id)
        |> assign_empty()
    end
  end

  defp assign_empty(conn) do
    conn
    |> assign(:current_user, nil)
    |> assign(:current_tenant, nil)
  end
end
