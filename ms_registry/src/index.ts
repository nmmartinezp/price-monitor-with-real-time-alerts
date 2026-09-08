import express, { type Express, type Request, type Response } from "express";
import config from "./config/config.ts";

const app: Express = express();

app.get("/", (req: Request, res: Response) => {
  res.send("Hello NIKI!");
});

app.listen(config.port, () => {
  console.log(`Example app listening on port ${config.port}`);
});
