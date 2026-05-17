import { test, expect, type Page } from "@playwright/test";

async function login(page: Page) {
  await page.goto("/login");
  await page.getByLabel("Email").fill("e2e@test.local");
  await page.getByLabel("Contraseña").fill("Dev1234!");
  await page.getByRole("button", { name: "Iniciar sesión" }).click();
  await page.waitForURL(/\/dashboard/);
}

/** Creates an exercise and leaves the browser on its detail page. */
async function createExercise(page: Page, name: string) {
  await page.goto("/dashboard/exercises/new");
  await page.getByLabel("Nombre").fill(name);
  await page.getByLabel("Categoría").selectOption("Push");
  await page.getByRole("checkbox").first().check();
  await page.getByRole("button", { name: "Crear ejercicio" }).click();
  // Server action redirects to the new detail page; wait for it.
  await page.waitForURL(/\/dashboard\/exercises\/[a-f0-9-]+/);
}

test.describe("Exercise — edit and delete", () => {
  test.beforeEach(async ({ page }) => {
    await login(page);
  });

  test("edit: change the name and see the updated value in the list", async ({ page }) => {
    const original = `E2E Edit ${Date.now()}`;
    const renamed = `${original} — renamed`;

    await createExercise(page, original);

    // We're on /dashboard/exercises/{id} (the edit page) right after creation.
    await page.getByLabel("Nombre").fill(renamed);
    await page.getByRole("button", { name: "Guardar cambios" }).click();

    // The update server action returns a success message (no redirect).
    await expect(page.getByText("Ejercicio actualizado correctamente")).toBeVisible();

    // The renamed exercise should appear in the list.
    await page.goto("/dashboard/exercises");
    await expect(page.getByRole("cell", { name: renamed })).toBeVisible();
    // …and the original name should NOT.
    await expect(page.getByRole("cell", { name: original, exact: true })).toHaveCount(0);
  });

  test("delete: ConfirmDialog removes the exercise from the list", async ({ page }) => {
    const name = `E2E Delete ${Date.now()}`;
    await createExercise(page, name);

    // Back to the list.
    await page.goto("/dashboard/exercises");
    await expect(page.getByRole("cell", { name })).toBeVisible();

    // Open ConfirmDialog: scope to the row for this exercise so we don't
    // accidentally trigger another row's delete button.
    const row = page.getByRole("row", { name: new RegExp(name) });
    await row.getByRole("button", { name: "Eliminar" }).click();

    // The dialog should appear with the confirmation question.
    const dialog = page.getByRole("dialog");
    await expect(dialog).toBeVisible();
    await expect(dialog.getByText(`¿Seguro que deseas eliminar "${name}"?`)).toBeVisible();

    // Confirm.
    await dialog.getByRole("button", { name: "Eliminar" }).click();

    // After the soft-delete server action runs (redirects back to the list),
    // the cell with this exercise name should no longer be visible.
    await expect(page.getByRole("cell", { name, exact: true })).toHaveCount(0);
  });
});
