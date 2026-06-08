defmodule RicqchetWeb.SettingsController do
  use RicqchetWeb, :controller

  alias Ricqchet.Auth
  alias Ricqchet.Authorization
  alias Ricqchet.Tenants

  plug :put_layout, html: {RicqchetWeb.Layouts, :app}

  def index(conn, _params) do
    render(conn, :index,
      page_title: "Settings",
      current_path: "/settings",
      tenant: conn.assigns.current_tenant
    )
  end

  def update_tenant(conn, %{"name" => name}) do
    if Authorization.can?(conn.assigns.current_user, :manage_settings) do
      do_update_tenant(conn, name)
    else
      conn
      |> put_flash(:error, "Only admins can change organization settings.")
      |> redirect(to: ~p"/settings")
    end
  end

  defp do_update_tenant(conn, name) do
    case Tenants.update_tenant(conn.assigns.current_tenant, %{name: name}) do
      {:ok, _tenant} ->
        conn
        |> put_flash(:info, "Organization name updated.")
        |> redirect(to: ~p"/settings")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to update organization name.")
        |> redirect(to: ~p"/settings")
    end
  end

  def change_password(conn, %{
        "current_password" => current_password,
        "new_password" => new_password
      }) do
    case Auth.change_password(conn.assigns.current_user, current_password, new_password) do
      {:ok, _result} ->
        conn
        |> configure_session(drop: true)
        |> put_flash(:info, "Password changed. Please log in again.")
        |> redirect(to: ~p"/login")

      {:error, :invalid_current_password} ->
        conn
        |> put_flash(:error, "Current password is incorrect.")
        |> redirect(to: ~p"/settings")

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to change password.")
        |> redirect(to: ~p"/settings")
    end
  end
end
