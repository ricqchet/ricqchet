defmodule Ricqchet.Scope do
  @moduledoc """
  Authorization context passed through the application.

  Contains the authenticated user, their tenant, and any additional
  context needed for authorization decisions. This struct provides
  a single parameter for context functions, making it easy to extend
  with new fields without changing function signatures.

  ## Usage

      # In plugs
      scope = Scope.for_user(user)
      conn = assign(conn, :current_scope, scope)

      # In controllers
      scope = conn.assigns.current_scope
      applications = Applications.list_applications(scope)

      # In contexts
      def list_applications(%Scope{tenant: tenant}) do
        # ...
      end
  """

  alias Ricqchet.Repo
  alias Ricqchet.Tenants.Tenant
  alias Ricqchet.Users.User

  defstruct [:user, :tenant]

  @type t :: %__MODULE__{
          user: User.t(),
          tenant: Tenant.t()
        }

  @doc """
  Builds a scope from an authenticated user.

  Preloads the tenant association if not already loaded.

  ## Examples

      iex> Scope.for_user(user)
      %Scope{user: %User{...}, tenant: %Tenant{...}}
  """
  @spec for_user(User.t()) :: t()
  def for_user(%User{} = user) do
    user = Repo.preload(user, :tenant)
    %__MODULE__{user: user, tenant: user.tenant}
  end
end
