defmodule Hybridsocial.Crypto.KeyProvider do
  @moduledoc """
  Source of the master key for at-rest field encryption. Behind a behaviour
  so the key can move from an env var (default) to Vault Transit / a cloud
  KMS later with no schema or call-site changes — swap the configured
  `:hybridsocial, :crypto_key_provider` module.
  """
  @callback master_key() :: {:ok, binary()} | {:error, term()}
end

defmodule Hybridsocial.Crypto.EnvKeyProvider do
  @moduledoc """
  Default key provider: reads the master key from application config
  (`:hybridsocial, :data_encryption_key`), which production sets from the
  `DATA_ENCRYPTION_KEY` env var in runtime.exs. Keep the value out of the
  repo and off the DB host's shell history.
  """
  @behaviour Hybridsocial.Crypto.KeyProvider

  @impl true
  def master_key do
    case Application.get_env(:hybridsocial, :data_encryption_key) do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :not_configured}
    end
  end
end
