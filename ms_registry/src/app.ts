import express, { type Express, type Request, type Response } from "express";
import usersRoutes from "./modules/users/users.routes.ts";

const app: Express = express();

app.use(express.json());

app.use("/api/v1/users", usersRoutes);

app.get("/health", (req: Request, res: Response) => {
  res.status(200).json({
    status: "ok",
  });
});

export default app;
