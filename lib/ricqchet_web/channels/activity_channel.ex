defmodule RicqchetWeb.ActivityChannel do
  @moduledoc """
  Channel for real-time activity updates.

  Clients can subscribe to tenant-level activity:
  - `activity:tenant:<tenant_id>` - All activity for a tenant

  Events pushed to clients:
  - `activity` - Message status changes (created, dispatched, delivered, failed, retrying)
  """

  use RicqchetWeb, :channel

  require Logger

  @impl Phoenix.Channel
  def join("activity:tenant:" <> tenant_id, _params, socket) do
    if socket.assigns.tenant_id == tenant_id do
      :ok = Phoenix.PubSub.subscribe(Ricqchet.PubSub, "activity:tenant:#{tenant_id}")
      Logger.debug("User #{socket.assigns.user_id} joined activity:tenant:#{tenant_id}")
      {:ok, socket}
    else
      {:error, %{reason: "unauthorized"}}
    end
  end

  def join(_topic, _params, _socket) do
    {:error, %{reason: "invalid_topic"}}
  end

  @impl Phoenix.Channel
  def handle_info({:activity_event, payload}, socket) do
    push(socket, "activity", payload)
    {:noreply, socket}
  end
end
