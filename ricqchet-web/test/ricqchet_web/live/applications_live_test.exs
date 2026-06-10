defmodule RicqchetWeb.ApplicationsLiveTest do
  use RicqchetWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Ricqchet.Applications

  defp authenticate(conn, user) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end

  describe "role-based access to applications" do
    setup do
      {:ok, %{user: admin, tenant: tenant}} = create_tenant_and_user(role: "admin")
      {:ok, %{user: member}} = create_tenant_and_user(tenant: tenant, role: "member")
      {:ok, %{user: viewer}} = create_tenant_and_user(tenant: tenant, role: "viewer")

      %{tenant: tenant, admin: admin, member: member, viewer: viewer}
    end

    test "editor (member) sees the New application button", %{conn: conn, member: member} do
      conn = authenticate(conn, member)
      {:ok, _view, html} = live(conn, ~p"/applications")
      assert html =~ "New application"
    end

    test "viewer does not see the New application button", %{conn: conn, viewer: viewer} do
      conn = authenticate(conn, viewer)
      {:ok, _view, html} = live(conn, ~p"/applications")
      refute html =~ "New application"
    end

    test "editor (member) can create an application", %{
      conn: conn,
      member: member,
      tenant: tenant
    } do
      conn = authenticate(conn, member)
      {:ok, view, _html} = live(conn, ~p"/applications")

      render_hook(view, "create_application", %{"name" => "Member App", "description" => ""})

      {:ok, {apps, _meta}} = Applications.list_applications_for_tenant(tenant)
      assert Enum.any?(apps, &(&1.name == "Member App"))
    end

    test "viewer cannot create an application even via a direct event", %{
      conn: conn,
      viewer: viewer,
      tenant: tenant
    } do
      conn = authenticate(conn, viewer)
      {:ok, view, _html} = live(conn, ~p"/applications")

      render_hook(view, "create_application", %{"name" => "Sneaky App", "description" => ""})

      {:ok, {apps, _meta}} = Applications.list_applications_for_tenant(tenant)
      assert apps == []
    end
  end
end
