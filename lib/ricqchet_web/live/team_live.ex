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
     |> assign(:show_add_modal, false)
     |> assign(:show_remove_modal, false)
     |> assign(:remove_user, nil)
     |> assign(:add_error, nil)
     |> assign(:created_user_email, nil)
     |> assign(:created_user_password, nil)}
  end

  @impl Phoenix.LiveView
  def handle_event("show_add_modal", _params, socket) do
    {:noreply, reset_add_modal(socket, true)}
  end

  def handle_event("close_add_modal", _params, socket) do
    {:noreply, reset_add_modal(socket, false)}
  end

  def handle_event("add_user", %{"email" => email, "role" => role} = params, socket)
      when role in @roles do
    with :ok <- require_admin(socket) do
      do_add_user(socket, email, role, params["password"])
    end
  end

  def handle_event("update_role", %{"user-id" => user_id, "role" => role}, socket)
      when role in @roles do
    with :ok <- require_admin(socket) do
      do_update_role(socket, user_id, role)
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
    with :ok <- require_admin(socket),
         %{} = user <- socket.assigns.remove_user,
         :ok <- validate_not_self(socket, user) do
      do_remove_user(socket, user)
    else
      nil -> {:noreply, close_remove_modal(socket, "User not found.")}
      {:noreply, _} = result -> result
    end
  end

  # Action helpers

  defp do_add_user(socket, email, role, password) do
    tenant = socket.assigns.current_tenant
    attrs = %{"email" => email, "role" => role, "password" => password}

    case Users.create_user_by_admin(tenant, attrs) do
      {:ok, _user, generated_password} ->
        {:noreply,
         socket
         |> reload_users()
         |> assign(:add_error, nil)
         |> assign(:created_user_email, email)
         |> assign(:created_user_password, generated_password)}

      {:error, :user_already_exists} ->
        {:noreply, assign(socket, :add_error, "A user with that email already exists.")}

      {:error, _changeset} ->
        {:noreply,
         assign(
           socket,
           :add_error,
           "Failed to add user. Check the email and password (minimum 12 characters)."
         )}
    end
  end

  defp do_update_role(socket, user_id, role) do
    user = Users.get_user_by_tenant(socket.assigns.current_tenant, user_id)

    if user do
      case Users.update_user(user, %{"role" => role}) do
        {:ok, _user} -> {:noreply, reload_users(socket)}
        {:error, _changeset} -> {:noreply, put_flash(socket, :error, "Failed to update role.")}
      end
    else
      {:noreply, put_flash(socket, :error, "User not found.")}
    end
  end

  defp do_remove_user(socket, user) do
    case Tenants.remove_user_from_tenant(user) do
      {:ok, _} ->
        {:noreply,
         socket
         |> reload_users()
         |> assign(show_remove_modal: false, remove_user: nil)
         |> put_flash(:info, "Team member removed.")}

      {:error, _} ->
        {:noreply, close_remove_modal(socket, "Failed to remove team member.")}
    end
  end

  # Guards and helpers

  defp require_admin(socket) do
    if socket.assigns.current_user.role == "admin" do
      :ok
    else
      {:noreply, put_flash(socket, :error, "Only admins can perform this action.")}
    end
  end

  defp validate_not_self(socket, user) do
    if user.id == socket.assigns.current_user.id do
      {:noreply, close_remove_modal(socket, "You cannot remove yourself.")}
    else
      :ok
    end
  end

  defp reset_add_modal(socket, show?) do
    assign(socket,
      show_add_modal: show?,
      add_error: nil,
      created_user_email: nil,
      created_user_password: nil
    )
  end

  defp reload_users(socket) do
    {:ok, {users, _meta}} =
      Users.list_users_for_tenant_paginated(socket.assigns.current_tenant, %{})

    assign(socket, :users, users)
  end

  defp close_remove_modal(socket, error_msg) do
    socket
    |> assign(show_remove_modal: false, remove_user: nil)
    |> put_flash(:error, error_msg)
  end
end
