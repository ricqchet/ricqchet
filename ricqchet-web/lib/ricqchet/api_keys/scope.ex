defmodule Ricqchet.ApiKeys.Scope do
  @moduledoc """
  Single source of truth for API key scopes.

  An API key's scope determines which surfaces it may use. Ricqchet has two
  scopes, in an ordered superset relationship (`relay` ⊇ `subscribe`):

    * `relay` — the full, server-side key (the default). Authorizes every
      key-authenticated REST relay endpoint (publish, channel events, message
      read/delete, the webhook signing secret, forced disconnect) *and* the
      real-time channels WebSocket.
    * `subscribe` — a **browser-safe** key. Authorizes the channels WebSocket
      only (subscribe to channels, receive events, presence, client events on
      private/presence channels). It is rejected on every REST relay endpoint,
      so it can be embedded in untrusted browser code without exposing the
      relay surface or the signing secret.

  This module mirrors `Ricqchet.Authorization` (which owns user *roles*): the
  REST pipeline plug, the channel socket, controllers, and views all ask this
  module rather than string-matching scope values inline.

  ## Why a strict allow-list

  `can_relay?/1` is deliberately fail-closed: it returns `true` only for the
  literal `"relay"` and `false` for everything else (including `nil` and
  unknown values). The relay surface — including the webhook signing secret —
  must never be reachable by a key that is not unambiguously a relay key.
  """

  alias Ricqchet.ApiKeys.ApiKey

  @relay "relay"
  @subscribe "subscribe"
  @scopes [@relay, @subscribe]

  @typedoc "A valid API key scope string."
  @type t :: String.t()

  @doc "Returns the list of valid scope strings."
  @spec scopes() :: [t()]
  def scopes, do: @scopes

  @doc "Returns the default scope assigned when none is specified."
  @spec default() :: t()
  def default, do: @relay

  @doc "The full relay scope string."
  @spec relay() :: t()
  def relay, do: @relay

  @doc "The browser-safe subscribe scope string."
  @spec subscribe() :: t()
  def subscribe, do: @subscribe

  @doc "Returns `true` when `scope` is a known scope value."
  @spec valid?(term()) :: boolean()
  def valid?(scope), do: scope in @scopes

  @doc """
  Returns `true` when the key may use the REST relay surface.

  Fail-closed: `true` only for an exact `relay` scope, `false` for `subscribe`,
  `nil`, structs missing the field, or any unknown value.
  """
  @spec can_relay?(ApiKey.t() | t() | term()) :: boolean()
  def can_relay?(%ApiKey{scope: scope}), do: can_relay?(scope)
  def can_relay?(@relay), do: true
  def can_relay?(_), do: false

  @doc """
  Returns `true` when the key may connect to the channels WebSocket.

  Both scopes may subscribe — `relay` is a superset of `subscribe`.
  """
  @spec can_subscribe?(ApiKey.t() | t() | term()) :: boolean()
  def can_subscribe?(%ApiKey{scope: scope}), do: can_subscribe?(scope)
  def can_subscribe?(scope), do: scope in @scopes
end
