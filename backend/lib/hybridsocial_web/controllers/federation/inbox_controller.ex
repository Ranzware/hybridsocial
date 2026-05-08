defmodule HybridsocialWeb.Federation.InboxController do
  use HybridsocialWeb, :controller

  alias Hybridsocial.Federation
  alias Hybridsocial.Federation.{Inbox, ActivityMapper}

  plug HybridsocialWeb.Plugs.DigestPlug

  require Logger

  @doc """
  Handles POST to /actors/:id/inbox (actor-specific inbox).
  """
  def actor_inbox(conn, _params) do
    # Use body_params, not the merged params — the route's :id would
    # otherwise shadow the activity's own "id" field.
    process_inbox(conn, conn.body_params)
  end

  @doc """
  Handles POST to /inbox (shared inbox).
  """
  def shared_inbox(conn, _params) do
    process_inbox(conn, conn.body_params)
  end

  defp process_inbox(conn, activity) do
    with {:ok, key_id} <- verify_http_signature(conn),
         :ok <- check_actor_matches_key(activity, key_id),
         :ok <- check_sender_policy(activity),
         :ok <- check_dedup(activity),
         {:ok, _result} <- Inbox.process(activity) do
      # Record the activity for dedup
      record_activity_dedup(activity)

      conn
      |> put_status(202)
      |> json(%{status: "accepted"})
    else
      {:error, :signature_invalid} ->
        conn
        |> put_status(401)
        |> json(%{error: "Invalid HTTP signature"})

      {:error, :domain_suspended} ->
        conn
        |> put_status(403)
        |> json(%{error: "Domain suspended"})

      {:error, :duplicate_activity} ->
        # Silently accept duplicates to be idempotent
        conn
        |> put_status(202)
        |> json(%{status: "accepted"})

      {:error, reason} ->
        Logger.warning("Inbox processing failed: #{inspect(reason)}")

        conn
        |> put_status(422)
        |> json(%{error: "Unprocessable activity"})
    end
  end

  # Verify HTTP signatures on incoming federation requests. Returns
  # `{:ok, key_id}` so the caller can cross-check the keyId's actor
  # against the activity's claimed actor — without that check, a valid
  # fediverse key can sign an activity claiming to come from anyone.
  defp verify_http_signature(conn) do
    if Application.get_env(:hybridsocial, :federation_signature_check, true) do
      case Hybridsocial.Federation.HTTPSignature.verify(conn) do
        {:ok, key_id} ->
          {:ok, key_id}

        {:error, reason} ->
          Logger.warning("HTTP signature verification failed: #{inspect(reason)}")
          {:error, :signature_invalid}
      end
    else
      # Test/dev bypass — never used in production.
      {:ok, :signature_check_disabled}
    end
  end

  # Cross-check that the keyId of the verified signature corresponds to
  # the actor named in the activity. Without this, an attacker holding
  # any valid fediverse key could sign an activity body claiming to be
  # from a different actor (`{"actor": "https://victim/users/X", ...}`)
  # and we'd happily accept it.
  #
  # The match is at the *origin* level: keyId
  # `https://example.com/users/foo#main-key` may sign for actor
  # `https://example.com/users/foo` (most common) but not for
  # `https://other.com/users/anything`. We compare the URL origin
  # (scheme + host + port) of `key_id` and `activity["actor"]`.
  # Same-origin signing is what every spec-compliant peer does and
  # blocks cross-origin actor spoofing without breaking shared inboxes
  # that legitimately fan out one actor's key across many activities.
  defp check_actor_matches_key(_activity, :signature_check_disabled), do: :ok

  defp check_actor_matches_key(%{"actor" => actor_url}, key_id)
       when is_binary(actor_url) and is_binary(key_id) do
    actor_origin = origin(actor_url)
    key_origin = origin(key_id)

    cond do
      is_nil(actor_origin) or is_nil(key_origin) ->
        Logger.warning("Inbox: missing origin on actor=#{actor_url} keyId=#{key_id}")
        {:error, :signature_invalid}

      actor_origin != key_origin ->
        Logger.warning(
          "Inbox: cross-origin signature rejected — actor origin #{actor_origin} != keyId origin #{key_origin}"
        )

        {:error, :signature_invalid}

      true ->
        :ok
    end
  end

  defp check_actor_matches_key(_activity, _key_id), do: {:error, :missing_actor}

  defp origin(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when is_binary(scheme) and is_binary(host) ->
        port = if URI.parse(url).port, do: ":#{URI.parse(url).port}", else: ""
        "#{scheme}://#{host}#{port}"

      _ ->
        nil
    end
  end

  # Check instance policy for the sender's domain using the Federation context.
  defp check_sender_policy(%{"actor" => actor_ap_id}) when is_binary(actor_ap_id) do
    domain = ActivityMapper.extract_domain(actor_ap_id)

    if domain do
      if Federation.domain_allowed?(domain) do
        :ok
      else
        {:error, :domain_suspended}
      end
    else
      {:error, :invalid_actor}
    end
  end

  defp check_sender_policy(_), do: {:error, :missing_actor}

  # Check for duplicate activities using the Federation dedup system.
  defp check_dedup(%{"id" => activity_id}) when is_binary(activity_id) do
    activity_hash = :crypto.hash(:sha256, activity_id) |> Base.encode16(case: :lower)

    if Federation.deduplicate?(activity_hash) do
      {:error, :duplicate_activity}
    else
      :ok
    end
  end

  defp check_dedup(_), do: :ok

  # Record a processed activity for future dedup checks.
  defp record_activity_dedup(%{"id" => activity_id}) when is_binary(activity_id) do
    activity_hash = :crypto.hash(:sha256, activity_id) |> Base.encode16(case: :lower)
    Federation.record_dedup(activity_hash, activity_id)
  end

  defp record_activity_dedup(_), do: :ok
end
