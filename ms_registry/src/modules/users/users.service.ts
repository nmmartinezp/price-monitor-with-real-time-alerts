import * as userRepository from "./users.repository.ts";

export async function getUserById(id: string) {
  const user = await userRepository.findById(id);

  if (!user) {
    throw new Error("USER_NOT_FOUND");
  }

  return user;
}
