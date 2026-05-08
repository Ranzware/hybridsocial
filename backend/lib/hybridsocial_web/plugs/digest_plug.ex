defmodule HybridsocialWeb.Plugs.DigestPlug do
  @moduledoc """
  Validates the Digest header on incoming POST requests to inbox endpoints.

  Computes SHA-256 of the request body and compares it against the provided
  Digest header. Rejects with 401 on mismatch — and on absence, because
  allowing missing-Digest POSTs lets an attacker replay a captured
  Signature with a tampered body whenever the signed-headers list happens
  to omit "digest" (which the verifier honors as-is). Every modern
  fediverse server sends Digest on inbox POSTs; refusing without it closes
  the body-tampering window without breaking real peers.
  """
  import Plug.Conn

  require Logger

  def init(opts), do: opts

  def call(%{method: "POST"} = conn, _opts) do
    case get_req_header(conn, "digest") do
      [digest_header] ->
        verify_digest(conn, digest_header)

      [] ->
        if signature_check_enabled?() do
          Logger.warning("Inbox POST missing Digest header (#{conn.request_path})")

          conn
          |> put_status(401)
          |> Phoenix.Controller.json(%{error: "Digest header required"})
          |> halt()
        else
          # Test/dev mode where signature verification is disabled.
          # Strictness is paired with the signature gate so the same
          # switch toggles both: production enforces, fixtures pass.
          conn
        end
    end
  end

  def call(conn, _opts), do: conn

  defp signature_check_enabled? do
    Application.get_env(:hybridsocial, :federation_signature_check, true)
  end

  defp verify_digest(conn, digest_header) do
    # Read the raw body — it should already be cached by Plug.Parsers
    body = read_cached_body(conn)

    expected = "SHA-256=" <> Base.encode64(:crypto.hash(:sha256, body))

    if Plug.Crypto.secure_compare(expected, digest_header) do
      conn
    else
      Logger.warning("Digest mismatch: expected #{expected}, got #{digest_header}")

      conn
      |> put_status(401)
      |> Phoenix.Controller.json(%{error: "Invalid digest"})
      |> halt()
    end
  end

  defp read_cached_body(conn) do
    # The body should be available via conn.assigns or cached body reader
    case conn.assigns[:raw_body] do
      body when is_binary(body) ->
        body

      [body | _] when is_binary(body) ->
        body

      _ ->
        # Fallback: re-encode params as JSON (less accurate but functional)
        case Jason.encode(conn.params) do
          {:ok, json} -> json
          _ -> ""
        end
    end
  end
end
