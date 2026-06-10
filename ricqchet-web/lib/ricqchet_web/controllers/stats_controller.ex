defmodule RicqchetWeb.StatsController do
  @moduledoc """
  Controller for dashboard statistics and metrics.

  Provides aggregated statistics on messages, delivery performance,
  errors, and destinations scoped to the authenticated tenant.

  All endpoints require JWT authentication.
  """

  use RicqchetWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Ricqchet.Stats
  alias RicqchetWeb.Schemas

  action_fallback RicqchetWeb.FallbackController

  tags(["stats"])

  # Common parameter definitions
  @period_param [
    period: [
      in: :query,
      schema: Schemas.Stats.TimePeriod,
      description: "Time period for statistics: 5m, 1h, 4h, 1d, 1w (default: 1h)"
    ]
  ]

  @limit_param [
    limit: [
      in: :query,
      schema: %Schema{type: :integer, minimum: 1, maximum: 50, default: 10},
      description: "Maximum number of items to return"
    ]
  ]

  operation(:messages,
    summary: "Get message count statistics",
    description: """
    Returns message counts grouped by status (pending, dispatched, delivered, failed)
    for the specified time period.

    Requires JWT authentication.
    """,
    parameters: @period_param,
    responses: Schemas.Helpers.show_responses(Schemas.Stats.MessageStats, [401, 429]),
    security: [%{"bearer_auth" => []}]
  )

  @doc """
  Returns message counts by status for the current tenant.
  """
  def messages(conn, params) do
    tenant = conn.assigns.current_tenant
    opts = extract_period_opts(params)

    stats = Stats.message_counts(tenant, opts)
    render(conn, :messages, stats: stats)
  end

  operation(:message_sizes,
    summary: "Get message size statistics",
    description: """
    Returns payload size statistics including average, total, and percentile distribution
    (p50, p95, p99) for the specified time period.

    Requires JWT authentication.
    """,
    parameters: @period_param,
    responses: Schemas.Helpers.show_responses(Schemas.Stats.MessageSizeStats, [401, 429]),
    security: [%{"bearer_auth" => []}]
  )

  @doc """
  Returns message size statistics for the current tenant.
  """
  def message_sizes(conn, params) do
    tenant = conn.assigns.current_tenant
    opts = extract_period_opts(params)

    stats = Stats.message_sizes(tenant, opts)
    render(conn, :message_sizes, stats: stats)
  end

  operation(:delivery,
    summary: "Get delivery performance statistics",
    description: """
    Returns delivery performance metrics including success rate, retry rate,
    and delivery time percentiles (average, p95, p99) for the specified time period.

    Requires JWT authentication.
    """,
    parameters: @period_param,
    responses: Schemas.Helpers.show_responses(Schemas.Stats.DeliveryStats, [401, 429]),
    security: [%{"bearer_auth" => []}]
  )

  @doc """
  Returns delivery performance statistics for the current tenant.
  """
  def delivery(conn, params) do
    tenant = conn.assigns.current_tenant
    opts = extract_period_opts(params)

    stats = Stats.delivery_performance(tenant, opts)
    render(conn, :delivery, stats: stats)
  end

  operation(:errors,
    summary: "Get error breakdown statistics",
    description: """
    Returns error statistics including counts by error type, by HTTP status code,
    and top failing destinations for the specified time period.

    Error types: timeout, connection_refused, ssl_error, dns_error, http_4xx, http_5xx, other

    Requires JWT authentication.
    """,
    parameters: @period_param ++ @limit_param,
    responses: Schemas.Helpers.show_responses(Schemas.Stats.ErrorStats, [401, 429]),
    security: [%{"bearer_auth" => []}]
  )

  @doc """
  Returns error breakdown statistics for the current tenant.
  """
  def errors(conn, params) do
    tenant = conn.assigns.current_tenant
    opts = extract_period_opts(params) ++ extract_limit_opts(params)

    stats = Stats.error_breakdown(tenant, opts)
    render(conn, :errors, stats: stats)
  end

  operation(:destinations,
    summary: "Get destination metrics",
    description: """
    Returns per-destination metrics including message volume, success rate,
    and average response time, ordered by volume (highest first).

    Requires JWT authentication.
    """,
    parameters: @period_param ++ @limit_param,
    responses: Schemas.Helpers.show_responses(Schemas.Stats.DestinationStats, [401, 429]),
    security: [%{"bearer_auth" => []}]
  )

  @doc """
  Returns destination metrics for the current tenant.
  """
  def destinations(conn, params) do
    tenant = conn.assigns.current_tenant
    opts = extract_period_opts(params) ++ extract_limit_opts(params)

    stats = Stats.destination_metrics(tenant, opts)
    render(conn, :destinations, stats: stats)
  end

  operation(:activity,
    summary: "Get recent activity feed",
    description: """
    Returns a paginated list of recent messages with their delivery status.
    Supports cursor-based pagination for efficient paging through large result sets.

    Requires JWT authentication.
    """,
    parameters:
      @period_param ++
        [
          limit: [
            in: :query,
            schema: %Schema{type: :integer, minimum: 1, maximum: 100, default: 25},
            description: "Maximum number of messages to return"
          ],
          status: [
            in: :query,
            schema: %Schema{type: :string, enum: ["pending", "dispatched", "delivered", "failed"]},
            description: "Filter by message status"
          ],
          after_cursor: [
            in: :query,
            schema: %Schema{type: :string},
            description: "Cursor for pagination (from previous response)"
          ]
        ],
    responses: Schemas.Helpers.show_responses(Schemas.Stats.ActivityStats, [401, 429]),
    security: [%{"bearer_auth" => []}]
  )

  @doc """
  Returns recent message activity for the current tenant.
  """
  def activity(conn, params) do
    tenant = conn.assigns.current_tenant

    opts =
      extract_period_opts(params) ++
        extract_activity_opts(params)

    stats = Stats.recent_activity(tenant, opts)
    render(conn, :activity, stats: stats)
  end

  # Parameter extraction helpers

  defp extract_period_opts(params) do
    case Map.get(params, "period") do
      nil -> []
      period -> [period: period]
    end
  end

  defp extract_limit_opts(params) do
    case Map.get(params, "limit") do
      nil -> []
      limit when is_integer(limit) -> [limit: limit]
      limit when is_binary(limit) -> parse_integer_opt(:limit, limit)
    end
  end

  defp extract_activity_opts(params) do
    []
    |> maybe_add_opt(:limit, params)
    |> maybe_add_opt(:status, params)
    |> maybe_add_opt(:after_cursor, params)
  end

  defp maybe_add_opt(opts, :limit, params) do
    case Map.get(params, "limit") do
      nil -> opts
      limit when is_integer(limit) -> Keyword.put(opts, :limit, limit)
      limit when is_binary(limit) -> opts ++ parse_integer_opt(:limit, limit)
    end
  end

  defp maybe_add_opt(opts, :status, params) do
    case Map.get(params, "status") do
      nil -> opts
      status -> Keyword.put(opts, :status, status)
    end
  end

  defp maybe_add_opt(opts, :after_cursor, params) do
    case Map.get(params, "after_cursor") do
      nil -> opts
      cursor -> Keyword.put(opts, :after_cursor, cursor)
    end
  end

  defp parse_integer_opt(key, value) do
    case Integer.parse(value) do
      {int, ""} -> [{key, int}]
      _ -> []
    end
  end
end
