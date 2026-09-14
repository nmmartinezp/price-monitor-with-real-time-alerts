import config from "./app.config.ts";
import { Pool } from "pg";

const pool = new Pool({
  connectionString: config.db_url,
});

export default pool;
