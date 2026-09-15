import type { CreateUserInput } from "./users.types.ts";
import * as userRepository from "./users.repository.ts";

export async function getUserById(id: string) {
  const user = await userRepository.findUserById(id);

  if (!user) {
    throw new Error("USER_NOT_FOUND");
  }

  return user;
}

export async function getAllUsers() {
  const users = await userRepository.findAllUsers();

  if (!users) {
    throw new Error("USERS_NOT_EXIST");
  }

  return users;
}

export async function createUser(data: CreateUserInput) {
  return userRepository.CreateNewUser(data);
}
