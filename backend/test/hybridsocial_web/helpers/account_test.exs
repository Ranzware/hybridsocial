defmodule HybridsocialWeb.Helpers.AccountTest do
  use ExUnit.Case, async: true

  alias HybridsocialWeb.Helpers.Account

  describe "api_type/1" do
    test "translates :organization (atom) to 'page'" do
      assert Account.api_type(:organization) == "page"
    end

    test "translates \"organization\" (string) to 'page'" do
      assert Account.api_type("organization") == "page"
    end

    test "passes through other atoms as strings" do
      assert Account.api_type(:user) == "user"
      assert Account.api_type(:bot) == "bot"
      assert Account.api_type(:group) == "group"
    end

    test "passes through other strings unchanged" do
      assert Account.api_type("user") == "user"
      assert Account.api_type("bot") == "bot"
      assert Account.api_type("group") == "group"
    end

    test "returns nil for invalid input" do
      assert Account.api_type(nil) == nil
      assert Account.api_type(42) == nil
    end
  end
end
