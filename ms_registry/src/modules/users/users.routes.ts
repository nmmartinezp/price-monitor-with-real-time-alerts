import { Router } from "express";
import * as userController from "./users.controller.ts";

const router = Router();

router.get("/:id", userController.getUser);
router.get("/", userController.getUsers);
router.post("/create", userController.createUser);

export default router;
