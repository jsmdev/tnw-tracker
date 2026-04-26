/**
 * @tnw/zod-schemas
 *
 * Shared Zod validation schemas used across the monorepo.
 * Import from here instead of defining schemas in each app.
 *
 * @example
 * import { someSchema } from "@tnw/zod-schemas";
 */

export { z } from "zod";

// Re-export schemas as they are added.
// Example:
// export { userSchema, createUserSchema } from "./user";
// export { quoteSchema } from "./quote";
