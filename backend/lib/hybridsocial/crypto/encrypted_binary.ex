defmodule Hybridsocial.Crypto.EncryptedBinary do
  @moduledoc """
  Transparent at-rest encryption for a `text` column. Encrypts on write,
  decrypts on read, so read sites (e.g. the federation signer reading a
  private key) need no changes.

      field :private_key, Hybridsocial.Crypto.EncryptedBinary,
        context: "identity.private_key"

  The `context` binds the ciphertext to this field (it's the HKDF info and
  the GCM AAD), so a blob can't be replayed into a different column. Legacy
  plaintext rows read back unchanged until backfilled.
  """
  use Ecto.ParameterizedType

  alias Hybridsocial.Crypto

  @impl true
  def type(_params), do: :string

  @impl true
  def init(opts) do
    %{context: Keyword.fetch!(opts, :context)}
  end

  @impl true
  def cast(nil, _params), do: {:ok, nil}
  def cast(value, _params) when is_binary(value), do: {:ok, value}
  def cast(_value, _params), do: :error

  @impl true
  def dump(nil, _dumper, _params), do: {:ok, nil}

  def dump(value, _dumper, %{context: context}) when is_binary(value) do
    {:ok, Crypto.encrypt(value, context)}
  end

  def dump(_value, _dumper, _params), do: :error

  @impl true
  def load(nil, _loader, _params), do: {:ok, nil}

  def load(value, _loader, %{context: context}) when is_binary(value) do
    {:ok, Crypto.decrypt(value, context)}
  end

  @impl true
  def equal?(a, b, _params), do: a == b
end
