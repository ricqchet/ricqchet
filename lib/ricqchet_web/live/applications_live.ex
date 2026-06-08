defmodule RicqchetWeb.ApplicationsLive do
  use RicqchetWeb, :live_view

  alias Ricqchet.ApiKeys
  alias Ricqchet.Applications
  alias Ricqchet.Authorization

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    {:ok, {apps, _meta}} =
      Applications.list_applications_for_tenant(socket.assigns.current_tenant)

    {:ok,
     socket
     |> assign(:page_title, "Applications")
     |> assign(:current_path, "/applications")
     |> assign(:applications, apps)
     |> assign(:show_create_modal, false)
     |> assign(:show_delete_modal, false)
     |> assign(:delete_app, nil)
     |> assign(:created_api_key, nil)
     |> assign(:create_error, nil)}
  end

  @impl Phoenix.LiveView
  def handle_event("show_create_modal", _params, socket) do
    {:noreply, assign(socket, :show_create_modal, true)}
  end

  def handle_event("close_create_modal", _params, socket) do
    {:noreply, assign(socket, show_create_modal: false, created_api_key: nil, create_error: nil)}
  end

  def handle_event("create_application", %{"name" => name, "description" => description}, socket) do
    with :ok <- require_editor(socket) do
      do_create_application(socket, name, description)
    end
  end

  def handle_event("confirm_delete", %{"id" => id}, socket) do
    app = Applications.get_application_by_tenant(socket.assigns.current_tenant, id)
    {:noreply, assign(socket, show_delete_modal: true, delete_app: app)}
  end

  def handle_event("close_delete_modal", _params, socket) do
    {:noreply, assign(socket, show_delete_modal: false, delete_app: nil)}
  end

  def handle_event("delete_application", _params, socket) do
    with :ok <- require_editor(socket) do
      do_delete_application(socket)
    end
  end

  defp do_create_application(socket, name, description) do
    tenant = socket.assigns.current_tenant
    attrs = %{"name" => name, "description" => description}

    case Applications.create_application(tenant, attrs) do
      {:ok, app} ->
        case ApiKeys.create_api_key(app, %{"name" => "Default"}) do
          {:ok, api_key} ->
            {:ok, {apps, _meta}} = Applications.list_applications_for_tenant(tenant)

            {:noreply,
             socket
             |> assign(:applications, apps)
             |> assign(:created_api_key, api_key.api_key)
             |> assign(:create_error, nil)}

          {:error, _} ->
            {:ok, {apps, _meta}} = Applications.list_applications_for_tenant(tenant)

            {:noreply,
             socket
             |> assign(:applications, apps)
             |> assign(:show_create_modal, false)
             |> put_flash(:info, "Application created (API key generation failed).")}
        end

      {:error, _changeset} ->
        {:noreply, assign(socket, :create_error, "Failed to create application.")}
    end
  end

  defp do_delete_application(socket) do
    case Applications.delete_application(socket.assigns.delete_app) do
      {:ok, _} ->
        {:ok, {apps, _meta}} =
          Applications.list_applications_for_tenant(socket.assigns.current_tenant)

        {:noreply,
         socket
         |> assign(:applications, apps)
         |> assign(show_delete_modal: false, delete_app: nil)
         |> put_flash(:info, "Application deleted.")}

      {:error, _} ->
        {:noreply,
         socket
         |> assign(show_delete_modal: false, delete_app: nil)
         |> put_flash(:error, "Failed to delete application.")}
    end
  end

  defp require_editor(socket) do
    if Authorization.editor?(socket.assigns.current_user) do
      :ok
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to make changes.")}
    end
  end
end
