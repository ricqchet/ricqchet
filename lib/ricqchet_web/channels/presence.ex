defmodule RicqchetWeb.Channels.Presence do
  @moduledoc """
  Phoenix Presence for channel presence tracking.

  Tracks connected users in `presence-` prefixed channels, providing
  real-time join/leave events and member lists.
  """

  use Phoenix.Presence,
    otp_app: :ricqchet,
    pubsub_server: Ricqchet.PubSub
end
