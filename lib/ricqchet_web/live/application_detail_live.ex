defmodule RicqchetWeb.ApplicationDetailLive do
  use RicqchetWeb, :live_view

  alias Ricqchet.ApiKeys
  alias Ricqchet.Applications
  alias Ricqchet.Authorization

  @impl Phoenix.LiveView
  def mount(%{"id" => id}, _session, socket) do
    app = Applications.get_application_by_tenant(socket.assigns.current_tenant, id)

    if app do
      api_keys = ApiKeys.list_api_keys_for_application(app)

      {:ok,
       socket
       |> assign(:page_title, app.name)
       |> assign(:current_path, "/applications")
       |> assign(:application, app)
       |> assign(:api_keys, api_keys)
       |> assign(:show_create_key_modal, false)
       |> assign(:show_rotate_key_modal, false)
       |> assign(:rotate_key, nil)
       |> assign(:created_key_value, nil)
       |> assign(:rotated_key_value, nil)}
    else
      {:ok,
       socket
       |> put_flash(:error, "Application not found.")
       |> redirect(to: ~p"/applications")}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("update_application", params, socket) do
    with :ok <- require_editor(socket) do
      do_update_application(socket, params)
    end
  end

  # API Key Management

  def handle_event("show_create_key_modal", _params, socket) do
    {:noreply, assign(socket, show_create_key_modal: true, created_key_value: nil)}
  end

  def handle_event("close_create_key_modal", _params, socket) do
    {:noreply, assign(socket, show_create_key_modal: false, created_key_value: nil)}
  end

  def handle_event("create_api_key", %{"name" => name}, socket) do
    with :ok <- require_editor(socket) do
      do_create_api_key(socket, name)
    end
  end

  def handle_event("revoke_api_key", %{"id" => id}, socket) do
    with :ok <- require_editor(socket) do
      do_revoke_api_key(socket, id)
    end
  end

  def handle_event("show_rotate_modal", %{"id" => id}, socket) do
    case find_owned_api_key(socket, id) do
      {:ok, key} ->
        {:noreply,
         assign(socket, show_rotate_key_modal: true, rotate_key: key, rotated_key_value: nil)}

      :error ->
        {:noreply, put_flash(socket, :error, "API key not found.")}
    end
  end

  def handle_event("close_rotate_modal", _params, socket) do
    {:noreply,
     assign(socket, show_rotate_key_modal: false, rotate_key: nil, rotated_key_value: nil)}
  end

  def handle_event("rotate_api_key", _params, socket) do
    with :ok <- require_editor(socket) do
      do_rotate_api_key(socket)
    end
  end

  # Action helpers

  defp do_update_application(socket, params) do
    attrs = Map.take(params, ["name", "description", "dlq_destination_url"])

    case Applications.update_application(socket.assigns.application, attrs) do
      {:ok, app} ->
        {:noreply,
         socket
         |> assign(:application, app)
         |> put_flash(:info, "Application updated.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update application.")}
    end
  end

  defp do_create_api_key(socket, name) do
    case ApiKeys.create_api_key(socket.assigns.application, %{"name" => name}) do
      {:ok, api_key} ->
        api_keys = ApiKeys.list_api_keys_for_application(socket.assigns.application)

        {:noreply,
         socket
         |> assign(:api_keys, api_keys)
         |> assign(:created_key_value, api_key.api_key)}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to create API key.")}
    end
  end

  defp do_revoke_api_key(socket, id) do
    case find_owned_api_key(socket, id) do
      {:ok, api_key} ->
        case ApiKeys.revoke_api_key(api_key) do
          {:ok, _} ->
            api_keys = ApiKeys.list_api_keys_for_application(socket.assigns.application)

            {:noreply,
             socket
             |> assign(:api_keys, api_keys)
             |> put_flash(:info, "API key revoked.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Failed to revoke API key.")}
        end

      :error ->
        {:noreply, put_flash(socket, :error, "API key not found.")}
    end
  end

  defp do_rotate_api_key(socket) do
    if socket.assigns.rotate_key do
      case ApiKeys.rotate_api_key(socket.assigns.rotate_key) do
        {:ok, {_old, new_key}} ->
          api_keys = ApiKeys.list_api_keys_for_application(socket.assigns.application)

          {:noreply,
           socket
           |> assign(:api_keys, api_keys)
           |> assign(:rotated_key_value, new_key.api_key)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to rotate API key.")}
      end
    else
      {:noreply, put_flash(socket, :error, "API key not found.")}
    end
  end

  # Guards and helpers

  defp require_editor(socket) do
    if Authorization.editor?(socket.assigns.current_user) do
      :ok
    else
      {:noreply, put_flash(socket, :error, "You don't have permission to make changes.")}
    end
  end

  defp find_owned_api_key(socket, id) do
    case ApiKeys.get_api_key_with_application(id) do
      %{application_id: app_id} = key when app_id == socket.assigns.application.id ->
        {:ok, key}

      _ ->
        :error
    end
  end

  defp format_key_prefix(key) do
    if key.prefix do
      key.prefix <> "..."
    else
      "..."
    end
  end
end
