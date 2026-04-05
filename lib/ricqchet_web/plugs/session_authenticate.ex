defmodule RicqchetWeb.Plugs.SessionAuthenticate do
  @moduledoc """
  Plug that loads the current user from the session.

  If a valid user_id is found in the session, assigns `current_user`
  and `current_tenant` to the connection. Otherwise, assigns nil.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    user_id = get_session(conn, :user_id)

    if user_id do
      case Ricqchet.Users.get_user(user_id) do
        %{status: "active"} = user ->
          tenant = Ricqchet.Tenants.get_tenant!(user.tenant_id)

          conn
          |> assign(:current_user, user)
          |> assign(:current_tenant, tenant)

        _other ->
          conn
          |> delete_session(:user_id)
          |> assign(:current_user, nil)
          |> assign(:current_tenant, nil)
      end
    else
      conn
      |> assign(:current_user, nil)
      |> assign(:current_tenant, nil)
    end
  end
end
