import { api } from './client.js';
import type { PostDraft } from './types.js';

export type DraftInput = Partial<
  Omit<PostDraft, 'id' | 'created_at' | 'updated_at'>
>;

export async function listDrafts(): Promise<PostDraft[]> {
  const response = await api.get<{ drafts: PostDraft[] }>('/api/v1/drafts');
  return response?.drafts ?? [];
}

export async function getDraft(id: string): Promise<PostDraft> {
  return api.get<PostDraft>(`/api/v1/drafts/${id}`);
}

export async function createDraft(input: DraftInput): Promise<PostDraft> {
  return api.post<PostDraft>('/api/v1/drafts', input);
}

export async function updateDraft(
  id: string,
  input: DraftInput,
): Promise<PostDraft> {
  return api.put<PostDraft>(`/api/v1/drafts/${id}`, input);
}

export async function deleteDraft(id: string): Promise<void> {
  await api.delete<void>(`/api/v1/drafts/${id}`);
}
