defmodule HybridsocialWeb.Plugs.RequireSudo do
  @moduledoc """
  Step-up auth gate for the admin panel. Requires a valid sudo window
  on the caller's access token — granted by re-entering password +
  TOTP via POST /api/v1/admin/sudo. A successful check extends the
  window (rolling TTL), so active admin sessions stay unlocked but an
  idle tab times out after `Hybridsocial.Auth.sudo_ttl_seconds/0`.

  Must run after `Auth` + `RequireAuth`.
  """
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Hybridsocial.Auth

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.assigns[:current_token] do
      nil ->
        deny(conn)

      token ->
        case Auth.check_and_extend_sudo(token) do
          {:ok, _until} -> conn
          {:error, :sudo_required} -> deny(conn)
        end
    end
  end

  defp deny(conn) do
    conn
    |> put_status(:forbidden)
    |> json(%{
      error: "auth.sudo_required",
      message: "Please re-enter your password and 2FA code to access the admin panel."
    })
    |> halt()
  end
end
