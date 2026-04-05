defmodule RicqchetWeb.SettingsController do
  use RicqchetWeb, :controller

  alias Ricqchet.Auth
  alias Ricqchet.Tenants

  def index(conn, _params) do
    render(conn, :index,
      page_title: "Settings",
      current_path: "/settings",
      tenant: conn.assigns.current_tenant
    )
  end

  def update_tenant(conn, %{"name" => name}) do
    case Tenants.update_tenant(conn.assigns.current_tenant, %{name: name}) do
      {:ok, tenant} ->
        conn
        |> put_flash(:info, "Organization name updated.")
        |> render(:index,
          page_title: "Settings",
          current_path: "/settings",
          tenant: tenant
        )

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to update organization name.")
        |> render(:index,
          page_title: "Settings",
          current_path: "/settings",
          tenant: conn.assigns.current_tenant
        )
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
        |> render(:index,
          page_title: "Settings",
          current_path: "/settings",
          tenant: conn.assigns.current_tenant
        )

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Failed to change password.")
        |> render(:index,
          page_title: "Settings",
          current_path: "/settings",
          tenant: conn.assigns.current_tenant
        )
    end
  end
end
