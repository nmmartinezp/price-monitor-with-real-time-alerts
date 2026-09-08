import type { Request, Response } from "express";
import * as userService from "./users.service.ts";

export async function getUser(req: Request, res: Response) {
  const { id } = req.params;

  const user = await userService.getUserById(id as string);

  return res.json({
    data: user,
  });
}
