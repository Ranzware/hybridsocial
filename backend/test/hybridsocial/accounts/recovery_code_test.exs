defmodule Hybridsocial.Accounts.RecoveryCodeTest do
  use Hybridsocial.DataCase, async: true

  alias Hybridsocial.Accounts
  alias Hybridsocial.Accounts.{Identity, RecoveryCode, User}

  defp register(handle) do
    uniq = :erlang.unique_integer([:positive])
    email = "#{handle}_#{uniq}@test.com"

    {:ok, identity} =
      Accounts.register_user(%{
        "handle" => "#{handle}_#{uniq}",
        "email" => email,
        "display_name" => handle,
        "password" => "password1234567890",
        "password_confirmation" => "password1234567890"
      })

    {identity, email}
  end

  defp enable_2fa(identity) do
    user = Repo.get_by!(User, identity_id: identity.id)
    raw_secret = NimbleTOTP.secret()
    encoded = Base.encode32(raw_secret, padding: false)

    {:ok, user} =
      user
      |> Ecto.Changeset.change(otp_secret: encoded, otp_enabled: true)
      |> Repo.update()

    {user, raw_secret}
  end

  defp totp_code(secret), do: NimbleTOTP.verification_code(secret)

  defp validate_params(identity, current_email, code, otp) do
    %{
      "handle" => identity.handle,
      "recovery_code" => code,
      "otp_code" => otp,
      "current_email" => current_email
    }
  end

  describe "RecoveryCode.generate/0" do
    test "returns 20 chars + 3 dashes in 4 groups of 5" do
      code = RecoveryCode.generate()
      assert String.length(code) == 23
      assert String.contains?(code, "-")

      groups = String.split(code, "-")
      assert length(groups) == 4
      assert Enum.all?(groups, &(String.length(&1) == 5))
    end

    test "draws from an unambiguous alphabet (no 0/1/I/L/O/U)" do
      banned = MapSet.new(["0", "1", "I", "L", "O", "U"])

      for _ <- 1..50 do
        code = RecoveryCode.generate()
        chars = code |> String.replace("-", "") |> String.graphemes() |> MapSet.new()
        assert MapSet.disjoint?(chars, banned)
      end
    end
  end

  describe "RecoveryCode.normalize/1 and verify/2" do
    test "verify ignores case, spaces, and extra dashes" do
      code = RecoveryCode.generate()
      hash = RecoveryCode.hash(code)

      assert RecoveryCode.verify(code, hash)
      assert RecoveryCode.verify(String.downcase(code), hash)
      assert RecoveryCode.verify(String.replace(code, "-", ""), hash)
      assert RecoveryCode.verify(String.replace(code, "-", " - "), hash)
    end

    test "wrong code fails" do
      hash = RecoveryCode.hash(RecoveryCode.generate())
      refute RecoveryCode.verify(RecoveryCode.generate(), hash)
    end

    test "nil hash always fails (no enumeration)" do
      refute RecoveryCode.verify("anything", nil)
    end
  end

  describe "Accounts.generate_recovery_code/2" do
    test "stores a hash and returns plaintext once (2FA enabled)" do
      {identity, _email} = register("gen_user")
      {_user, _secret} = enable_2fa(identity)

      assert {:ok, code, updated} =
               Accounts.generate_recovery_code(identity.id, "password1234567890")

      assert is_binary(code)
      assert String.length(code) == 23
      assert updated.recovery_code_hash != nil
      refute updated.recovery_code_hash == code
      assert RecoveryCode.verify(code, updated.recovery_code_hash)
    end

    test "requires 2FA to be enabled" do
      {identity, _email} = register("no_2fa")

      assert {:error, :two_factor_required} =
               Accounts.generate_recovery_code(identity.id, "password1234567890")
    end

    test "rotates: old code stops working after a regeneration" do
      {identity, _email} = register("rotate_user")
      {_user, _secret} = enable_2fa(identity)

      {:ok, old_code, _} = Accounts.generate_recovery_code(identity.id, "password1234567890")

      {:ok, new_code, updated} =
        Accounts.generate_recovery_code(identity.id, "password1234567890")

      refute old_code == new_code
      refute RecoveryCode.verify(old_code, updated.recovery_code_hash)
      assert RecoveryCode.verify(new_code, updated.recovery_code_hash)
    end

    test "rejects a wrong password" do
      {identity, _email} = register("wrongpw")
      {_user, _secret} = enable_2fa(identity)
      assert {:error, :invalid_password} = Accounts.generate_recovery_code(identity.id, "not-it")
    end
  end

  describe "Accounts.clear_recovery_code/2" do
    test "nulls out the hash" do
      {identity, _email} = register("clr_user")
      {_user, _secret} = enable_2fa(identity)
      {:ok, _, _} = Accounts.generate_recovery_code(identity.id, "password1234567890")

      assert {:ok, updated} = Accounts.clear_recovery_code(identity.id, "password1234567890")
      assert updated.recovery_code_hash == nil
    end

    test "rejects without password" do
      {identity, _email} = register("clr_wrongpw")
      {_user, _secret} = enable_2fa(identity)
      {:ok, _, _} = Accounts.generate_recovery_code(identity.id, "password1234567890")

      assert {:error, :invalid_password} = Accounts.clear_recovery_code(identity.id, "nope")
    end
  end

  describe "Accounts.validate_recovery_factors/1" do
    test "returns {:ok, identity} when all four factors match" do
      {identity, current_email} = register("vrf_ok")
      {_user, secret} = enable_2fa(identity)
      {:ok, code, _} = Accounts.generate_recovery_code(identity.id, "password1234567890")

      assert {:ok, got} =
               Accounts.validate_recovery_factors(
                 validate_params(identity, current_email, code, totp_code(secret))
               )

      assert got.id == identity.id
    end

    test "accepts current email case-insensitively and with whitespace" do
      {identity, current_email} = register("vrf_ci")
      {_user, secret} = enable_2fa(identity)
      {:ok, code, _} = Accounts.generate_recovery_code(identity.id, "password1234567890")

      assert {:ok, _} =
               Accounts.validate_recovery_factors(
                 validate_params(
                   identity,
                   "  #{String.upcase(current_email)}  ",
                   code,
                   totp_code(secret)
                 )
               )
    end

    test "rejects wrong code" do
      {identity, current_email} = register("vrf_wc")
      {_user, secret} = enable_2fa(identity)
      {:ok, _code, _} = Accounts.generate_recovery_code(identity.id, "password1234567890")

      assert {:error, :invalid_credentials} =
               Accounts.validate_recovery_factors(
                 validate_params(
                   identity,
                   current_email,
                   RecoveryCode.generate(),
                   totp_code(secret)
                 )
               )
    end

    test "rejects wrong OTP" do
      {identity, current_email} = register("vrf_wo")
      {_user, _secret} = enable_2fa(identity)
      {:ok, code, _} = Accounts.generate_recovery_code(identity.id, "password1234567890")

      assert {:error, :invalid_credentials} =
               Accounts.validate_recovery_factors(
                 validate_params(identity, current_email, code, "000000")
               )
    end

    test "rejects wrong current email" do
      {identity, _email} = register("vrf_we")
      {_user, secret} = enable_2fa(identity)
      {:ok, code, _} = Accounts.generate_recovery_code(identity.id, "password1234567890")

      assert {:error, :invalid_credentials} =
               Accounts.validate_recovery_factors(
                 validate_params(identity, "not-the-real@test.com", code, totp_code(secret))
               )
    end

    test "rejects unknown handle" do
      assert {:error, :invalid_credentials} =
               Accounts.validate_recovery_factors(%{
                 "handle" => "definitelynotreal",
                 "recovery_code" => RecoveryCode.generate(),
                 "otp_code" => "123456",
                 "current_email" => "ghost@test.com"
               })
    end

    test "rejects when any required field is missing" do
      assert {:error, :invalid_credentials} =
               Accounts.validate_recovery_factors(%{
                 "handle" => "whoever",
                 "recovery_code" => "code"
               })
    end

    test "rejects when 2FA not enabled on the account" do
      {identity, current_email} = register("vrf_n2fa")
      code = RecoveryCode.generate()

      identity
      |> Ecto.Changeset.change(%{recovery_code_hash: RecoveryCode.hash(code)})
      |> Repo.update!()

      assert {:error, :invalid_credentials} =
               Accounts.validate_recovery_factors(
                 validate_params(identity, current_email, code, "123456")
               )
    end
  end

  describe "Accounts.complete_recovery/4" do
    test "resets password + email and auto-rotates the code on success" do
      {identity, _current_email} = register("cr_ok")
      {_user, _secret} = enable_2fa(identity)
      {:ok, code, _} = Accounts.generate_recovery_code(identity.id, "password1234567890")

      uniq = :erlang.unique_integer([:positive])
      new_email = "cr_ok_#{uniq}_new@test.com"

      assert {:ok, new_code, recovered} =
               Accounts.complete_recovery(
                 identity.id,
                 new_email,
                 "newpassword1234567890",
                 "newpassword1234567890"
               )

      refute new_code == code
      assert recovered.recovered_at != nil
      assert recovered.recovery_code_last_used_at != nil

      user = Repo.get_by!(User, identity_id: identity.id)
      assert user.email == new_email
      assert Bcrypt.verify_pass("newpassword1234567890", user.password_hash)
      refute Bcrypt.verify_pass("password1234567890", user.password_hash)
      assert user.confirmed_at != nil
    end

    test "rejects weak new password with :invalid_input" do
      {identity, _current_email} = register("cr_weak")

      assert {:error, :invalid_input, _cs} =
               Accounts.complete_recovery(
                 identity.id,
                 "cr_weak_new@test.com",
                 "short",
                 "short"
               )
    end

    test "rejects invalid email with :invalid_input" do
      {identity, _current_email} = register("cr_bad")

      assert {:error, :invalid_input, _cs} =
               Accounts.complete_recovery(
                 identity.id,
                 "not-an-email",
                 "newpassword1234567890",
                 "newpassword1234567890"
               )
    end

    test "rejects unknown identity_id with :not_found" do
      assert {:error, :not_found} =
               Accounts.complete_recovery(
                 Ecto.UUID.generate(),
                 "ghost_new@test.com",
                 "newpassword1234567890",
                 "newpassword1234567890"
               )
    end
  end

  describe "Accounts.in_recovery_cooldown?/1" do
    test "true within 24h of recovered_at, false otherwise" do
      assert false == Accounts.in_recovery_cooldown?(%Identity{recovered_at: nil})

      just_recovered = DateTime.utc_now() |> DateTime.add(-60, :second)
      assert true == Accounts.in_recovery_cooldown?(%Identity{recovered_at: just_recovered})

      long_ago = DateTime.utc_now() |> DateTime.add(-48 * 3600, :second)
      assert false == Accounts.in_recovery_cooldown?(%Identity{recovered_at: long_ago})
    end
  end
end
