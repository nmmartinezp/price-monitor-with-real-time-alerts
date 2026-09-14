import app from "./app.ts";
import config from "./config/app.config.ts";

app.listen(config.port, () => {
  console.log(`Server is running in http://localhost:${config.port}`);
});
