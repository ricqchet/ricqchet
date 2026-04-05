defmodule RicqchetWeb.SessionController do
  use RicqchetWeb, :controller

  alias Ricqchet.Auth

  def register(conn, %{"tenant_name" => tenant_name, "email" => email, "password" => password}) do
    attrs = %{"tenant_name" => tenant_name, "email" => email, "password" => password}

    case Auth.register_user(attrs) do
      {:ok, _result} ->
        conn
        |> put_flash(:info, "Account created! Please check your email to verify.")
        |> redirect(to: ~p"/login")

      {:error, _step, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(RicqchetWeb.PageHTML)
        |> render(:register,
          page_title: "Create account",
          error: format_changeset_errors(changeset),
          errors: %{}
        )
    end
  end

  def create(conn, %{"email" => email, "password" => password}) do
    case Auth.login(email, password) do
      {:ok, %{user: user}} ->
        conn
        |> configure_session(renew: true)
        |> put_session(:user_id, user.id)
        |> put_flash(:info, "Welcome back!")
        |> redirect(to: ~p"/dashboard")

      {:error, :email_not_verified} ->
        render_login(conn, "Please verify your email before logging in.")

      {:error, _reason} ->
        render_login(conn, "Invalid email or password.")
    end
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "Logged out successfully.")
    |> redirect(to: ~p"/login")
  end

  defp render_login(conn, error) do
    conn
    |> put_status(:unauthorized)
    |> put_view(RicqchetWeb.PageHTML)
    |> render(:login, page_title: "Log in", error: error)
  end

  defp format_changeset_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field}: #{Enum.join(msgs, ", ")}" end)
  end
end
