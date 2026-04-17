defmodule HybridsocialWeb.Api.V1.PremiumReactionController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Reactions

  @doc """
  GET /api/v1/premium_reactions

  Public — anyone can fetch the catalog so the reaction picker
  can render the locked variants for free users (with an upgrade
  CTA) and unlocked variants for premium users.
  """
  def index(conn, _params) do
    emojis = Reactions.list_enabled_premium()

    json(conn, %{
      defaults: Reactions.default_reactions(),
      premium: Enum.map(emojis, &serialize/1),
      max_premium: Reactions.max_premium_slots()
    })
  end

  defp serialize(emoji) do
    %{
      id: emoji.id,
      shortcode: emoji.shortcode,
      character: emoji.character,
      image_url: emoji.image_url,
      position: emoji.position
    }
  end
end
