import { Router } from "express";
import * as userController from "./users.controller.ts";

const router = Router();

router.get("/:id", userController.getUser);

export default router;
