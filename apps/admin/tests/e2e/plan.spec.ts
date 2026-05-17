import { test, expect, type Page } from "@playwright/test";

async function login(page: Page) {
  await page.goto("/login");
  await page.getByLabel("Email").fill("e2e@test.local");
  await page.getByLabel("Contraseña").fill("Dev1234!");
  await page.getByRole("button", { name: "Iniciar sesión" }).click();
  await page.waitForURL(/\/dashboard/);
}

/** Creates a plan and leaves the browser on its detail page. */
async function createPlan(page: Page, name: string) {
  await page.goto("/dashboard/plans/new");
  await page.getByLabel("Nombre").fill(name);
  await page.getByRole("button", { name: "Crear plan" }).click();
  await page.waitForURL(/\/dashboard\/plans\/[a-f0-9-]+/);
}

test.describe("Plan — CRUD", () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test("create: new plan appears in the list", async ({ page }) => {
    const name = `E2E Plan Create ${Date.now()}`;
    await createPlan(page, name);

    await page.goto("/dashboard/plans");
    await expect(page.getByRole("cell", { name })).toBeVisible();
  });

  test("edit: change the name and see the updated value in the list", async ({ page }) => {
    const original = `E2E Plan Edit ${Date.now()}`;
    const renamed = `${original} — renamed`;

    await createPlan(page, original);

    // We're on /dashboard/plans/{id} (edit page) right after creation.
    await page.getByLabel("Nombre").fill(renamed);
    await page.getByRole("button", { name: "Guardar cambios" }).click();

    // The update action returns a success message (no redirect).
    await expect(page.getByText("Plan actualizado correctamente")).toBeVisible();

    await page.goto("/dashboard/plans");
    await expect(page.getByRole("cell", { name: renamed })).toBeVisible();
    await expect(page.getByRole("cell", { name: original, exact: true })).toHaveCount(0);
  });

  test("delete: ConfirmDialog removes the plan from the list", async ({ page }) => {
    const name = `E2E Plan Delete ${Date.now()}`;
    await createPlan(page, name);

    await page.goto("/dashboard/plans");
    await expect(page.getByRole("cell", { name })).toBeVisible();

    // Open ConfirmDialog scoped to this plan's row.
    const row = page.getByRole("row", { name: new RegExp(name) });
    await row.getByRole("button", { name: "Eliminar" }).click();

    const dialog = page.getByRole("dialog");
    await expect(dialog).toBeVisible();
    await expect(dialog.getByText(`¿Seguro que deseas eliminar "${name}"?`)).toBeVisible();

    await dialog.getByRole("button", { name: "Eliminar" }).click();

    await expect(page.getByRole("cell", { name, exact: true })).toHaveCount(0);
  });
});
