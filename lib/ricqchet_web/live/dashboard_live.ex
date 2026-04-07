defmodule RicqchetWeb.DashboardLive do
  use RicqchetWeb, :live_view

  alias Ricqchet.Applications
  alias Ricqchet.Stats
  alias Ricqchet.Stats.ChannelStats

  @relay_refresh_interval :timer.seconds(60)
  @channel_refresh_interval :timer.seconds(10)
  @periods ~w(5m 1h 4h 1d 1w)
  @tabs ~w(messages channels)

  @impl Phoenix.LiveView
  def mount(_params, _session, socket) do
    tenant = socket.assigns.current_tenant

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Ricqchet.PubSub, "activity:tenant:#{tenant.id}")
      Process.send_after(self(), :refresh_stats, @relay_refresh_interval)
    end

    {:ok, {apps, _meta}} = Applications.list_applications_for_tenant(tenant)

    {:ok,
     socket
     |> assign(:page_title, "Dashboard")
     |> assign(:current_path, "/dashboard")
     |> assign(:tab, "messages")
     |> assign(:period, "1h")
     |> assign(:activity_events, [])
     |> assign(:applications, apps)
     |> assign(:selected_app, nil)
     |> assign(:channel_overview, nil)
     |> assign(:channel_list, [])
     |> assign(:channel_events, [])
     |> assign(:type_breakdown, nil)
     |> load_relay_stats()}
  end

  @impl Phoenix.LiveView
  def handle_params(params, _uri, socket) do
    tab = if params["tab"] in @tabs, do: params["tab"], else: "messages"
    period = if params["period"] in @periods, do: params["period"], else: "1h"
    app_id = params["app"]

    updated_socket =
      socket
      |> assign(:tab, tab)
      |> assign(:period, period)
      |> manage_subscriptions(tab)
      |> load_tab_data(tab, app_id)

    {:noreply, updated_socket}
  end

  # Relay activity events
  @impl Phoenix.LiveView
  def handle_info({:activity_event, payload}, socket) do
    if socket.assigns.tab == "messages" do
      events = Enum.take([payload | socket.assigns.activity_events], 25)
      {:noreply, assign(socket, :activity_events, events)}
    else
      {:noreply, socket}
    end
  end

  # Channel activity events
  def handle_info({:channel_activity, payload}, socket) do
    if socket.assigns.tab == "channels" && socket.assigns.selected_app &&
         payload.application_id == socket.assigns.selected_app.id do
      events = Enum.take([payload | socket.assigns.channel_events], 25)
      {:noreply, assign(socket, :channel_events, events)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:refresh_stats, socket) do
    Process.send_after(self(), :refresh_stats, @relay_refresh_interval)

    if socket.assigns.tab == "messages" do
      {:noreply, load_relay_stats(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:refresh_channel_stats, socket) do
    if socket.assigns.tab == "channels" do
      Process.send_after(self(), :refresh_channel_stats, @channel_refresh_interval)

      if socket.assigns.selected_app do
        {:noreply, load_channel_stats(socket)}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl Phoenix.LiveView
  def handle_event("change_period", %{"period" => period}, socket) when period in @periods do
    params = build_params(socket.assigns.tab, socket.assigns.selected_app, period)
    {:noreply, push_patch(socket, to: ~p"/dashboard?#{params}")}
  end

  def handle_event("change_tab", %{"tab" => tab}, socket) when tab in @tabs do
    params = build_params(tab, socket.assigns.selected_app, "1h")
    {:noreply, push_patch(socket, to: ~p"/dashboard?#{params}")}
  end

  def handle_event("select_app", %{"app" => app_id}, socket) do
    params = build_params("channels", find_app(socket.assigns.applications, app_id), "1h")
    {:noreply, push_patch(socket, to: ~p"/dashboard?#{params}")}
  end

  # Private helpers

  defp build_params(tab, selected_app, period) do
    %{}
    |> then(fn p -> if tab != "messages", do: Map.put(p, "tab", tab), else: p end)
    |> then(fn p -> if selected_app, do: Map.put(p, "app", selected_app.id), else: p end)
    |> Map.put("period", period)
  end

  defp load_tab_data(socket, "messages", _app_id), do: load_relay_stats(socket)

  defp load_tab_data(socket, "channels", app_id) do
    selected_app =
      find_app(socket.assigns.applications, app_id) ||
        auto_select_app(socket.assigns.applications)

    updated = assign(socket, :selected_app, selected_app)

    if selected_app, do: load_channel_stats(updated), else: updated
  end

  defp auto_select_app([single_app]), do: single_app
  defp auto_select_app(_), do: nil

  defp find_app(_applications, nil), do: nil

  defp find_app(applications, app_id) do
    Enum.find(applications, &(&1.id == app_id))
  end

  defp manage_subscriptions(socket, tab) do
    tenant_id = socket.assigns.current_tenant.id
    channel_topic = "channels:tenant:#{tenant_id}"

    if connected?(socket) do
      case {socket.assigns.tab, tab} do
        {old, new} when old != "channels" and new == "channels" ->
          Phoenix.PubSub.subscribe(Ricqchet.PubSub, channel_topic)
          Process.send_after(self(), :refresh_channel_stats, @channel_refresh_interval)
          socket

        {old, new} when old == "channels" and new != "channels" ->
          Phoenix.PubSub.unsubscribe(Ricqchet.PubSub, channel_topic)
          socket

        _ ->
          socket
      end
    else
      socket
    end
  end

  defp load_relay_stats(socket) do
    tenant = socket.assigns.current_tenant
    opts = [period: socket.assigns.period]

    socket
    |> assign(:message_counts, Stats.message_counts(tenant, opts))
    |> assign(:delivery, Stats.delivery_performance(tenant, opts))
    |> assign(:errors, Stats.error_breakdown(tenant, opts))
    |> assign(:destinations, Stats.destination_metrics(tenant, opts))
    |> assign(:recent_activity, Stats.recent_activity(tenant, Keyword.merge(opts, limit: 10)))
  end

  defp load_channel_stats(socket) do
    app_id = socket.assigns.selected_app.id
    opts = [period: socket.assigns.period]

    channel_events =
      app_id
      |> ChannelStats.recent_channel_events(opts)
      |> Enum.map(fn event ->
        %{
          application_id: app_id,
          channel: event.channel,
          event: event.event_name,
          timestamp: event.inserted_at
        }
      end)

    socket
    |> assign(:channel_overview, ChannelStats.overview(app_id))
    |> assign(:channel_list, ChannelStats.active_channels(app_id))
    |> assign(:type_breakdown, ChannelStats.type_breakdown(app_id))
    |> assign(:channel_events, channel_events)
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

  defp channel_type_variant("public"), do: "secondary"
  defp channel_type_variant("private"), do: "default"
  defp channel_type_variant("presence"), do: "success"
  defp channel_type_variant(_), do: "secondary"

  attr :status, :string, required: true

  defp status_dot(assigns) do
    ~H"""
    <span class={[
      "h-2 w-2 rounded-full shrink-0",
      case @status do
        "delivered" -> "bg-emerald-500"
        "failed" -> "bg-accent-400"
        "dispatched" -> "bg-amber-500"
        _ -> "bg-[hsl(var(--muted-foreground))]"
      end
    ]} />
    """
  end
end
