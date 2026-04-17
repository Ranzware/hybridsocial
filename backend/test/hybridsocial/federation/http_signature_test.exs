defmodule Hybridsocial.Federation.HTTPSignatureTest do
  use ExUnit.Case, async: true

  alias Hybridsocial.Federation.HTTPSignature

  setup do
    # Generate a test RSA keypair
    private_key = :public_key.generate_key({:rsa, 2048, 65537})
    private_entry = :public_key.pem_entry_encode(:RSAPrivateKey, private_key)
    private_pem = :public_key.pem_encode([private_entry])

    rsa_public = {:RSAPublicKey, elem(private_key, 2), elem(private_key, 3)}
    public_entry = :public_key.pem_entry_encode(:SubjectPublicKeyInfo, rsa_public)
    public_pem = :public_key.pem_encode([public_entry])

    %{private_pem: private_pem, public_pem: public_pem}
  end

  describe "sign/3" do
    test "returns a map with required headers", %{private_pem: private_pem} do
      request = %{
        method: "POST",
        url: "https://remote.example/inbox",
        body: ~s({"type": "Create"})
      }

      key_id = "https://local.example/actors/123#main-key"
      headers = HTTPSignature.sign(request, private_pem, key_id)

      assert Map.has_key?(headers, "Signature")
      assert Map.has_key?(headers, "Date")
      assert Map.has_key?(headers, "Digest")
      assert Map.has_key?(headers, "Host")

      assert headers["Host"] == "remote.example"
      assert String.starts_with?(headers["Digest"], "SHA-256=")
      assert String.contains?(headers["Signature"], ~s(keyId="#{key_id}"))
      assert String.contains?(headers["Signature"], ~s(algorithm="rsa-sha256"))
    end
  end

  describe "build_signing_string/2" do
    test "constructs correct signing string" do
      headers = ["(request-target)", "host", "date"]

      request_data = %{
        "(request-target)" => "post /inbox",
        "host" => "remote.example",
        "date" => "Sun, 22 Mar 2026 12:00:00 GMT"
      }

      result = HTTPSignature.build_signing_string(headers, request_data)

      expected =
        "(request-target): post /inbox\nhost: remote.example\ndate: Sun, 22 Mar 2026 12:00:00 GMT"

      assert result == expected
    end
  end

  describe "sign and verify round-trip" do
    test "a signed request can be verified", %{private_pem: private_pem, public_pem: public_pem} do
      request = %{
        method: "POST",
        url: "https://remote.example/inbox",
        body: ~s({"type": "Create"})
      }

      key_id = "https://local.example/actors/123#main-key"
      signed_headers = HTTPSignature.sign(request, private_pem, key_id)

      # Verify the signature manually
      sig_header = signed_headers["Signature"]

      # Parse signature params
      params =
        sig_header
        |> String.split(",")
        |> Enum.map(fn part ->
          [key, value] = String.split(part, "=", parts: 2)
          {String.trim(key), String.trim(value, "\"")}
        end)
        |> Map.new()

      headers_to_verify = String.split(params["headers"], " ")

      request_data = %{
        "(request-target)" => "post /inbox",
        "host" => signed_headers["Host"],
        "date" => signed_headers["Date"],
        "digest" => signed_headers["Digest"]
      }

      signing_string = HTTPSignature.build_signing_string(headers_to_verify, request_data)

      [pem_entry] = :public_key.pem_decode(public_pem)
      pub_key = :public_key.pem_entry_decode(pem_entry)
      signature = Base.decode64!(params["signature"])

      assert :public_key.verify(signing_string, :sha256, signature, pub_key)
    end
  end

  describe "verify/1 — date-header freshness" do
    # The full signature path requires an HTTP fetch of the public
    # key, so we exercise the date check in isolation by building a
    # minimal conn whose Date header lies about the request time and
    # asserting the appropriate error short-circuits the with chain.
    # We expect the date check to come first — before keyId fetch.

    defp conn_with_date(date_str) do
      %Plug.Conn{
        method: "POST",
        request_path: "/inbox",
        req_headers: [
          {"signature",
           ~s|keyId="https://nope.invalid/actor#main-key",algorithm="rsa-sha256",headers="(request-target) host date",signature="ZmFrZQ=="|},
          {"date", date_str},
          {"host", "local.example"}
        ]
      }
    end

    test "rejects a missing Date header" do
      conn = %Plug.Conn{
        method: "POST",
        request_path: "/inbox",
        req_headers: [
          {"signature",
           ~s|keyId="x",algorithm="rsa-sha256",headers="(request-target)",signature="ZmFrZQ=="|}
        ]
      }

      assert {:error, :date_missing} = HTTPSignature.verify(conn)
    end

    test "rejects a Date header older than 12 hours" do
      stale =
        DateTime.utc_now()
        |> DateTime.add(-13 * 3600, :second)
        |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT")

      assert {:error, :date_too_old} = HTTPSignature.verify(conn_with_date(stale))
    end

    test "rejects a Date header in the future by more than 12 hours" do
      future =
        DateTime.utc_now()
        |> DateTime.add(13 * 3600, :second)
        |> Calendar.strftime("%a, %d %b %Y %H:%M:%S GMT")

      assert {:error, :date_too_skewed} = HTTPSignature.verify(conn_with_date(future))
    end

    test "rejects an unparseable Date header" do
      assert {:error, :date_invalid} = HTTPSignature.verify(conn_with_date("not a date"))
    end

    test "passes the freshness gate for a Date within 12h (then fails on keyId fetch)" do
      fresh = Calendar.strftime(DateTime.utc_now(), "%a, %d %b %Y %H:%M:%S GMT")

      # A fresh date passes the freshness check, then the verify chain
      # tries to fetch the public key from the (intentionally invalid)
      # keyId host — which fails. We assert the failure is anything OTHER
      # than the date errors, proving the gate let it through.
      result = HTTPSignature.verify(conn_with_date(fresh))
      assert {:error, reason} = result
      refute reason in [:date_missing, :date_too_old, :date_too_skewed, :date_invalid]
    end
  end
end
