defmodule RicqchetWeb.Auth.LiveAuth do
  @moduledoc """
  LiveView on_mount hook for session-based authentication.

  Used in `live_session` blocks to authenticate LiveView connections.
  """
  import Phoenix.LiveView
  import Phoenix.Component

  use RicqchetWeb, :verified_routes

  def on_mount(:ensure_authenticated, _params, session, socket) do
    with user_id when is_binary(user_id) <- session["user_id"],
         %{status: "active"} = user <- Ricqchet.Users.get_user(user_id),
         %{} = tenant <- Ricqchet.Tenants.get_tenant(user.tenant_id) do
      {:cont,
       socket
       |> assign(:current_user, user)
       |> assign(:current_tenant, tenant)}
    else
      _ -> {:halt, redirect(socket, to: ~p"/login")}
    end
  end
end
