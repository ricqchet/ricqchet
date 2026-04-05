defmodule RicqchetWeb.TeamLive do
  use RicqchetWeb, :live_view

  alias Ricqchet.Tenants
  alias Ricqchet.Users

  @roles ~w(admin member viewer)

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    tenant = socket.assigns.current_tenant
    {:ok, {users, _meta}} = Users.list_users_for_tenant_paginated(tenant, %{})

    {:ok,
     socket
     |> assign(:page_title, "Team")
     |> assign(:current_path, "/team")
     |> assign(:users, users)
     |> assign(:show_invite_modal, false)
     |> assign(:show_remove_modal, false)
     |> assign(:remove_user, nil)
     |> assign(:invite_error, nil)}
  end

  @impl Phoenix.LiveView
  def handle_event("show_invite_modal", _params, socket) do
    {:noreply, assign(socket, show_invite_modal: true, invite_error: nil)}
  end

  def handle_event("close_invite_modal", _params, socket) do
    {:noreply, assign(socket, show_invite_modal: false, invite_error: nil)}
  end

  def handle_event("invite_user", %{"email" => email, "role" => role}, socket)
      when role in @roles do
    tenant = socket.assigns.current_tenant
    current_user = socket.assigns.current_user

    case Tenants.invite_user(tenant, current_user, %{"email" => email, "role" => role}) do
      {:ok, _invitation} ->
        {:ok, {users, _meta}} = Users.list_users_for_tenant_paginated(tenant, %{})

        {:noreply,
         socket
         |> assign(:users, users)
         |> assign(:show_invite_modal, false)
         |> put_flash(:info, "Invitation sent to #{email}.")}

      {:error, _changeset} ->
        {:noreply, assign(socket, :invite_error, "Failed to send invitation.")}
    end
  end

  def handle_event("update_role", %{"user-id" => user_id, "role" => role}, socket)
      when role in @roles do
    tenant = socket.assigns.current_tenant
    user = Users.get_user_by_tenant(tenant, user_id)

    if user do
      case Users.update_user(user, %{"role" => role}) do
        {:ok, _user} ->
          {:ok, {users, _meta}} = Users.list_users_for_tenant_paginated(tenant, %{})
          {:noreply, assign(socket, :users, users)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Failed to update role.")}
      end
    else
      {:noreply, put_flash(socket, :error, "User not found.")}
    end
  end

  def handle_event("confirm_remove", %{"id" => id}, socket) do
    user = Users.get_user_by_tenant(socket.assigns.current_tenant, id)
    {:noreply, assign(socket, show_remove_modal: true, remove_user: user)}
  end

  def handle_event("close_remove_modal", _params, socket) do
    {:noreply, assign(socket, show_remove_modal: false, remove_user: nil)}
  end

  def handle_event("remove_user", _params, socket) do
    case Tenants.remove_user_from_tenant(socket.assigns.remove_user) do
      {:ok, _} ->
        {:ok, {users, _meta}} =
          Users.list_users_for_tenant_paginated(socket.assigns.current_tenant, %{})

        {:noreply,
         socket
         |> assign(:users, users)
         |> assign(show_remove_modal: false, remove_user: nil)
         |> put_flash(:info, "Team member removed.")}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(show_remove_modal: false, remove_user: nil)
         |> put_flash(:error, "Failed to remove team member.")}
    end
  end
end
