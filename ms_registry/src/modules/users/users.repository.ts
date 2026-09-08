// import pool from "../../config/db.config.ts";
import type { User } from "./users.types.ts";

export async function findById(id: string): Promise<User | null> {
  /* const result = await pool.query(
    `
      SELECT
        id,
        email,
        name,
        telegram_id,
        telegram_username,
        phone_number,
        role,
        subscription_tier,
        max_products,
        notification_preferences,
        is_active,
        last_login_at,
        email_verified,
        created_at,
        updated_at
      FROM users
      WHERE id = $1
    `,
    [id],
  );

  return result.rows[0] ?? null; */
  return null;
}
