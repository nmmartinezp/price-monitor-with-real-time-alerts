import pool from "../../config/db.config.ts";
import type { User, CreateUserInput, UpdateUserInput } from "./users.types.ts";

export async function findAllUsers(): Promise<User[] | null> {
  const result = await pool.query<User>(`SELECT * FROM users`);

  return result.rows ?? null;
}

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

export async function CreateNewUser(
  data: CreateUserInput,
): Promise<User | null> {
  const result = await pool.query<User>(
    `INSERT INTO users (email, password_hash, name, telegram_id, telegram_username, phone_number) VALUES ($1,$2,$3,$4,$5,$6) RETURNING *`,
    [
      data.email,
      data.password_hash,
      data.name,
      data.telegram_id,
      data.telegram_username,
      data.phone_number,
    ],
  );

  return result.rows[0] ?? null;
}
