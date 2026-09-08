export interface User {
  id: string;
  email: string;
  name: string | null;
  telegramId: string | null;
  telegramUsername: string | null;
  phoneNumber: string | null;
  role: string;
  subscriptionTier: string;
  maxProducts: number;
  notificationPreferences: Record<string, unknown>;
  isActive: boolean;
  lastLoginAt: Date | null;
  emailVerified: boolean;
  createdAt: Date;
  updatedAt: Date;
}
