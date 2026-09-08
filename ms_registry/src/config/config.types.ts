export type Config = {
  port: number | string;
  db_url: string;
  jwtSecret: string;
  node_env: string;
  redis_url: string;
  rabbit_url: string;
};
