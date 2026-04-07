defmodule RicqchetWeb.PageController do
  use RicqchetWeb, :controller

  def index(conn, _params) do
    if conn.assigns[:current_user] do
      redirect(conn, to: ~p"/dashboard")
    else
      redirect(conn, to: ~p"/login")
    end
  end

  def login(conn, _params) do
    if conn.assigns[:current_user] do
      redirect(conn, to: ~p"/dashboard")
    else
      render(conn, :login, page_title: "Log in", error: nil)
    end
  end

  def register(conn, _params) do
    if conn.assigns[:current_user] do
      redirect(conn, to: ~p"/dashboard")
    else
      render(conn, :register, page_title: "Create account", error: nil, errors: %{})
    end
  end

  def forgot_password(conn, _params) do
    render(conn, :forgot_password, page_title: "Forgot password", submitted: false)
  end

  def submit_forgot_password(conn, %{"email" => email}) do
    # Always show success to prevent email enumeration
    Ricqchet.Auth.request_password_reset(email)
    render(conn, :forgot_password, page_title: "Forgot password", submitted: true)
  end

  def reset_password(conn, _params) do
    render(conn, :reset_password, page_title: "Reset password")
  end

  def verify_email(conn, _params) do
    render(conn, :verify_email, page_title: "Verify email")
  end

  def accept_invite(conn, _params) do
    render(conn, :accept_invite, page_title: "Accept invitation")
  end
end
