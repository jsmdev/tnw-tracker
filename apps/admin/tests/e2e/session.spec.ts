import { test, expect, type Page } from "@playwright/test";

async function login(page: Page) {
  await page.goto("/login");
  await page.getByLabel("Email").fill("e2e@test.local");
  await page.getByLabel("Contraseña").fill("Dev1234!");
  await page.getByRole("button", { name: "Iniciar sesión" }).click();
  await page.waitForURL(/\/dashboard/);
}

/** Creates a session and leaves the browser on its detail page. */
async function createSession(page: Page, name: string) {
  await page.goto("/dashboard/sessions/new");
  await page.getByLabel("Nombre").fill(name);
  await page.getByRole("button", { name: "Crear sesión" }).click();
  await page.waitForURL(/\/dashboard\/sessions\/[a-f0-9-]+/);
}

test.describe("Session — CRUD", () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test("create: new session appears in the list", async ({ page }) => {
    const name = `E2E Session Create ${Date.now()}`;
    await createSession(page, name);

    await page.goto("/dashboard/sessions");
    await expect(page.getByRole("cell", { name })).toBeVisible();
  });

  test("edit: change the name and see the updated value in the list", async ({ page }) => {
    const original = `E2E Session Edit ${Date.now()}`;
    const renamed = `${original} — renamed`;

    await createSession(page, original);

    await page.getByLabel("Nombre").fill(renamed);
    await page.getByRole("button", { name: "Guardar cambios" }).click();

    await expect(page.getByText("Sesión actualizada correctamente")).toBeVisible();

    await page.goto("/dashboard/sessions");
    await expect(page.getByRole("cell", { name: renamed })).toBeVisible();
    await expect(page.getByRole("cell", { name: original, exact: true })).toHaveCount(0);
  });

  // Sessions are HARD deleted (no is_active flag), unlike plans/routines/exercises.
  // The list still reflects the disappearance the same way.
  test("delete: ConfirmDialog removes the session from the list (hard delete)", async ({
    page,
  }) => {
    const name = `E2E Session Delete ${Date.now()}`;
    await createSession(page, name);

    await page.goto("/dashboard/sessions");
    await expect(page.getByRole("cell", { name })).toBeVisible();

    const row = page.getByRole("row", { name: new RegExp(name) });
    await row.getByRole("button", { name: "Eliminar" }).click();

    const dialog = page.getByRole("dialog");
    await expect(dialog).toBeVisible();
    await expect(dialog.getByText(`¿Seguro que deseas eliminar "${name}"?`)).toBeVisible();

    await dialog.getByRole("button", { name: "Eliminar" }).click();

    await expect(page.getByRole("cell", { name, exact: true })).toHaveCount(0);
  });
});
