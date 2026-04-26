/**
 * @tnw/shared-types
 *
 * Shared TypeScript type definitions used across the monorepo.
 * These are pure types (no runtime code) — safe to import anywhere.
 *
 * @example
 * import type { SomeType } from "@tnw/shared-types";
 */

// API response envelope
export type ApiResponse<T> =
  | { success: true; data: T }
  | { success: false; error: string; code?: string };

// Pagination
export interface PaginatedResult<T> {
  items: T[];
  total: number;
  page: number;
  pageSize: number;
  hasNextPage: boolean;
}

// Re-export domain types as they are added.
// Example:
// export type { User, UserRole } from "./user";
// export type { Quote, QuoteCategory } from "./quote";
