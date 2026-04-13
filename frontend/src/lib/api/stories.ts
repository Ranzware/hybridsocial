import { api } from './client.js';
import type { Identity } from './types.js';

export type StoryDuration = 8 | 16 | 24;

export interface StoryMedia {
  id: string;
  content_type: string;
  url: string;
  width: number | null;
  height: number | null;
  duration: number | null;
  blurhash: string | null;
}

export interface Story {
  id: string;
  identity_id: string;
  caption: string | null;
  duration_hours: StoryDuration;
  view_count: number;
  reaction_count: number;
  published_at: string;
  expires_at: string;
  media: StoryMedia | null;
  viewed: boolean;
  user_reaction: string | null;
  is_own: boolean;
}

export interface StoryGroup {
  identity: Identity;
  stories: Story[];
  all_viewed: boolean;
  is_self: boolean;
}

export interface StoryViewer {
  viewed_at: string;
  account: Identity;
}

export interface CreateStoryRequest {
  media_id: string;
  caption?: string;
  duration_hours: StoryDuration;
}

export function listStoryFeed(): Promise<{ groups: StoryGroup[] }> {
  return api.get('/api/v1/stories');
}

export function createStory(data: CreateStoryRequest): Promise<{ story: Story }> {
  return api.post('/api/v1/stories', data);
}

export function getStory(id: string): Promise<{ story: Story }> {
  return api.get(`/api/v1/stories/${id}`);
}

export function deleteStory(id: string): Promise<void> {
  return api.delete(`/api/v1/stories/${id}`);
}

export function recordStoryView(id: string): Promise<void> {
  return api.post(`/api/v1/stories/${id}/view`);
}

export function listStoryViewers(id: string): Promise<{ viewers: StoryViewer[] }> {
  return api.get(`/api/v1/stories/${id}/viewers`);
}

export function reactToStory(id: string, emoji: string): Promise<{ reaction: { emoji: string } }> {
  return api.post(`/api/v1/stories/${id}/reactions`, { emoji });
}

export function unreactToStory(id: string): Promise<void> {
  return api.delete(`/api/v1/stories/${id}/reactions`);
}
