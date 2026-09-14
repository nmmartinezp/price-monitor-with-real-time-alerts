export type UserRole = "USER" | "ADMIN";

export type SubscriptionTier = "FREE" | "PRO" | "ENTERPRISE";

export interface User {
  id: string;
  email: string;
  password_hash: string;
  name: string | null;
  telegram_id: string | null;
  telegram_username: string | null;
  phone_number: string | null;
  role: UserRole;
  subscription_tier: SubscriptionTier;
  max_products: number;
  notification_preferences: {
    email: boolean;
    telegram: boolean;
    webhook: boolean;
  };
  is_active: boolean;
  last_login_at: Date | null;
  email_verified: boolean;
  verification_token: string | null;
  reset_password_token: string | null;
  reset_password_expires: Date | null;
  created_at: Date;
  updated_at: Date;
}

export interface CreateUserInput {
  email: string;
  password_hash: string;
  name?: string;
  telegram_id?: string;
  telegram_username?: string;
  phone_number?: string;
}

export interface UpdateUserInput {
  email?: string;
  name?: string;
  telegram_id?: string;
  telegram_username?: string;
  phone_number?: string;
}
