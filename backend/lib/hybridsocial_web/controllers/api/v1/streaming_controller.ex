defmodule HybridsocialWeb.Api.V1.StreamingController do
  @moduledoc """
  SSE streaming controller for real-time updates.

  Uses chunked transfer encoding to stream Server-Sent Events (SSE) to clients.
  """
  use HybridsocialWeb, :controller

  @doc """
  Streams user-specific events: notifications, home timeline updates, DM notifications.
  Requires authentication.
  """
  def user(conn, _params) do
    identity = conn.assigns.current_identity

    conn = start_sse(conn)

    Phoenix.PubSub.subscribe(Hybridsocial.PubSub, "user:#{identity.id}")

    listen_loop(conn, identity.id)
  end

  @doc """
  Streams public timeline updates. Authentication optional.
  """
  def public(conn, _params) do
    conn = start_sse(conn)

    Phoenix.PubSub.subscribe(Hybridsocial.PubSub, "timeline:public")

    listen_loop(conn)
  end

  @doc """
  Streams posts with a specific hashtag. Authentication optional.
  """
  def hashtag(conn, %{"tag" => tag}) do
    conn = start_sse(conn)

    Phoenix.PubSub.subscribe(Hybridsocial.PubSub, "hashtag:#{tag}")

    listen_loop(conn)
  end

  @doc """
  Streams posts from list members. Requires authentication.
  """
  def list(conn, %{"id" => list_id}) do
    conn = start_sse(conn)

    Phoenix.PubSub.subscribe(Hybridsocial.PubSub, "list:#{list_id}")

    listen_loop(conn)
  end

  @doc """
  Streams new group posts. Requires authentication.
  """
  def group(conn, %{"id" => group_id}) do
    conn = start_sse(conn)

    Phoenix.PubSub.subscribe(Hybridsocial.PubSub, "group:#{group_id}")

    listen_loop(conn)
  end

  @doc """
  Streams update events for a single post. Used by the composer to
  show a live "edited" indicator when the author edits a post the
  user is currently replying to.

  Subscription is intentionally instance-scoped (authenticated
  pipeline) — federation peers see updates via Update activities,
  not this stream.
  """
  def post(conn, %{"id" => post_id}) do
    conn = start_sse(conn)

    Phoenix.PubSub.subscribe(Hybridsocial.PubSub, "post:#{post_id}")

    listen_loop(conn)
  end

  defp start_sse(conn) do
    conn
    |> put_resp_content_type("text/event-stream")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("x-accel-buffering", "no")
    |> send_chunked(200)
  end

  defp listen_loop(conn, viewer_id \\ nil) do
    receive do
      %{event: event, payload: payload} ->
        # DM "delivered" tick: when this user's stream is about to receive
        # a new chat message and they're not the sender, mark the
        # delivery_status row as delivered. Fire-and-forget so the SSE
        # push isn't blocked by a DB write.
        maybe_mark_delivered(viewer_id, event, payload)

        data = if is_binary(payload), do: payload, else: Jason.encode!(payload)

        case Plug.Conn.chunk(conn, "event: #{event}\ndata: #{data}\n\n") do
          {:ok, conn} ->
            listen_loop(conn, viewer_id)

          {:error, :closed} ->
            conn
        end

      :heartbeat ->
        case Plug.Conn.chunk(conn, ":heartbeat\n\n") do
          {:ok, conn} ->
            listen_loop(conn, viewer_id)

          {:error, :closed} ->
            conn
        end
    after
      30_000 ->
        # Send a heartbeat comment every 30 seconds to keep connection alive
        case Plug.Conn.chunk(conn, ":heartbeat\n\n") do
          {:ok, conn} ->
            listen_loop(conn, viewer_id)

          {:error, :closed} ->
            conn
        end
    end
  end

  defp maybe_mark_delivered(nil, _event, _payload), do: :ok

  defp maybe_mark_delivered(viewer_id, "chat.new_message", payload) when is_map(payload) do
    message_id = payload[:id] || payload["id"]
    sender = payload[:sender] || payload["sender"]
    sender_id = if is_map(sender), do: sender[:id] || sender["id"]

    if is_binary(message_id) and sender_id != viewer_id do
      Task.Supervisor.start_child(Hybridsocial.TaskSupervisor, fn ->
        Hybridsocial.Messaging.mark_delivered(message_id, viewer_id)
      end)
    end

    :ok
  end

  defp maybe_mark_delivered(_viewer_id, _event, _payload), do: :ok
end
