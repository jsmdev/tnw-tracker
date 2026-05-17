import { test, expect, type Page } from "@playwright/test";

async function login(page: Page) {
  await page.goto("/login");
  await page.getByLabel("Email").fill("e2e@test.local");
  await page.getByLabel("Contraseña").fill("Dev1234!");
  await page.getByRole("button", { name: "Iniciar sesión" }).click();
  await page.waitForURL(/\/dashboard/);
}

/** Creates a routine and leaves the browser on its detail page. */
async function createRoutine(page: Page, name: string) {
  await page.goto("/dashboard/routines/new");
  await page.getByLabel("Nombre").fill(name);
  await page.getByRole("button", { name: "Crear rutina" }).click();
  await page.waitForURL(/\/dashboard\/routines\/[a-f0-9-]+/);
}

test.describe("Routine — CRUD", () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test("create: new routine appears in the list", async ({ page }) => {
    const name = `E2E Routine Create ${Date.now()}`;
    await createRoutine(page, name);

    await page.goto("/dashboard/routines");
    await expect(page.getByRole("cell", { name })).toBeVisible();
  });

  test("edit: change the name and see the updated value in the list", async ({ page }) => {
    const original = `E2E Routine Edit ${Date.now()}`;
    const renamed = `${original} — renamed`;

    await createRoutine(page, original);

    // We're on /dashboard/routines/{id} (edit page) right after creation.
    await page.getByLabel("Nombre").fill(renamed);
    await page.getByRole("button", { name: "Guardar cambios" }).click();

    await expect(page.getByText("Rutina actualizada correctamente")).toBeVisible();

    await page.goto("/dashboard/routines");
    await expect(page.getByRole("cell", { name: renamed })).toBeVisible();
    await expect(page.getByRole("cell", { name: original, exact: true })).toHaveCount(0);
  });

  test("delete: ConfirmDialog removes the routine from the list", async ({ page }) => {
    const name = `E2E Routine Delete ${Date.now()}`;
    await createRoutine(page, name);

    await page.goto("/dashboard/routines");
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
