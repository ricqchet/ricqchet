defmodule RicqchetWeb.TenantUserJSON do
  @moduledoc """
  JSON views for tenant user endpoints.
  """

  alias Ricqchet.Users.User

  @doc """
  Renders tenant user JSON responses.

  - `index.json` - Paginated list of users
  - `show.json` - Single user details
  - `created.json` - Newly created user (with one-time password when generated)
  - `deleted.json` - User removal confirmation
  """
  def render(template, assigns)

  def render("index.json", %{users: users, meta: meta}) do
    %{
      data: Enum.map(users, &user_json/1),
      meta: meta_json(meta)
    }
  end

  def render("show.json", %{user: user}) do
    user_json(user)
  end

  def render("created.json", %{user: user, password: password}) do
    user
    |> user_json()
    |> maybe_put_password(password)
  end

  def render("deleted.json", %{id: id}) do
    %{
      id: id,
      message: "User removed from tenant"
    }
  end

  defp user_json(%User{} = user) do
    %{
      id: user.id,
      email: user.email,
      role: user.role,
      status: user.status,
      confirmed_at: user.confirmed_at,
      last_login_at: user.last_login_at,
      inserted_at: user.inserted_at,
      updated_at: user.updated_at
    }
  end

  defp maybe_put_password(user_map, nil), do: user_map
  defp maybe_put_password(user_map, password), do: Map.put(user_map, :password, password)

  defp meta_json(meta) do
    %{
      total: meta.total_count,
      has_next_page: meta.has_next_page?,
      has_previous_page: meta.has_previous_page?,
      start_cursor: meta.start_cursor,
      end_cursor: meta.end_cursor,
      current_offset: meta.current_offset,
      current_page: meta.current_page,
      total_pages: meta.total_pages
    }
  end
end
