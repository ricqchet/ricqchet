defmodule RicqchetWeb.SessionController do
  use RicqchetWeb, :controller

  alias Ricqchet.Auth

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
end
