defmodule Ricqchet.AuthorizationTest do
  use ExUnit.Case, async: true

  alias Ricqchet.Authorization
  alias Ricqchet.Users.User

  @admin %User{role: "admin"}
  @member %User{role: "member"}
  @viewer %User{role: "viewer"}

  describe "admin?/1" do
    test "true only for admins" do
      assert Authorization.admin?(@admin)
      refute Authorization.admin?(@member)
      refute Authorization.admin?(@viewer)
    end
  end

  describe "editor?/1" do
    test "true for admin and member, false for viewer" do
      assert Authorization.editor?(@admin)
      assert Authorization.editor?(@member)
      refute Authorization.editor?(@viewer)
    end
  end

  describe "viewer?/1" do
    test "true only for viewers" do
      refute Authorization.viewer?(@admin)
      refute Authorization.viewer?(@member)
      assert Authorization.viewer?(@viewer)
    end
  end

  describe "can?/2" do
    test ":write is allowed for admin and member only" do
      assert Authorization.can?(@admin, :write)
      assert Authorization.can?(@member, :write)
      refute Authorization.can?(@viewer, :write)
    end

    test ":manage_users and :manage_settings are admin only" do
      for action <- [:manage_users, :manage_settings] do
        assert Authorization.can?(@admin, action)
        refute Authorization.can?(@member, action)
        refute Authorization.can?(@viewer, action)
      end
    end
  end

  describe "authorize/2" do
    test ":admin level" do
      assert Authorization.authorize(@admin, :admin) == :ok
      assert Authorization.authorize(@member, :admin) == {:error, :forbidden}
      assert Authorization.authorize(@viewer, :admin) == {:error, :forbidden}
    end

    test ":editor level" do
      assert Authorization.authorize(@admin, :editor) == :ok
      assert Authorization.authorize(@member, :editor) == :ok
      assert Authorization.authorize(@viewer, :editor) == {:error, :forbidden}
    end
  end
end
