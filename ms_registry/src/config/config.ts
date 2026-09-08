import type { Config } from "./config.types.ts";

const config: Config = {
  port: process.env.PORT || 3000,
  db_url: process.env.DATABASE_URL || "",
  jwtSecret: process.env.JWT_SECRET || "",
  node_env: process.env.NODE_ENV || "development",
  redis_url: process.env.REDIS_URL || "",
  rabbit_url: process.env.RABBITMQ_URL || "",
};

export default config;
