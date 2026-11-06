const {defineConfig, devices} = require("@playwright/test")

const port = process.env.PLAYWRIGHT_PORT || "4791"
const baseURL = `http://127.0.0.1:${port}`

module.exports = defineConfig({
  testDir: "./test/browser",
  fullyParallel: true,
  workers: process.env.CI ? 2 : 3,
  forbidOnly: Boolean(process.env.CI),
  retries: 0,
  reporter: [["list"], ["html", {open: "never"}]],
  use: {
    baseURL,
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  projects: [
    {name: "desktop", use: {...devices["Desktop Chrome"], viewport: {width: 1440, height: 1000}}},
    {name: "mobile", use: {...devices["Pixel 7"], viewport: {width: 390, height: 844}}},
  ],
  webServer: {
    command: "mix assets.build && mix phx.server",
    env: {MIX_ENV: "test", PHX_SERVER: "true", PORT: port},
    url: baseURL,
    reuseExistingServer: false,
    timeout: 120_000,
    gracefulShutdown: {signal: "SIGTERM", timeout: 5_000},
  },
})
