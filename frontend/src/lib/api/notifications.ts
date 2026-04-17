import { api } from './client.js';
import type { Notification, NotificationPreferences, PaginatedResponse } from './types.js';

export function getNotifications(params?: {
  cursor?: string;
  limit?: string;
  types?: string[];
}): Promise<PaginatedResponse<Notification>> {
  const query: Record<string, string> = {};
  if (params?.cursor) query.cursor = params.cursor;
  if (params?.limit) query.limit = params.limit;
  if (params?.types) query.types = params.types.join(',');
  return api.get('/api/v1/notifications', query);
}

export function getNotification(id: string): Promise<Notification> {
  return api.get(`/api/v1/notifications/${id}`);
}

export function markNotificationRead(id: string): Promise<void> {
  return api.post(`/api/v1/notifications/${id}/read`);
}

export function markAllNotificationsRead(): Promise<void> {
  // The backend route is `/clear` — server-side it flips every
  // unread row to read, not a hard delete. Separate name from the
  // client function because "clear the badge" is what callers
  // mean; `clearAllNotifications` is the alias kept for callers
  // that already use it.
  return api.post('/api/v1/notifications/clear');
}

export function clearAllNotifications(): Promise<void> {
  return api.post('/api/v1/notifications/clear');
}

export function getNotificationPreferences(): Promise<NotificationPreferences> {
  return api.get('/api/v1/notification_preferences');
}

export function updateNotificationPreferences(prefs: Partial<NotificationPreferences>): Promise<NotificationPreferences> {
  return api.patch('/api/v1/notification_preferences', prefs);
}
