defmodule HybridsocialWeb.Serializers.PostSerializerTest do
  @moduledoc """
  Unit tests for PostSerializer's account block — specifically the
  verification fields that the frontend badge UI keys off.
  """
  use Hybridsocial.DataCase, async: true

  alias HybridsocialWeb.Serializers.PostSerializer

  defp identity(attrs) do
    base = %Hybridsocial.Accounts.Identity{
      id: Ecto.UUID.generate(),
      type: "user",
      handle: "alice",
      display_name: "Alice",
      inserted_at: ~U[2026-01-01 00:00:00.000000Z]
    }

    Map.merge(base, attrs)
  end

  describe "serialize_account/2 verification fields" do
    test "includes verification_tier and is_verified=true for paid tiers" do
      for tier <- ["verified_starter", "verified_creator", "verified_pro"] do
        account = PostSerializer.serialize_account(identity(%{verification_tier: tier}), [])

        assert account.verification_tier == tier
        assert account.is_verified == true
      end
    end

    test "is_verified=false for the free tier" do
      account = PostSerializer.serialize_account(identity(%{verification_tier: "free"}), [])

      assert account.verification_tier == "free"
      assert account.is_verified == false
    end

    test "is_verified=false when verification_tier is nil" do
      account = PostSerializer.serialize_account(identity(%{verification_tier: nil}), [])

      assert account.verification_tier == nil
      assert account.is_verified == false
    end

    test "is_verified=false for unknown tier strings" do
      account = PostSerializer.serialize_account(identity(%{verification_tier: "garbage"}), [])

      assert account.is_verified == false
    end
  end

  describe "serialize_account/2 type translation" do
    test "emits 'page' instead of 'organization' at the API boundary" do
      account = PostSerializer.serialize_account(identity(%{type: "organization"}), [])
      assert account.type == "page"
    end

    test "passes other types through unchanged" do
      for t <- ["user", "bot", "group"] do
        account = PostSerializer.serialize_account(identity(%{type: t}), [])
        assert account.type == t
      end
    end
  end

  describe "remote media attachments" do
    alias Hybridsocial.Media.MediaFile

    test "remote_changeset accepts remote-only attrs (no storage_path)" do
      changeset =
        MediaFile.remote_changeset(%MediaFile{}, %{
          identity_id: Ecto.UUID.generate(),
          post_id: Ecto.UUID.generate(),
          content_type: "image/jpeg",
          remote_url: "https://mastodon.example/system/img/1.jpg",
          remote_origin_domain: "mastodon.example",
          alt_text: "a cat",
          width: 800,
          height: 600
        })

      assert changeset.valid?
      assert changeset.changes.remote_url == "https://mastodon.example/system/img/1.jpg"
      assert changeset.changes.remote_origin_domain == "mastodon.example"
      # storage_path stays nil — that's the marker that bytes live remote.
      refute Map.has_key?(changeset.changes, :storage_path)
    end

    test "remote_changeset rejects missing remote_url" do
      changeset =
        MediaFile.remote_changeset(%MediaFile{}, %{
          identity_id: Ecto.UUID.generate(),
          remote_origin_domain: "mastodon.example"
        })

      refute changeset.valid?
      assert {_, _} = changeset.errors[:remote_url]
    end

    test "remote_changeset rejects missing identity_id" do
      changeset =
        MediaFile.remote_changeset(%MediaFile{}, %{
          remote_url: "https://mastodon.example/system/img/1.jpg",
          remote_origin_domain: "mastodon.example"
        })

      refute changeset.valid?
      assert {_, _} = changeset.errors[:identity_id]
    end
  end
end
