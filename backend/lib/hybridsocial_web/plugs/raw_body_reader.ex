defmodule HybridsocialWeb.Plugs.RawBodyReader do
  @moduledoc """
  Custom body reader for `Plug.Parsers` that stashes the raw request
  body into `conn.assigns[:raw_body]` BEFORE the parser consumes it.

  ActivityPub's HTTP signature scheme requires the digest to be
  computed over the exact byte sequence the peer sent — re-encoding
  the parsed JSON produces different bytes (different key order,
  whitespace) and breaks signature verification.

  Configured in endpoint.ex:

      plug Plug.Parsers,
        parsers: [...],
        body_reader: {HybridsocialWeb.Plugs.RawBodyReader, :read_body, []}

  Only stashes for POST requests against AP federation paths to
  avoid memory pressure for large multipart uploads.
  """

  @ap_paths ["/inbox", "/users/", "/actors/"]

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        {:ok, body, maybe_stash(conn, body)}

      {:more, partial, conn} ->
        {:more, partial, conn}

      {:error, _} = err ->
        err
    end
  end

  defp maybe_stash(%Plug.Conn{method: "POST", request_path: path} = conn, body) do
    if Enum.any?(@ap_paths, &String.contains?(path, &1)) do
      Plug.Conn.assign(conn, :raw_body, body)
    else
      conn
    end
  end

  defp maybe_stash(conn, _body), do: conn
end
