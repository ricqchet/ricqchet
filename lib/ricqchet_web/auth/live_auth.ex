defmodule RicqchetWeb.Auth.LiveAuth do
  @moduledoc """
  LiveView on_mount hook for session-based authentication.

  Used in `live_session` blocks to authenticate LiveView connections.
  """
  import Phoenix.LiveView
  import Phoenix.Component

  use RicqchetWeb, :verified_routes

  def on_mount(:ensure_authenticated, _params, session, socket) do
    user_id = session["user_id"]

    if user_id do
      case Ricqchet.Users.get_user(user_id) do
        %{status: "active"} = user ->
          tenant = Ricqchet.Tenants.get_tenant!(user.tenant_id)

          {:cont,
           socket
           |> assign(:current_user, user)
           |> assign(:current_tenant, tenant)}

        _other ->
          {:halt, redirect(socket, to: ~p"/login")}
      end
    else
      {:halt, redirect(socket, to: ~p"/login")}
    end
  end
end
