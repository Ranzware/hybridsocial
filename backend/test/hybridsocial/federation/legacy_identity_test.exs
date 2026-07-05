defmodule Hybridsocial.Federation.LegacyIdentityTest do
  @moduledoc """
  Foundation for importing actors from a retired Pleroma/Rebased instance:
  a local identity can keep a foreign-shaped `ap_actor_url` + imported
  keypair and still be classified local.
  """
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Accounts
  alias Hybridsocial.Accounts.Identity
  alias Hybridsocial.Federation.LocalUrl
  alias Hybridsocial.Repo

  # Minimal well-formed PEM stand-ins — the storage layer treats them as
  # opaque strings; wire-level signing is exercised elsewhere.
  @pub "-----BEGIN PUBLIC KEY-----\nMIIBIjANBg...\n-----END PUBLIC KEY-----\n"
  @priv "-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAK...\n-----END RSA PRIVATE KEY-----\n"

  defp import_actor(handle, ap_url) do
    %{
      "type" => "user",
      "handle" => handle,
      "display_name" => handle,
      "ap_actor_url" => ap_url,
      "public_key" => @pub,
      "private_key" => @priv,
      "inbox_url" => ap_url <> "/inbox",
      "outbox_url" => ap_url <> "/outbox",
      "followers_url" => ap_url <> "/followers",
      "following_url" => ap_url <> "/following"
    }
    |> Identity.import_changeset()
    |> Repo.insert()
  end

  describe "import_changeset/2" do
    test "preserves the imported URI and keypair, marks the actor local" do
      handle = "legacy_#{:erlang.unique_integer([:positive])}"
      ap_url = "https://bassam.social/users/#{handle}"

      assert {:ok, identity} = import_actor(handle, ap_url)

      # Original identity preserved verbatim — not regenerated.
      assert identity.ap_actor_url == ap_url
      assert identity.public_key == @pub
      assert identity.private_key == @priv
      assert identity.inbox_url == ap_url <> "/inbox"
      assert identity.following_url == ap_url <> "/following"
      assert identity.is_local == true
    end

    test "requires the identity-defining fields" do
      cs = Identity.import_changeset(%{"type" => "user", "handle" => "x"})
      refute cs.valid?
      assert %{ap_actor_url: _, public_key: _, private_key: _} = errors_on(cs)
    end
  end

  describe "LocalUrl.local_identity?/1" do
    test "true for an imported actor despite its foreign-shaped URL" do
      handle = "legacy_#{:erlang.unique_integer([:positive])}"
      {:ok, identity} = import_actor(handle, "https://bassam.social/users/#{handle}")
      assert LocalUrl.local_identity?(identity)
    end

    test "true for a natively-registered user" do
      uniq = :erlang.unique_integer([:positive])

      {:ok, identity} =
        Accounts.register_user(%{
          "handle" => "native_#{uniq}",
          "email" => "native_#{uniq}@test.com",
          "display_name" => "Native",
          "password" => "correct-horse-battery-staple",
          "password_confirmation" => "correct-horse-battery-staple"
        })

      assert identity.is_local == true
      assert LocalUrl.local_identity?(identity)
    end

    test "false for a remote identity, regardless of URL" do
      assert LocalUrl.local_identity?(%Identity{is_local: false, ap_actor_url: "https://remote.social/users/bob"}) ==
               false
    end

    test "falls back to the URL prefix only when is_local is nil" do
      base = LocalUrl.base_url()
      assert LocalUrl.local_identity?(%Identity{is_local: nil, ap_actor_url: base <> "/actors/abc"})
      refute LocalUrl.local_identity?(%Identity{is_local: nil, ap_actor_url: "https://remote.social/users/bob"})
    end
  end
end
