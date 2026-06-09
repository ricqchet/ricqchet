defmodule Ricqchet.Authorization do
  @moduledoc """
  Centralized role-based authorization.

  Ricqchet is a single-org, self-hosted deployment with three user roles:

    * `admin`  — full control: manage users, instance settings, and all resources.
    * `member` — "editor": create/edit/delete applications, API keys, and channel
      namespaces, and cancel messages, but cannot manage users or instance settings.
    * `viewer` — read-only access to everything.

  This module is the single source of truth for those rules. It is shared by the
  JSON API controllers, the LiveView dashboard, and HEEx templates so the same
  checks apply on every surface — a user who cannot perform an action via the API
  also never sees the control for it in the UI.
  """

  alias Ricqchet.Users.User

  @doc "Returns `true` when the user is an admin."
  @spec admin?(User.t()) :: boolean()
  def admin?(%User{role: "admin"}), do: true
  def admin?(%User{}), do: false

  @doc "Returns `true` when the user can make changes (admin or member)."
  @spec editor?(User.t()) :: boolean()
  def editor?(%User{role: role}), do: role in ["admin", "member"]

  @doc "Returns `true` when the user is read-only (anything that is not an editor)."
  @spec viewer?(User.t()) :: boolean()
  def viewer?(%User{} = user), do: not editor?(user)

  @doc """
  Returns `true` when `user` is permitted to perform `action`.

    * `:write`           — mutate resources (applications, API keys, namespaces, messages).
    * `:manage_users`    — create/update/remove users.
    * `:manage_settings` — change instance/tenant settings.

  Intended for use in templates to show or hide controls.
  """
  @spec can?(User.t(), :write | :manage_users | :manage_settings) :: boolean()
  def can?(%User{} = user, :write), do: editor?(user)
  def can?(%User{} = user, :manage_users), do: admin?(user)
  def can?(%User{} = user, :manage_settings), do: admin?(user)

  @doc """
  Authorization guard for `with` chains in controllers.

  Returns `:ok` when the user holds at least the required role level, otherwise
  `{:error, :forbidden}` — which `RicqchetWeb.FallbackController` renders as a 403.

    * `:admin`  — admin only.
    * `:editor` — admin or member.
  """
  @spec authorize(User.t(), :admin | :editor) :: :ok | {:error, :forbidden}
  def authorize(%User{} = user, :admin) do
    if admin?(user), do: :ok, else: {:error, :forbidden}
  end

  def authorize(%User{} = user, :editor) do
    if editor?(user), do: :ok, else: {:error, :forbidden}
  end
end
