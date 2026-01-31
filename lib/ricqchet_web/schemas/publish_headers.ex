defmodule RicqchetWeb.Schemas.PublishHeaders do
  @moduledoc """
  Defines custom Ricqchet headers for the publish endpoint.
  """

  alias OpenApiSpex.Parameter
  alias OpenApiSpex.Schema

  @doc """
  Returns the list of custom Ricqchet header parameters.
  """
  def parameters do
    [
      %Parameter{
        name: "Ricqchet-Destination",
        in: :header,
        required: true,
        schema: %Schema{type: :string, format: :uri},
        description:
          "Full destination URL including scheme (e.g., https://example.com/webhook). The message payload will be delivered to this URL."
      },
      %Parameter{
        name: "Ricqchet-Delay",
        in: :header,
        required: false,
        schema: %Schema{type: :string, pattern: "^\\d+[smhd]?$"},
        description:
          "Delay before first delivery attempt. Supports units: s (seconds), m (minutes), h (hours), d (days). Examples: '30s', '5m', '2h', '1d'. Maximum: 7 days."
      },
      %Parameter{
        name: "Ricqchet-Dedup-Key",
        in: :header,
        required: false,
        schema: %Schema{type: :string},
        description:
          "Deduplication key to prevent duplicate messages. Messages with the same key within the TTL window will be rejected with 409 Conflict."
      },
      %Parameter{
        name: "Ricqchet-Dedup-TTL",
        in: :header,
        required: false,
        schema: %Schema{type: :integer, default: 300, minimum: 1},
        description: "Deduplication window in seconds. Default: 300 (5 minutes)."
      },
      %Parameter{
        name: "Ricqchet-Retries",
        in: :header,
        required: false,
        schema: %Schema{type: :integer, minimum: 0},
        description: "Override maximum retry attempts for this message. Default: 3."
      },
      %Parameter{
        name: "Ricqchet-Batch-Key",
        in: :header,
        required: false,
        schema: %Schema{type: :string},
        description:
          "Group messages into a batch by this key. Messages with the same batch key will be delivered together."
      },
      %Parameter{
        name: "Ricqchet-Batch-Size",
        in: :header,
        required: false,
        schema: %Schema{type: :integer, default: 10, minimum: 1, maximum: 1000},
        description: "Maximum messages per batch. Default: 10, Maximum: 1000."
      },
      %Parameter{
        name: "Ricqchet-Batch-Timeout",
        in: :header,
        required: false,
        schema: %Schema{type: :integer, default: 5, minimum: 1, maximum: 3600},
        description:
          "Seconds to wait before sending an incomplete batch. Default: 5, Maximum: 3600 (1 hour)."
      }
    ]
  end

  @doc """
  Returns documentation for the dynamic Ricqchet-Forward-* headers.
  """
  @spec forward_header_description() :: String.t()
  def forward_header_description do
    """
    **Header Forwarding:** Headers prefixed with `Ricqchet-Forward-` will be forwarded \
    to the destination URL with the prefix stripped. For example, \
    `Ricqchet-Forward-X-Custom: value` becomes `X-Custom: value` in the delivered request.
    """
  end
end
