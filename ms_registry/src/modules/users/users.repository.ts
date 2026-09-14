import pool from "../../config/db.config.ts";
import type { User, CreateUserInput, UpdateUserInput } from "./users.types.ts";

export async function findUserById(id: string): Promise<User | null> {
  const result = await pool.query<User>(
    `
      SELECT *
      FROM users
      WHERE id = $1
    `,
    [id],
  );

  return result.rows[0] ?? null;
}
