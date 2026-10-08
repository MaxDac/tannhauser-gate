import { chromium } from "@playwright/test";
import { readFile, writeFile } from "node:fs/promises";

const staticRoot = new URL("../../priv/static/", import.meta.url);
const svg = await readFile(new URL("favicon.svg", staticRoot), "utf8");
const browser = await chromium.launch();

try {
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  await page.setContent(
    `<style>body { margin: 0; background: transparent; } img { display: block; }</style>` +
      `<img alt="" src="data:image/svg+xml;base64,${Buffer.from(svg).toString("base64")}">`,
  );

  const images = new Map();
  for (const size of [16, 32, 48, 180]) {
    await page.locator("img").evaluate((img, size) => {
      img.width = size;
      img.height = size;
    }, size);
    await page.locator("img").evaluate((img) => img.decode());
    images.set(size, await page.locator("img").screenshot({ omitBackground: true }));
  }

  for (const size of [16, 32]) {
    await writeFile(new URL(`images/favicon-${size}.png`, staticRoot), images.get(size));
  }
  await writeFile(new URL("images/apple-touch-icon.png", staticRoot), images.get(180));

  // ICO supports PNG payloads; render each size from SVG rather than downsampling.
  const sizes = [16, 32, 48];
  const directory = Buffer.alloc(6 + 16 * sizes.length);
  directory.writeUInt16LE(1, 2);
  directory.writeUInt16LE(sizes.length, 4);
  let offset = directory.length;

  for (const [index, size] of sizes.entries()) {
    const entry = 6 + 16 * index;
    const png = images.get(size);
    directory[entry] = size;
    directory[entry + 1] = size;
    directory.writeUInt16LE(1, entry + 4);
    directory.writeUInt16LE(32, entry + 6);
    directory.writeUInt32LE(png.length, entry + 8);
    directory.writeUInt32LE(offset, entry + 12);
    offset += png.length;
  }

  await writeFile(
    new URL("favicon.ico", staticRoot),
    Buffer.concat([directory, ...sizes.map((size) => images.get(size))]),
  );
} finally {
  await browser.close();
}
