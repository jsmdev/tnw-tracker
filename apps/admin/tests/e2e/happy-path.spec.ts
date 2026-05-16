import { test, expect } from "@playwright/test";

test("happy path: login → crear ejercicio → verlo en lista", async ({ page }) => {
  // 1. Login
  await page.goto("/login");
  await page.getByLabel("Email").fill("e2e@test.local");
  await page.getByLabel("Contraseña").fill("Dev1234!");
  await page.getByRole("button", { name: "Iniciar sesión" }).click();
  await page.waitForURL(/\/dashboard/);

  // 2. Navegar a ejercicios y crear uno
  const exerciseName = `E2E Test ${Date.now()}`;
  await page.goto("/dashboard/exercises");
  await page.getByRole("link", { name: "+ Nuevo ejercicio" }).click();
  await page.waitForURL(/\/dashboard\/exercises\/new/);

  await page.getByLabel("Nombre").fill(exerciseName);
  await page.getByLabel("Categoría").selectOption("Push");
  // Marcar el primer grupo muscular disponible
  await page.getByRole("checkbox").first().check();
  await page.getByRole("button", { name: "Crear ejercicio" }).click();
  // El server action redirige a /dashboard/exercises/{id} tras el INSERT.
  // Esperar al redirect garantiza que la creación completó antes de seguir.
  await page.waitForURL(/\/dashboard\/exercises\/[a-f0-9-]+/);

  // 3. Volver a la lista y verificar que aparece
  // Usar getByRole("cell") porque el nombre también aparece en el ConfirmDialog
  // de borrado, y getByText() falla en strict mode con múltiples matches.
  await page.goto("/dashboard/exercises");
  await expect(page.getByRole("cell", { name: exerciseName })).toBeVisible();
});
