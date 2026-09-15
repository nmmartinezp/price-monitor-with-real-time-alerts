import type { Request, Response } from "express";
import type { CreateUserInput } from "./users.types.ts";
import * as userService from "./users.service.ts";

export async function getUser(req: Request, res: Response) {
  const { id } = req.params;

  const user = await userService.getUserById(id.toString());

  return res.json({
    data: user,
  });
}

export async function getUsers(req: Request, res: Response) {
  const users = await userService.getAllUsers();

  return res.json({
    data: users,
  });
}

export async function createUser(req: Request, res: Response) {
  const data: CreateUserInput = req.body;

  const newUser = await userService.createUser(data);

  return res.json({
    data: newUser,
  });
}
