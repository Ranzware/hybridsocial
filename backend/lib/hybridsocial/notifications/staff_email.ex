defmodule Hybridsocial.Notifications.StaffEmail do
  @moduledoc """
  Generic fan-out for admin-targeted transactional emails. Finds
  every staff member that (a) holds any role, (b) has the required
  permission, and (c) has opted into the given notification key for
  email, then delivers a builder-produced Swoosh email to each one —
  once per throttle window per recipient.

  Throttle window is `moderation_email_throttle_seconds` (default
  600s); the same key that gates `moderation_queue` emails. We
  share it deliberately: a burst of reports shouldn't spam every
  admin either, and if an operator lowers the window they want it
  lowered uniformly.
  """

  require Logger
  import Ecto.Query

  alias Hybridsocial.{Accounts, Auth.IdentityRole, Auth.RBAC, Cache, Mailer, Notifications, Repo}
  alias Hybridsocial.Accounts.{Identity, User}

  @doc """
  `notification_key`: matches the `notification_preferences.type` a
  staff member must have set to email=true (e.g. `"admin_new_report"`).

  `required_permission`: RBAC permission the staff member must hold
  to be relevant for this event (e.g. `"reports.manage"`). Users
  without this permission are skipped — no point emailing them
  about something they can't act on.

  `build_email`: 2-arity fn `(to_email, identity) -> Swoosh.Email`.
  The identity is passed so the builder can personalize (use handle,
  display_name) and log failures against a recipient.
  """
  def dispatch(notification_key, required_permission, build_email)
      when is_binary(notification_key) and is_binary(required_permission) and
             is_function(build_email, 2) do
    throttle_sec =
      case Hybridsocial.Config.get("moderation_email_throttle_seconds", 600) do
        n when is_integer(n) and n > 0 -> n
        _ -> 600
      end

    staff_ids =
      from(r in IdentityRole,
        distinct: true,
        select: r.identity_id,
        where: is_nil(r.expires_at) or r.expires_at > ^DateTime.utc_now()
      )
      |> Repo.all()

    for identity_id <- staff_ids do
      if eligible?(identity_id, notification_key, required_permission) do
        maybe_send(identity_id, notification_key, throttle_sec, build_email)
      end
    end

    :ok
  end

  defp eligible?(identity_id, notification_key, required_permission) do
    Notifications.should_notify?(identity_id, notification_key, :email) and
      RBAC.staff?(identity_id) and
      RBAC.has_permission?(identity_id, required_permission)
  end

  defp maybe_send(identity_id, notification_key, throttle_sec, build_email) do
    # Scope the throttle per-recipient AND per-key, so getting a report
    # email doesn't suppress a backup-failure email from the same
    # window.
    throttle_key = "staff_email:#{notification_key}:#{identity_id}"

    case Cache.get(throttle_key) do
      nil ->
        # Set the flag BEFORE building the email. Two near-simultaneous
        # inserts from different processes would otherwise both race
        # past the check.
        Cache.set(throttle_key, "1", throttle_sec)

        with %Identity{} = identity <- Accounts.get_identity(identity_id),
             %User{email: email} when is_binary(email) and email != "" <-
               Accounts.get_user_by_identity(identity_id) do
          try do
            build_email.(email, identity) |> Mailer.deliver()
          rescue
            e ->
              Logger.warning(
                "staff email #{notification_key} failed for #{identity_id}: #{Exception.message(e)}"
              )
          end
        end

      _ ->
        :ok
    end
  end
end
