defmodule RicqchetWeb.DashboardLive do
  use RicqchetWeb, :live_view

  alias Ricqchet.Stats

  @refresh_interval :timer.seconds(60)
  @periods ~w(5m 1h 4h 1d 1w)

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    if connected?(socket) do
      tenant_id = socket.assigns.current_tenant.id
      Phoenix.PubSub.subscribe(Ricqchet.PubSub, "activity:tenant:#{tenant_id}")
      Process.send_after(self(), :refresh_stats, @refresh_interval)
    end

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:current_path, "/dashboard")
     |> assign(:period, "1h")
     |> assign(:activity_events, [])
     |> load_stats()}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    period = params["period"] || "1h"

    if period in @periods do
      {:noreply,
       socket
       |> assign(:period, period)
       |> load_stats()}
    else
      {:noreply, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_info({:activity_event, payload}, socket) do
    events = Enum.take([payload | socket.assigns.activity_events], 25)

    {:noreply, assign(socket, :activity_events, events)}
  end

  def handle_info(:refresh_stats, socket) do
    Process.send_after(self(), :refresh_stats, @refresh_interval)
    {:noreply, load_stats(socket)}
  end

  @impl Phoenix.LiveView
  def handle_event("change_period", %{"period" => period}, socket) when period in @periods do
    {:noreply, push_patch(socket, to: ~p"/dashboard?period=#{period}")}
  end

  # Template helpers

  defp format_error_type(type) when is_atom(type) do
    type
    |> to_string()
    |> format_error_type()
  end

  defp format_error_type(type) when is_binary(type) do
    type
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp status_variant("delivered"), do: "success"
  defp status_variant("failed"), do: "error"
  defp status_variant("pending"), do: "secondary"
  defp status_variant("dispatched"), do: "warning"
  defp status_variant(_), do: "secondary"

  defp format_attempts(1), do: "1 attempt"
  defp format_attempts(n), do: "#{n} attempts"

  attr :status, :string, required: true

  defp status_dot(assigns) do
    ~H"""
    <span class={[
      "h-2 w-2 rounded-full shrink-0",
      case @status do
        "delivered" -> "bg-green-500"
        "failed" -> "bg-red-500"
        "dispatched" -> "bg-yellow-500"
        _ -> "bg-gray-400"
      end
    ]} />
    """
  end

  defp load_stats(socket) do
    tenant = socket.assigns.current_tenant
    opts = [period: socket.assigns.period]

    message_counts = Stats.message_counts(tenant, opts)
    delivery = Stats.delivery_performance(tenant, opts)
    errors = Stats.error_breakdown(tenant, opts)
    destinations = Stats.destination_metrics(tenant, opts)
    activity = Stats.recent_activity(tenant, Keyword.merge(opts, limit: 10))

    socket
    |> assign(:message_counts, message_counts)
    |> assign(:delivery, delivery)
    |> assign(:errors, errors)
    |> assign(:destinations, destinations)
    |> assign(:recent_activity, activity)
  end
end
